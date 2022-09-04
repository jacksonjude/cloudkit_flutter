import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:sqlbrite/sqlbrite.dart';

import '/src/parsing/ck_field_structure.dart';
import '/src/parsing/ck_record_parser.dart';
import '/src/parsing/ck_record_structure.dart';
import '/src/parsing/types/ck_field_type.dart';
import '/src/ck_constants.dart';
import '/src/api/request_models/ck_zone.dart';
import '/src/api/request_models/ck_sync_token.dart';
import '/src/api/ck_notification_manager.dart';
import '/src/api/ck_operation.dart';
import '/src/api/ck_api_manager.dart';
import 'ck_database_event.dart';

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

  static Future<void> initializeDatabase(Map<Type,CKRecordStructure> recordStructures, {CKDatabase? database, CKZone? zone, CKLocalDatabaseManager? manager}) async
  {
    WidgetsFlutterBinding.ensureInitialized();

    var managerToInit = manager ?? CKLocalDatabaseManager.shared;

    managerToInit.cloudDatabase = database ?? CKDatabase.PRIVATE_DATABASE;
    managerToInit.cloudZone = zone ?? CKZone();

    deleteDatabase(managerToInit._databaseName); // TODO: REMOVE THIS AFTER TESTING

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

          await db.execute('CREATE TABLE `${recordStructure.ckRecordType}` ($tableColumnDefinitions)');

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

  Future<void> initCloudSync(CKAPNSEnvironment environment, {CKAPIManager? apiManager}) async
  {
    _apiManager = apiManager;

    var notificationStream = await CKNotificationManager.shared.registerForRemoteNotifications(environment, apiManager: _apiManager);
    _notificationStreamSubscription = notificationStream.listen((notification) {
      syncCloudData();
    });

    await syncCloudData();
  }

  Future<void> syncCloudData() async
  {
    var zoneChangesOperation = CKRecordZoneChangesOperation(
      CKDatabase.PRIVATE_DATABASE,
      zoneID: CKZone("CloudCore"),
      syncToken: _syncToken,
      recordTypes: _syncRecordTypes,
      apiManager: _apiManager
    );
    var changesOperationCallback = await zoneChangesOperation.execute();

    var groupedChanges = changesOperationCallback.recordChanges.groupBy((recordChange) => recordChange.recordType);
    groupedChanges.forEach((recordType, recordChanges) {
      if (recordType != dynamic)
      {
        var recordStructure = CKRecordParser.getRecordStructureFromLocalType(recordType);
        var recordTypeAnnotation = recordStructure.recordTypeAnnotation!;

        recordChanges.forEach((recordChange) {
          var objectID = CKRecordParser.getIDFromLocalObject(recordChange.localObject, recordStructure);

          CKDatabaseEventType databaseEventType;
          switch (recordChange.changeType)
          {
            case CKRecordChangeType.update:
              databaseEventType = CKDatabaseEventType.insert;
              break;

            case CKRecordChangeType.delete:
              databaseEventType = CKDatabaseEventType.delete;
              break;
          }

          addEvent(recordTypeAnnotation.createEvent(objectID, databaseEventType, localObject: recordChange.localObject));
        });
      }
      else
      {
        recordChanges.removeWhere((recordChange) => recordChange.changeType != CKRecordChangeType.delete);
        recordChanges.forEach((recordChange) {
          addEvent(CKDatabaseEvent(CKDatabaseEventType.delete, CKDatabaseEventSource.cloud, recordChange.objectID));
        });
      }
    });

    _syncToken = changesOperationCallback.syncToken;

    await synchronizeAllEvents();
  }

  Future<void> stopCloudSync() async
  {
    await _notificationStreamSubscription?.cancel();
  }

  Future<Map<String, dynamic>> _formatForSQLite<T>(Map<String, dynamic> recordJSON, {IBriteBatch? batch}) async
  {
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

        var insertBatch = batch ?? _databaseInstance.batch();
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

  Stream<List<T>> createQuery<T extends Object>([String? where, List? whereArgs])
  {
    var recordStructure = CKRecordParser.getRecordStructureFromLocalType(T);

    return _databaseInstance.createQuery(recordStructure.ckRecordType, where: where, whereArgs: whereArgs)
        .asyncMapToList<T>(_convertFromSQLiteMap);
  }

  Stream<T> createQueryByID<T extends Object>(String recordID)
  {
    var recordStructure = CKRecordParser.getRecordStructureFromLocalType(T);

    return _databaseInstance.createQuery(recordStructure.ckRecordType, where: '${CKConstants.RECORD_NAME_FIELD} = ?', whereArgs: [recordID])
        .asyncMapToOne<T>(_convertFromSQLiteMap);
  }

  Stream<List<T>> createQueryBySQL<T extends Object>(List<String> tables, String sql, [List? args])
  {
    return _databaseInstance.createRawQuery(tables, sql, args)
        .asyncMapToList<T>(_convertFromSQLiteMap);
  }

  Stream<T> createSingularQueryBySQL<T extends Object>(List<String> tables, String sql, [List? args])
  {
    return _databaseInstance.createRawQuery(tables, sql, args)
        .asyncMapToOne<T>(_convertFromSQLiteMap);
  }

  Future<T?> queryByID<T extends Object>(String recordID) async
  {
    var recordStructure = CKRecordParser.getRecordStructureFromLocalType(T);

    var queryResults = await _databaseInstance.query(recordStructure.ckRecordType, where: '${CKConstants.RECORD_NAME_FIELD} = ?', whereArgs: [recordID]);
    if (queryResults.length == 0) return null;

    return _convertFromSQLiteMap<T>(queryResults[0]);
  }

  Future<Uint8List?> queryAssetCache(String checksum) async
  {
    var queryResults = await queryMapBySQL('SELECT * FROM `$_assetCacheTableName` WHERE checksum = ?', args: [checksum]);
    if (queryResults.length == 0) return null;
    return queryResults[0]["cache"];
  }

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

  Stream<T> streamObject<T extends Object>(T object)
  {
    var recordStructure = CKRecordParser.getRecordStructureFromLocalType(T);
    var objectID = CKRecordParser.getIDFromLocalObject(object, recordStructure);

    return createSingularQueryBySQL<T>([recordStructure.ckRecordType],
        "SELECT * FROM `${recordStructure.ckRecordType}` WHERE ${CKConstants.RECORD_NAME_FIELD} = ?",
        [objectID]);
  }

  Stream<V> streamField<U extends Object, V extends Object>(U parentObject, String referenceFieldName)
  {
    var childRecordStructure = CKRecordParser.getRecordStructureFromLocalType(V);
    var parentRecordStructure = CKRecordParser.getRecordStructureFromLocalType(U);

    var parentObjectID = CKRecordParser.getIDFromLocalObject(parentObject, parentRecordStructure);

    return createSingularQueryBySQL<V>([childRecordStructure.ckRecordType, parentRecordStructure.ckRecordType],
        "SELECT * FROM `${childRecordStructure.ckRecordType}` WHERE ${CKConstants.RECORD_NAME_FIELD} = (SELECT $referenceFieldName from `${parentRecordStructure.ckRecordType}` WHERE `${CKConstants.RECORD_NAME_FIELD}` = ?)",
        [parentObjectID]);
  }

  Stream<List<V>> streamListField<U extends Object, V extends Object>(U parentObject, String referenceListFieldName, {String? where, List? whereArgs, String? orderBy})
  {
    var childRecordStructure = CKRecordParser.getRecordStructureFromLocalType(V);
    var parentRecordStructure = CKRecordParser.getRecordStructureFromLocalType(U);

    var joinTableName = '${parentRecordStructure.ckRecordType}_$referenceListFieldName';
    var parentObjectID = CKRecordParser.getIDFromLocalObject(parentObject, parentRecordStructure);

    return createQueryBySQL<V>([childRecordStructure.ckRecordType, joinTableName],
        "SELECT * FROM `${childRecordStructure.ckRecordType}` WHERE ${CKConstants.RECORD_NAME_FIELD} IN (SELECT `$referenceListFieldName` from `$joinTableName` WHERE `${parentRecordStructure.ckRecordType}ID` = ?)${where != null ? " AND ($where)" : ""}${orderBy != null ? " ORDER BY $orderBy" : ""}",
        [parentObjectID, ...?whereArgs]);
  }

  Future<void> insert<T extends Object>(T localObject, {bool shouldUseReplace = false, bool shouldTrackEvent = true, IBriteBatch? batch}) async
  {
    var recordStructure = CKRecordParser.getRecordStructureFromLocalType(T);

    Map<String,dynamic> simpleJSON = CKRecordParser.localObjectToSimpleJSON<T>(localObject);
    var formattedJSON = await _formatForSQLite<T>(simpleJSON, batch: batch);

    var objectID = simpleJSON[CKConstants.RECORD_NAME_FIELD];
    var tableName = recordStructure.ckRecordType;

    if (!shouldUseReplace)
    {
      batch == null ? await _databaseInstance.insert(tableName, formattedJSON) : batch.insert(tableName, formattedJSON);
    }
    else
    {
      var columns = formattedJSON.entries.map((keyValue) => "`${keyValue.key}`").join(",");
      var values = formattedJSON.entries.map((keyValue) => keyValue.value).toList();
      var valuesPlaceholderString = values.map((value) => "?").join(",");
      var replaceSQL = 'REPLACE INTO `$tableName`($columns) VALUES($valuesPlaceholderString)';
      batch == null ? await _databaseInstance.executeAndTrigger([tableName], replaceSQL, values) : batch.executeAndTrigger([tableName], replaceSQL, values);
    }

    var uuidToTypeReplaceSQL = 'REPLACE INTO `$_uuidToTypeTableName` (uuid, type) VALUES(?, ?)';
    batch == null ? await _databaseInstance.execute(uuidToTypeReplaceSQL, [objectID, tableName]) : batch.execute(uuidToTypeReplaceSQL, [objectID, tableName]);

    if (shouldTrackEvent)
    {
      addEvent(CKDatabaseEvent<T>(
        CKDatabaseEventType.insert,
        CKDatabaseEventSource.local,
        objectID,
        localObject
      ));
    }
  }

  Future<void> insertAll<T extends Object>(List<T> localObjects, {bool shouldTrackEvents = true}) async
  {
    for (var localObject in localObjects)
    {
      await insert<T>(localObject, shouldTrackEvent: shouldTrackEvents);
    }
  }

  Future<void> insertAssetCache(CKFieldPath fieldPath, String checksum, Uint8List cache) async
  {
    await _databaseInstance.execute('REPLACE INTO `$_assetCacheTableName` (fieldPath, checksum, cache) VALUES(?, ?, ?)', [fieldPath.toString(), checksum, cache]);
  }

  Future<void> update<T extends Object>(T updatedLocalObject, {bool shouldTrackEvent = true, IBriteBatch? batch}) async
  {
    var recordStructure = CKRecordParser.getRecordStructureFromLocalType(T);

    var updatedLocalObjectJSON = CKRecordParser.localObjectToSimpleJSON<T>(updatedLocalObject);
    var formattedJSON = await _formatForSQLite(updatedLocalObjectJSON, batch: batch);

    batch == null ? await _databaseInstance.update(recordStructure.ckRecordType, formattedJSON) : batch.update(recordStructure.ckRecordType, formattedJSON);

    if (shouldTrackEvent)
    {
      addEvent(CKDatabaseEvent<T>(
        CKDatabaseEventType.update,
        CKDatabaseEventSource.local,
        updatedLocalObjectJSON[CKConstants.RECORD_NAME_FIELD],
        updatedLocalObject
      ));
    }
  }

  Future<void> delete<T extends Object>(String localObjectID, {T? localObject, bool shouldTrackEvent = true, IBriteBatch? batch}) async
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

    batch == null ? await _databaseInstance.delete(recordStructure.ckRecordType, where: "${CKConstants.RECORD_NAME_FIELD} = ?", whereArgs: [localObjectID]) :
        batch.delete(recordStructure.ckRecordType, where: "${CKConstants.RECORD_NAME_FIELD} = ?", whereArgs: [localObjectID]);
    batch == null ? await _databaseInstance.delete(_uuidToTypeTableName, where: "uuid = ?", whereArgs: [localObjectID]) :
        batch.delete(_uuidToTypeTableName, where: "uuid = ?", whereArgs: [localObjectID]);

    for (var field in recordStructure.fields)
    {
      if (field.type == CKFieldType.ASSET_TYPE)
      {
        var fieldPath = CKFieldPath.fromFieldStructure(localObjectID, field);
        batch == null ? await _databaseInstance.delete(_assetCacheTableName, where: "fieldPath = ?", whereArgs: [fieldPath.toString()]) :
            batch.delete(_assetCacheTableName, where: "fieldPath = ?", whereArgs: [fieldPath.toString()]);
      }
      else if (field.type.sqlite.isList)
      {
        batch == null ? await _databaseInstance.delete('`${recordStructure.ckRecordType}_${field.ckName}`', where: "`${recordStructure.ckRecordType}ID` = ?", whereArgs: [localObjectID]) :
            batch.delete('`${recordStructure.ckRecordType}_${field.ckName}`', where: "`${recordStructure.ckRecordType}ID` = ?", whereArgs: [localObjectID]);
      }
    }

    if (shouldTrackEvent)
    {
      addEvent(CKDatabaseEvent<T>(
        CKDatabaseEventType.delete,
        CKDatabaseEventSource.local,
        localObjectID,
        localObject
      ));
    }
  }

  IBriteBatch batch()
  {
    return _databaseInstance.batch();
  }

  void addEvent(CKDatabaseEvent event)
  {
    _databaseEventHistory.add(event);
  }

  Future<void> synchronizeAllEvents()
  {
    return _databaseEventHistory.synchronizeAll();
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