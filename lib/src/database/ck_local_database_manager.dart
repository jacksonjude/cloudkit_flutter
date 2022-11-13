import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:sqlbrite/sqlbrite.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '/src/parsing/ck_field_structure.dart';
import '/src/parsing/ck_record_parser.dart';
import '/src/parsing/ck_record_structure.dart';
import '/src/parsing/types/ck_field_type.dart';
import '/src/ck_constants.dart';
import '/src/api/request_models/ck_zone.dart';
import '/src/api/request_models/ck_sync_token.dart';
import '/src/api/request_models/ck_zone_operation.dart';
import '/src/api/request_models/ck_subscription_operation.dart';
import '/src/api/request_models/ck_record_change.dart';
import '/src/api/ck_notification_manager.dart';
import '/src/api/ck_operation.dart';
import '/src/api/ck_api_manager.dart';
import '/src/api/ck_subscription.dart';
import 'ck_database_event.dart';

/// The manager for storing CloudKit records in a local SQLite database,
class CKLocalDatabaseManager
{
  static const _defaultDatabaseName = "cloudkit_flutter_sync.db";
  static const _defaultVersionNumber = 1;

  static const _uuidToTypeTableName = "_UUID_Type";
  static const _assetCacheTableName = "_Asset_Cache";

  final _databaseName;
  final _databaseVersion;
  late final CKDatabase cloudDatabase;
  late final CKZone cloudZone;
  late final CKAPIManager? _apiManager;
  late final BriteDatabase _databaseInstance;

  CKLocalDatabaseManager(this._databaseName, this._databaseVersion);

  static CKLocalDatabaseManager? _instance;

  /// Get the shared instance of the [CKLocalDatabaseManager].
  static CKLocalDatabaseManager get shared
  {
    if (_instance == null) _instance = CKLocalDatabaseManager(_defaultDatabaseName, _defaultVersionNumber);
    return _instance!;
  }

  late final CKDatabaseEventList _databaseEventHistory;

  List<Type>? _syncRecordTypes;
  StreamSubscription<CKNotification>? _notificationStreamSubscription;
  CKSyncToken? _syncToken;

  /// Initialize the shared local database for the application. Optionally, a custom [CKLocalDatabaseManager] can be passed in.
  static Future<void> initDatabase(Map<Type,CKRecordStructure> recordStructures, {CKDatabase? database, CKZone? zone, CKLocalDatabaseManager? manager}) async
  {
    WidgetsFlutterBinding.ensureInitialized();

    var managerToInit = manager ?? CKLocalDatabaseManager.shared;

    managerToInit.cloudDatabase = database ?? CKDatabase.PRIVATE_DATABASE;
    managerToInit.cloudZone = zone ?? CKZone();

    const resetOnLaunch = false;
    if (resetOnLaunch)
    {
      deleteDatabase(managerToInit._databaseName);
      managerToInit._resetSyncToken();
    }

    var databaseInstance = await openDatabase(
      managerToInit._databaseName,
      version: managerToInit._databaseVersion,
      onCreate: (Database db, int version) async {
        for (var recordStructureEntry in recordStructures.entries)
        {
          var recordStructure = recordStructureEntry.value;

          var tableColumnDefinitions = recordStructure.fields.where((fieldStructure) {
            return !fieldStructure.type.sqlite.isList;
          }).map((fieldStructure) {
            return '`${fieldStructure.ckName}` ${fieldStructure.type.sqlite.baseType}${fieldStructure.ckName == CKConstants.RECORD_NAME_FIELD ? " PRIMARY KEY" : ""}';
          }).join(", ");

          await db.execute('CREATE TABLE `${recordStructure.ckRecordType}` ($tableColumnDefinitions, `${CKConstants.RECORD_CHANGE_TAG_FIELD}` TEXT)');

          var listFields = recordStructure.fields.where((fieldStructure) {
            return fieldStructure.type.sqlite.isList;
          });
          for (var fieldStructure in listFields)
          {
            await db.execute('CREATE TABLE `${recordStructure.ckRecordType}_${fieldStructure.ckName}` (`${recordStructure.ckRecordType}ID` TEXT, `${fieldStructure.ckName}` ${fieldStructure.type.sqlite.baseType})');
          }
        }

        await db.execute('CREATE TABLE `$_uuidToTypeTableName` (uuid TEXT, type TEXT)');
        await db.execute('CREATE TABLE `$_assetCacheTableName` (fieldPath TEXT, checksum TEXT, cache BLOB)');
      }
    );

    managerToInit._databaseInstance = BriteDatabase(databaseInstance);

    managerToInit._databaseEventHistory = CKDatabaseEventList(managerToInit);

    managerToInit._syncRecordTypes = recordStructures.keys.toList();
  }

  /// Begin cloud sync for the given APNS environment and [CKAPIManager].
  Future<void> initCloudSync(CKAPNSEnvironment environment, {String? subscriptionID, CKAPIManager? apiManager}) async
  {
    _apiManager = apiManager;
    _syncToken = await _fetchSyncToken();

    var lookupZoneOperation = CKZoneLookupOperation([cloudZone], cloudDatabase);
    var lookupZoneOperationCallback = await lookupZoneOperation.execute();

    var shouldCreateZone = (lookupZoneOperationCallback.response?.length ?? 0) == 0;
    if (shouldCreateZone)
    {
      var createZoneOperation = CKZoneModifyOperation([
        CKZoneOperation(cloudZone, CKZoneOperationType.CREATE)
      ], cloudDatabase);
      await createZoneOperation.execute();
    }

    subscriptionID ??= ("${cloudZone.toJSON()["zoneName"]}-${cloudDatabase.toString()}");
    var lookupSubscriptionOperation = CKSubscriptionLookupOperation([subscriptionID], cloudDatabase);
    var lookupSubscriptionCallback = await lookupSubscriptionOperation.execute();

    var shouldCreateSubscription = (lookupSubscriptionCallback.response?.length ?? 0) == 0;
    if (shouldCreateSubscription)
    {
      var syncZoneSubscription = CKZoneSubscription(subscriptionID, cloudZone);
      var createSubscriptionsOperation = CKSubscriptionModifyOperation([
        CKSubscriptionOperation(CKSubscriptionOperationType.CREATE, syncZoneSubscription)
      ], cloudDatabase);
      await createSubscriptionsOperation.execute();
    }

    var notificationStream = await CKNotificationManager.shared.registerForRemoteNotifications(environment, apiManager: _apiManager);
    _notificationStreamSubscription = notificationStream.listen((notification) {
      syncCloudData();
    });

    await syncCloudData();
  }

  /// Sync cloud data for the current zone and sync token.
  Future<void> syncCloudData() async
  {
    var zoneChangesOperation = CKRecordZoneChangesOperation(
      CKDatabase.PRIVATE_DATABASE,
      zoneID: cloudZone,
      syncToken: _syncToken,
      recordTypes: _syncRecordTypes,
      apiManager: _apiManager
    );
    var changesOperationCallback = await zoneChangesOperation.execute();

    var groupedChanges = changesOperationCallback.recordChanges.groupBy((recordChange) => recordChange.recordMetadata.localType);
    for (var changesEntry in groupedChanges.entries)
    {
      var recordType = changesEntry.key;
      var recordChanges = changesEntry.value;
      if (recordType != dynamic)
      {
        var recordStructure = CKRecordParser.getRecordStructureFromLocalType(recordType!);
        var recordTypeAnnotation = recordStructure.recordTypeAnnotation!;

        for (var recordChange in recordChanges)
        {
          await addEvent(recordTypeAnnotation.createCloudEvent(recordChange), shouldSync: false);
        }
      }
      else
      {
        recordChanges.removeWhere((recordChange) => recordChange.operationType != CKRecordOperationType.DELETE);
        for (var recordChange in recordChanges)
        {
          await addEvent(CKDatabaseEvent(recordChange, CKDatabaseEventSource.cloud), shouldSync: false);
        }
      }
    }

    _syncToken = changesOperationCallback.syncToken;
    _saveSyncToken(_syncToken);

    await synchronizeAllEvents();
  }

  Future<CKSyncToken?> _fetchSyncToken() async
  {
    WidgetsFlutterBinding.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    var rawSyncToken = prefs.getString(CKConstants.LOCAL_DATABASE_SYNC_TOKEN_KEY + "-" + _databaseName);
    return rawSyncToken != null ? CKSyncToken(rawSyncToken) : null;
  }

  Future<void> _saveSyncToken(CKSyncToken? syncToken) async
  {
    if (syncToken == null) return;

    WidgetsFlutterBinding.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(CKConstants.LOCAL_DATABASE_SYNC_TOKEN_KEY + "-" + _databaseName, syncToken.toString());
  }

  /// End cloud sync notifications.
  Future<void> stopCloudSync() async
  {
    await _notificationStreamSubscription?.cancel();
  }

  Future<void> _resetSyncToken() async
  {
    WidgetsFlutterBinding.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(CKConstants.LOCAL_DATABASE_SYNC_TOKEN_KEY + "-" + _databaseName);
  }

  Future<Map<String, dynamic>> _formatForSQLite<T>(Map<String, dynamic> recordJSON, {CKLocalDatabaseBatch? batch}) async
  {
    recordJSON = Map.of(recordJSON);

    var recordStructure = CKRecordParser.getRecordStructureFromLocalType(T);

    for (var field in recordStructure.fields)
    {
      if (recordJSON[field.ckName] != null)
      {
        switch (field.type)
        {
          case CKFieldType.REFERENCE_TYPE:
            recordJSON[field.ckName] = recordJSON[field.ckName][CKConstants.RECORD_NAME_FIELD];
            break;

          case CKFieldType.LIST_REFERENCE_TYPE:
            recordJSON[field.ckName] = (recordJSON[field.ckName] as List<Map<String, dynamic>>).map((referenceJSON) => referenceJSON[CKConstants.RECORD_NAME_FIELD]).toList();
            break;

          case CKFieldType.ASSET_TYPE:
            recordJSON[field.ckName] = jsonEncode(recordJSON[field.ckName]);
            break;
        }
      }

      if (field.type.sqlite.isList)
      {
        List objectsToInsert = recordJSON[field.ckName] ?? [];
        var rawExistingObjectsMap = await _databaseInstance.query('`${recordStructure.ckRecordType}_${field.ckName}`', where: '`${recordStructure.ckRecordType}ID` = ?', whereArgs: [recordJSON[CKConstants.RECORD_NAME_FIELD]]);
        var existingObjects = rawExistingObjectsMap.map((keyPair) => keyPair[field.ckName]).toList();

        objectsToInsert.removeWhere((element) {
          var existingIndex = existingObjects.indexOf(element);
          if (existingIndex == -1) return false;

          existingObjects.removeAt(existingIndex);
          return true;
        });

        var insertBatch = batch?._briteBatch ?? _databaseInstance.batch();
        objectsToInsert.forEach((element) {
          insertBatch.insert('`${recordStructure.ckRecordType}_${field.ckName}`', {'`${recordStructure.ckRecordType}ID`': recordJSON[CKConstants.RECORD_NAME_FIELD], field.ckName: element});
        });
        if (batch == null) await insertBatch.commit();

        recordJSON.remove(field.ckName);
      }
    }

    return recordJSON;
  }

  Future<Map<String, dynamic>> _decodeFromSQLite<T>(Map<String, dynamic> rawJSON) async
  {
    rawJSON = Map.of(rawJSON);
    var recordStructure = CKRecordParser.getRecordStructureFromLocalType(T);

    for (var field in recordStructure.fields)
    {
      if (field.type.sqlite.isList)
      {
        var fieldValuePairs = await queryMapBySQL('SELECT `${field.ckName}` FROM `${recordStructure.ckRecordType}_${field.ckName}` WHERE `${recordStructure.ckRecordType}ID` = ?', args: [rawJSON[CKConstants.RECORD_NAME_FIELD]]);
        rawJSON[field.ckName] = fieldValuePairs.map((fieldValuePair) => fieldValuePair[field.ckName]).toList();
      }

      if (rawJSON[field.ckName] != null)
      {
        switch (field.type)
        {
          case CKFieldType.REFERENCE_TYPE:
            rawJSON[field.ckName] = {
              CKConstants.RECORD_NAME_FIELD: rawJSON[field.ckName],
              "database": cloudDatabase,
              "zone": cloudZone
            };
            break;

          case CKFieldType.LIST_REFERENCE_TYPE:
            rawJSON[field.ckName] = (rawJSON[field.ckName] as List).map((referenceID) => {
              CKConstants.RECORD_NAME_FIELD: referenceID,
              "database": cloudDatabase,
              "zone": cloudZone
            }).toList();
            break;

          case CKFieldType.ASSET_TYPE:
            rawJSON[field.ckName] = jsonDecode(rawJSON[field.ckName]);
            break;
        }
      }
    }

    return rawJSON;
  }

  /// Query records by where SQL.
  Future<List<T>> query<T extends Object>([String? where, List? whereArgs]) async
  {
    var recordStructure = CKRecordParser.getRecordStructureFromLocalType(T);

    var queryResults = await _databaseInstance.query(recordStructure.ckRecordType, where: where, whereArgs: whereArgs);

    List<T> localObjectResults = [];
    for (var queryResult in queryResults)
    {
      localObjectResults.add(await _convertFromSQLiteMap<T>(queryResult));
    }
    return localObjectResults;
  }

  /// Query a record by id.
  Future<T?> queryByID<T extends Object>(String recordID, {CKRecordStructure? recordStructure}) async
  {
    recordStructure ??= CKRecordParser.getRecordStructureFromLocalType(T);

    var queryResults = await _databaseInstance.query(recordStructure.ckRecordType, where: '${CKConstants.RECORD_NAME_FIELD} = ?', whereArgs: [recordID]);
    if (queryResults.length == 0) return null;

    return _convertFromSQLiteMap<T>(queryResults[0]);
  }

  /// Query a cached asset for a given checksum.
  Future<Uint8List?> queryAssetCache(String checksum) async
  {
    var queryResults = await queryMapBySQL('SELECT * FROM `$_assetCacheTableName` WHERE checksum = ?', args: [checksum]);
    if (queryResults.length == 0) return null;
    return queryResults[0]["cache"];
  }

  /// Query the changeTag for a given metadata.
  Future<String?> queryChangeTag(CKRecordMetadata metadata) async
  {
    if (metadata.recordType == null) return null;
    var queryResults = await queryMapBySQL('SELECT `${CKConstants.RECORD_CHANGE_TAG_FIELD}` FROM `${metadata.recordType}` WHERE `${CKConstants.RECORD_NAME_FIELD}` = ?', args: [metadata.id]);
    if (queryResults.length == 0) return null;
    return queryResults[0][CKConstants.RECORD_CHANGE_TAG_FIELD];
  }

  /// Check if the changeTag for a given metadata is equal to the one in the database.
  Future<bool> isChangeTagEqual(CKRecordMetadata metadata) async
  {
    String? savedChangeTag = await queryChangeTag(metadata);
    return savedChangeTag == metadata.changeTag;
  }

  /// Query the raw sqlite rows in JSON format.
  Future<List<Map<String,dynamic>>> queryMapBySQL(String sql, {List? args, bool copyObjects = true}) async
  {
    var queryResults = await _databaseInstance.rawQuery(sql, args);
    return !copyObjects ? queryResults : queryResults.map((object) => Map.of(object)).toList();
  }

  Future<T> _convertFromSQLiteMap<T>(Map<String,dynamic> rawJSON) async
  {
    var decodedJSON = await _decodeFromSQLite<T>(rawJSON);
    T localObject = CKRecordParser.simpleJSONToLocalObject<T>(decodedJSON, this.cloudDatabase);
    return localObject;
  }

  Stream<List<T>> _createQuery<T extends Object>(String table, [String? where, List? whereArgs])
  {
    return _databaseInstance.createQuery(table, where: where, whereArgs: whereArgs)
        .asyncMapToList<T>(_convertFromSQLiteMap);
  }

  Stream<T> _createSingularQuery<T extends Object>(String table, [String? where, List? whereArgs])
  {
    return _databaseInstance.createQuery(table, where: where, whereArgs: whereArgs)
        .asyncMapToOne<T>(_convertFromSQLiteMap);
  }

  Stream<List<T>> _createQueryBySQL<T extends Object>(List<String> tables, String sql, [List? args])
  {
    return _databaseInstance.createRawQuery(tables, sql, args)
        .asyncMapToList<T>(_convertFromSQLiteMap);
  }

  Stream<T> _createSingularQueryBySQL<T extends Object>(List<String> tables, String sql, [List? args])
  {
    return _databaseInstance.createRawQuery(tables, sql, args)
        .asyncMapToOne<T>(_convertFromSQLiteMap);
  }

  /// Get a stream for changes on an object type.
  Stream<List<T>> streamObjects<T extends Object>([String? where, List? whereArgs])
  {
    var recordStructure = CKRecordParser.getRecordStructureFromLocalType(T);

    return _createQuery<T>(recordStructure.ckRecordType, where, whereArgs);
  }

  /// Get a stream for changes on an object by id.
  Stream<T> streamByID<T extends Object>(String objectID)
  {
    var recordStructure = CKRecordParser.getRecordStructureFromLocalType(T);

    return _createSingularQuery<T>(recordStructure.ckRecordType, "${CKConstants.RECORD_NAME_FIELD} = ?", [objectID]);
  }

  /// Get a stream for changes on an object field.
  Stream<V> streamField<U extends Object, V extends Object>(U parentObject, String referenceFieldName)
  {
    var childRecordStructure = CKRecordParser.getRecordStructureFromLocalType(V);
    var parentRecordStructure = CKRecordParser.getRecordStructureFromLocalType(U);

    var parentObjectID = CKRecordParser.getIDFromLocalObject(parentObject, parentRecordStructure);

    return _createSingularQueryBySQL<V>([childRecordStructure.ckRecordType, parentRecordStructure.ckRecordType],
        "SELECT * FROM `${childRecordStructure.ckRecordType}` WHERE ${CKConstants.RECORD_NAME_FIELD} = (SELECT $referenceFieldName from `${parentRecordStructure.ckRecordType}` WHERE `${CKConstants.RECORD_NAME_FIELD}` = ?)",
        [parentObjectID]);
  }

  /// Get a stream for changes on a list field.
  Stream<List<V>> streamListField<U extends Object, V extends Object>(U parentObject, String referenceListFieldName, {String? where, List? whereArgs, String? orderBy})
  {
    var childRecordStructure = CKRecordParser.getRecordStructureFromLocalType(V);
    var parentRecordStructure = CKRecordParser.getRecordStructureFromLocalType(U);

    var joinTableName = '${parentRecordStructure.ckRecordType}_$referenceListFieldName';
    var parentObjectID = CKRecordParser.getIDFromLocalObject(parentObject, parentRecordStructure);

    return _createQueryBySQL<V>([childRecordStructure.ckRecordType, joinTableName],
        "SELECT * FROM `${childRecordStructure.ckRecordType}` WHERE ${CKConstants.RECORD_NAME_FIELD} IN (SELECT `$referenceListFieldName` from `$joinTableName` WHERE `${parentRecordStructure.ckRecordType}ID` = ?)${where != null ? " AND ($where)" : ""}${orderBy != null ? " ORDER BY $orderBy" : ""}",
        [parentObjectID, ...?whereArgs]);
  }

  /// Insert an object into the database.
  Future<void> insert<T extends Object>(T localObject, {bool shouldUseReplace = false, bool shouldTrackEvent = true, String? recordChangeTag, CKLocalDatabaseBatch? batch}) async
  {
    var recordStructure = CKRecordParser.getRecordStructureFromLocalType(T);

    Map<String,dynamic> simpleJSON = CKRecordParser.localObjectToSimpleJSON<T>(localObject);
    var formattedJSON = await _formatForSQLite<T>(simpleJSON, batch: batch);
    if (recordChangeTag != null) formattedJSON[CKConstants.RECORD_CHANGE_TAG_FIELD] = recordChangeTag;

    var objectID = simpleJSON[CKConstants.RECORD_NAME_FIELD];
    var tableName = recordStructure.ckRecordType;

    if (!shouldUseReplace)
    {

      batch == null ? await _databaseInstance.insert(tableName, formattedJSON) : batch._briteBatch.insert(tableName, formattedJSON);
    }
    else
    {
      var columns = formattedJSON.entries.map((keyValue) => "`${keyValue.key}`").join(",");
      var values = formattedJSON.entries.map((keyValue) => keyValue.value).toList();
      var valuesPlaceholderString = values.map((value) => "?").join(",");
      var replaceSQL = 'REPLACE INTO `$tableName`($columns) VALUES($valuesPlaceholderString)';
      batch == null ? await _databaseInstance.executeAndTrigger([tableName], replaceSQL, values) : batch._briteBatch.executeAndTrigger([tableName], replaceSQL, values);
    }

    var uuidToTypeReplaceSQL = 'REPLACE INTO `$_uuidToTypeTableName` (uuid, type) VALUES(?, ?)';
    batch == null ? await _databaseInstance.execute(uuidToTypeReplaceSQL, [objectID, tableName]) : batch._briteBatch.execute(uuidToTypeReplaceSQL, [objectID, tableName]);

    if (shouldTrackEvent)
    {
      addEvent(CKDatabaseEvent<T>(
        CKRecordChange<T>(objectID, CKRecordOperationType.CREATE, T, localObject: localObject),
        CKDatabaseEventSource.local
      ), batch: batch);
    }
  }

  /// Insert a list of objects into the database.
  Future<void> insertAll<T extends Object>(List<T> localObjects, {bool shouldTrackEvents = true}) async
  {
    for (var localObject in localObjects)
    {
      await insert<T>(localObject, shouldTrackEvent: shouldTrackEvents);
    }
  }

  /// Insert an asset cache into the asset cache table.
  Future<void> insertAssetCache(CKFieldPath fieldPath, String checksum, Uint8List cache) async
  {
    await _databaseInstance.execute('REPLACE INTO `$_assetCacheTableName` (fieldPath, checksum, cache) VALUES(?, ?, ?)', [fieldPath.toString(), checksum, cache]);
  }

  /// Update an object in the database.
  Future<void> update<T extends Object>(T updatedLocalObject, {bool shouldTrackEvent = true, String? recordChangeTag, CKLocalDatabaseBatch? batch}) async
  {
    var recordStructure = CKRecordParser.getRecordStructureFromLocalType(T);

    var updatedLocalObjectJSON = CKRecordParser.localObjectToSimpleJSON<T>(updatedLocalObject);
    var formattedJSON = await _formatForSQLite<T>(updatedLocalObjectJSON, batch: batch);
    if (recordChangeTag != null) formattedJSON[CKConstants.RECORD_CHANGE_TAG_FIELD] = recordChangeTag;

    String recordName = formattedJSON.remove(CKConstants.RECORD_NAME_FIELD);

    batch == null ? await _databaseInstance.update(recordStructure.ckRecordType, formattedJSON, where: "${CKConstants.RECORD_NAME_FIELD} = ?", whereArgs: [recordName]) :
        batch._briteBatch.update(recordStructure.ckRecordType, formattedJSON, where: "${CKConstants.RECORD_NAME_FIELD} = ?", whereArgs: [recordName]);

    if (shouldTrackEvent)
    {
      addEvent(CKDatabaseEvent<T>(
        CKRecordChange<T>(updatedLocalObjectJSON[CKConstants.RECORD_NAME_FIELD], CKRecordOperationType.UPDATE, T, localObject: updatedLocalObject),
        CKDatabaseEventSource.local
      ), batch: batch);
    }
  }

  /// Update the changeTag field for an object in the database.
  Future<void> updateChangeTag(CKRecordMetadata metadata) async
  {
    await _databaseInstance.update(metadata.recordType!, {CKConstants.RECORD_CHANGE_TAG_FIELD: metadata.changeTag}, where: "${CKConstants.RECORD_NAME_FIELD} = ?", whereArgs: [metadata.id]);
  }

  /// Delete an object from the database.
  Future<void> delete<T extends Object>(String localObjectID, {bool shouldTrackEvent = true, CKLocalDatabaseBatch? batch}) async
  {
    CKRecordStructure recordStructure;
    if (T != Object)
    {
      recordStructure = CKRecordParser.getRecordStructureFromLocalType(T);
    }
    else
    {
      var uuidToTypeMap = await _databaseInstance.query(_uuidToTypeTableName, where: "uuid = ?", whereArgs: [localObjectID]);
      if (uuidToTypeMap.length == 0) return;

      var ckRecordType = uuidToTypeMap.first["type"] as String;
      recordStructure = CKRecordParser.getRecordStructureFromRecordType(ckRecordType);
    }

    T? localObject;
    String? recordChangeTag;
    if (shouldTrackEvent)
    {
      localObject = await queryByID(localObjectID, recordStructure: recordStructure);
      recordChangeTag = await queryChangeTag(CKRecordMetadata(localObjectID, recordType: recordStructure.ckRecordType));
    }

    batch == null ? await _databaseInstance.delete(recordStructure.ckRecordType, where: "${CKConstants.RECORD_NAME_FIELD} = ?", whereArgs: [localObjectID]) :
        batch._briteBatch.delete(recordStructure.ckRecordType, where: "${CKConstants.RECORD_NAME_FIELD} = ?", whereArgs: [localObjectID]);
    batch == null ? await _databaseInstance.delete(_uuidToTypeTableName, where: "uuid = ?", whereArgs: [localObjectID]) :
        batch._briteBatch.delete(_uuidToTypeTableName, where: "uuid = ?", whereArgs: [localObjectID]);

    for (var field in recordStructure.fields)
    {
      if (field.type == CKFieldType.ASSET_TYPE)
      {
        var fieldPath = CKFieldPath.fromFieldStructure(localObjectID, field);
        batch == null ? await _databaseInstance.delete(_assetCacheTableName, where: "fieldPath = ?", whereArgs: [fieldPath.toString()]) :
            batch._briteBatch.delete(_assetCacheTableName, where: "fieldPath = ?", whereArgs: [fieldPath.toString()]);
      }
      else if (field.type.sqlite.isList)
      {
        batch == null ? await _databaseInstance.delete('`${recordStructure.ckRecordType}_${field.ckName}`', where: "`${recordStructure.ckRecordType}ID` = ?", whereArgs: [localObjectID]) :
            batch._briteBatch.delete('`${recordStructure.ckRecordType}_${field.ckName}`', where: "`${recordStructure.ckRecordType}ID` = ?", whereArgs: [localObjectID]);
      }
    }

    if (shouldTrackEvent)
    {
      addEvent(CKDatabaseEvent<T>(
        CKRecordChange<T>(localObjectID, CKRecordOperationType.DELETE, T, localObject: localObject, recordChangeTag: recordChangeTag),
        CKDatabaseEventSource.local
      ), batch: batch);
    }
  }

  IBriteBatch _createBriteBatch()
  {
    return _databaseInstance.batch();
  }

  /// Create a new database batch.
  CKLocalDatabaseBatch batch()
  {
    return CKLocalDatabaseBatch(this);
  }

  /// Add a database change event.
  Future<void> addEvent(CKDatabaseEvent event, {CKLocalDatabaseBatch? batch, bool shouldSync = true}) async
  {
    if (batch != null)
    {
      batch._addEvent(event);
      return;
    }

    if (event.recordChange.recordMetadata.changeTag == null)
    {
      event.recordChange.recordMetadata.changeTag = await queryChangeTag(event.recordChange.recordMetadata);
    }
    _databaseEventHistory.add(event);
    if (shouldSync) await synchronizeAllEvents();
  }

  Future<void> addEvents(List<CKDatabaseEvent> events, {bool shouldSync = true}) async
  {
    for (CKDatabaseEvent event in events)
    {
      await addEvent(event, shouldSync: false);
    }
    if (shouldSync) await synchronizeAllEvents();
  }

  /// Sync all database events.
  Future<void> synchronizeAllEvents()
  {
    return _databaseEventHistory.synchronizeAll();
  }
}

class CKLocalDatabaseBatch
{
  final List<CKDatabaseEvent> _events;
  final IBriteBatch _briteBatch;
  final CKLocalDatabaseManager _databaseManager;

  CKLocalDatabaseBatch(this._databaseManager) : _events = [], _briteBatch = _databaseManager._createBriteBatch();

  void _addEvent(CKDatabaseEvent event)
  {
    _events.add(event);
  }

  Future<void> commit() async
  {
    await _briteBatch.commit(noResult: true);

    if (_events.length > 0)
    {
      _databaseManager.addEvents(_events);
      await _databaseManager.synchronizeAllEvents();
    }
  }
}

extension Iterables<E> on Iterable<E>
{
  Map<K, List<E>> groupBy<K>(K Function(E) keyFunction) => fold(
      <K, List<E>>{},
          (Map<K, List<E>> map, E element) =>
      map..putIfAbsent(keyFunction(element), () => <E>[]).add(element));
}

extension AsyncMapToListQueryStreamExtensions on Stream<Query>
{
  Stream<List<T>> asyncMapToList<T>(Future<T> Function(JSON row) rowMapper) {
    final controller = isBroadcast
        ? StreamController<List<T>>.broadcast(sync: false)
        : StreamController<List<T>>(sync: false);
    // Instance cancelled in controller.onCancel, but transfer to temporary variable necessary
    // ignore: cancel_subscriptions
    StreamSubscription<Query>? subscription;

    Future<void> add(List<JSON> rows) async {
      try {
        List<T> items = [];
        for (var row in rows) items.add(await rowMapper(row));
        controller.add(List.unmodifiable(items));
      } catch (e, s) {
        controller.addError(e, s);
      }
    }

    controller.onListen = () {
      subscription = listen(
            (query) {
          Future<List<JSON>> future;

          try {
            future = query();
          } catch (e, s) {
            controller.addError(e, s);
            return;
          }

          subscription!.pause();
          future
              .then(add, onError: controller.addError)
              .whenComplete(subscription!.resume);
        },
        onError: controller.addError,
        onDone: controller.close,
      );

      if (!isBroadcast) {
        controller.onPause = () => subscription!.pause();
        controller.onResume = () => subscription!.resume();
      }
    };
    controller.onCancel = () {
      final toCancel = subscription;
      subscription = null;
      return toCancel?.cancel();
    };

    return controller.stream;
  }
}

extension AsyncMapToOneQueryStreamExtensions on Stream<Query>
{
  Stream<T> asyncMapToOne<T>(final Future<T> Function(JSON row) rowMapper) {
    final controller = isBroadcast
        ? StreamController<T>.broadcast(sync: false)
        : StreamController<T>(sync: false);
    // Instance cancelled in controller.onCancel, but transfer to temporary variable necessary
    // ignore: cancel_subscriptions
    StreamSubscription<Query>? subscription;

    Future<void> add(List<JSON> rows) async {
      final length = rows.length;

      if (length > 1) {
        controller.addError(StateError('Query returned more than 1 row'));
        return;
      }

      if (length == 0) {
        controller.addError(StateError('Query returned 0 row'));
        return;
      }

      final T result;
      try {
        result = await rowMapper(rows[0]);
      } catch (e, s) {
        controller.addError(e, s);
        return;
      }

      controller.add(result);
    }

    controller.onListen = () {
      subscription = listen(
            (query) {
          Future<List<JSON>> future;
          try {
            future = query();
          } catch (e, s) {
            controller.addError(e, s);
            return;
          }

          subscription!.pause();
          future
              .then(add, onError: controller.addError)
              .whenComplete(subscription!.resume);
        },
        onError: controller.addError,
        onDone: controller.close,
      );

      if (!isBroadcast) {
        controller.onPause = () => subscription!.pause();
        controller.onResume = () => subscription!.resume();
      }
    };
    controller.onCancel = () {
      final toCancel = subscription;
      subscription = null;
      return toCancel?.cancel();
    };

    return controller.stream;
  }
}