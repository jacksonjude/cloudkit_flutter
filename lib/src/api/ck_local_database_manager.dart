import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:collection/collection.dart';
import 'package:tuple/tuple.dart';

import '../parsing/ck_record_parser.dart';
import '../parsing/ck_record_structure.dart';
import '../parsing/types/ck_field_type.dart';
import '../ck_constants.dart';
import 'request_models/ck_zone.dart';
import 'ck_operation.dart';
import 'request_models/ck_record_modify_request.dart';

class CKLocalDatabaseManager
{
  static const _defaultDatabaseName = "cloudkit_flutter_sync.db";
  static const _defaultVersionNumber = 1;

  final _databaseName;
  final _databaseVersion;
  late final CKDatabase _cloudDatabase;
  late final CKZone _cloudZone;
  late final Database _databaseInstance;

  CKLocalDatabaseManager(this._databaseName, this._databaseVersion) : databaseEventHistory = CKDatabaseEventList();

  static CKLocalDatabaseManager? _instance;

  /// Get the shared instance of the [CKLocalDatabaseManager].
  static CKLocalDatabaseManager get shared
  {
    if (_instance == null) _instance = CKLocalDatabaseManager(_defaultDatabaseName, _defaultVersionNumber);
    return _instance!;
  }

  CKDatabaseEventList databaseEventHistory;

  static Future<void> initializeDatabase(Map<Type,CKRecordStructure> recordStructures, {CKDatabase? database, CKZone? zone, CKLocalDatabaseManager? manager}) async
  {
    WidgetsFlutterBinding.ensureInitialized();

    var managerToInit = manager ?? CKLocalDatabaseManager.shared;

    managerToInit._cloudDatabase = database ?? CKDatabase.PRIVATE_DATABASE;
    managerToInit._cloudZone = zone ?? CKZone();

    deleteDatabase(managerToInit._databaseName); // TODO: REMOVE THIS AFTER TESTING

    managerToInit._databaseInstance = await openDatabase(
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
      }
    );
  }

  Future<Map<String, dynamic>> _formatForSQLite<T>(Map<String, dynamic> recordJSON) async
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
        var existingObjects = (await _databaseInstance.query('`${recordStructure.ckRecordType}_${field.ckName}`', where: '`${recordStructure.ckRecordType}ID` = ?', whereArgs: [recordJSON[CKConstants.RECORD_NAME_FIELD]]))
            .map((keyPair) => keyPair[field.ckName]).toList();

        objectsToInsert.removeWhere((element) {
          var existingIndex = existingObjects.indexOf(element);
          if (existingIndex == -1) return false;

          existingObjects.removeAt(existingIndex);
          return true;
        });

        var insertBatch = _databaseInstance.batch();
        objectsToInsert.forEach((element) {
          insertBatch.insert('`${recordStructure.ckRecordType}_${field.ckName}`', {'`${recordStructure.ckRecordType}ID`': recordJSON[CKConstants.RECORD_NAME_FIELD], field.ckName: element});
        });
        await insertBatch.commit();

        recordJSON.remove(field.ckName);
      }
    }

    return recordJSON;
  }

  Future<Map<String, dynamic>> _decodeFromSQLite<T>(Map<String, dynamic> rawJSON) async
  {
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
              "database": _cloudDatabase,
              "zone": _cloudZone
            };
            break;

          case CKFieldType.LIST_REFERENCE_TYPE:
            rawJSON[field.ckName] = (rawJSON[field.ckName] as List).map((referenceID) => {
              CKConstants.RECORD_NAME_FIELD: referenceID,
              "database": _cloudDatabase,
              "zone": _cloudZone
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

  Future<void> insert<T extends Object>(T localObject, {bool shouldUseReplace = false, bool? shouldTrackEvent}) async
  {
    var recordStructure = CKRecordParser.getRecordStructureFromLocalType(T);

    Map<String,dynamic> simpleJSON = CKRecordParser.localObjectToSimpleJSON<T>(localObject);
    var formattedJSON = await _formatForSQLite<T>(simpleJSON);

    if (!shouldUseReplace)
    {
      await _databaseInstance.insert(recordStructure.ckRecordType, formattedJSON);
    }
    else
    {
      var columns = formattedJSON.entries.map((keyValue) => "`${keyValue.key}`").join(",");
      var values = formattedJSON.entries.map((keyValue) => keyValue.value).toList();
      var valuesPlaceholderString = values.map((value) => "?").join(",");
      await _databaseInstance.execute('REPLACE INTO `${recordStructure.ckRecordType}`($columns) VALUES($valuesPlaceholderString)', values);
    }

    shouldTrackEvent ??= true;
    if (shouldTrackEvent)
    {
      databaseEventHistory.add(CKDatabaseEvent<T>(
        this,
        CKDatabaseEventType.insert,
        CKDatabaseEventSource.local,
        simpleJSON[CKConstants.RECORD_NAME_FIELD],
        localObject
      ));
    }
  }

  Future<void> insertAll<T extends Object>(List<T> localObjects, {bool? shouldTrackEvents}) async
  {
    for (var localObject in localObjects)
    {
      await insert<T>(localObject, shouldTrackEvent: shouldTrackEvents);
    }
  }

  Future<List<T>> query<T extends Object>([String? where, List? whereArgs]) async
  {
    var recordStructure = CKRecordParser.getRecordStructureFromLocalType(T);

    var queryResults = await queryBySQL<T>('SELECT * FROM `${recordStructure.ckRecordType}` ${where != null ? "WHERE $where" : ""}', args: whereArgs);
    return queryResults;
  }

  Future<T?> queryByID<T extends Object>(String recordID) async
  {
    var recordStructure = CKRecordParser.getRecordStructureFromLocalType(T);

    var queryResults = await queryBySQL<T>('SELECT * FROM `${recordStructure.ckRecordType}` WHERE ${CKConstants.RECORD_NAME_FIELD} = ?', args: [recordID]);
    return queryResults.firstOrNull;
  }

  Future<List<T>> queryBySQL<T extends Object>(String sql, {List? args}) async
  {
    var queryResults = await queryMapBySQL(sql, args: args);

    List<T> localObjects = [];
    for (var rawJSON in queryResults)
    {
      var decodedJSON = await _decodeFromSQLite<T>(rawJSON);
      T localObject = CKRecordParser.simpleJSONToLocalObject<T>(decodedJSON, this._cloudDatabase);
      localObjects.add(localObject);
    }

    return localObjects;
  }

  Future<List<Map<String,dynamic>>> queryMapBySQL(String sql, {List? args, bool copyObjects = true}) async
  {
    var queryResults = await _databaseInstance.rawQuery(sql, args);
    return !copyObjects ? queryResults : queryResults.map((object) => Map.of(object)).toList();
  }

  Future<void> update<T extends Object>(T updatedLocalObject, {bool? shouldTrackEvent}) async
  {
    var recordStructure = CKRecordParser.getRecordStructureFromLocalType(T);

    var updatedLocalObjectJSON = CKRecordParser.localObjectToSimpleJSON<T>(updatedLocalObject);
    var formattedJSON = await _formatForSQLite(updatedLocalObjectJSON);

    await _databaseInstance.update(recordStructure.ckRecordType, formattedJSON);

    shouldTrackEvent ??= true;
    if (shouldTrackEvent)
    {
      databaseEventHistory.add(CKDatabaseEvent<T>(
        this,
        CKDatabaseEventType.update,
        CKDatabaseEventSource.local,
        updatedLocalObjectJSON[CKConstants.RECORD_NAME_FIELD],
        updatedLocalObject
      ));
    }
  }

  Future<void> delete<T extends Object>(String localObjectID, {T? localObject, bool? shouldTrackEvent}) async
  {
    var recordStructure = CKRecordParser.getRecordStructureFromLocalType(T);

    await _databaseInstance.delete(recordStructure.ckRecordType, where: "${CKConstants.RECORD_NAME_FIELD} = ?", whereArgs: [localObjectID]);

    for (var field in recordStructure.fields)
    {
      if (!field.type.sqlite.isList) continue;
      await _databaseInstance.delete('`${recordStructure.ckRecordType}_${field.ckName}`', where: "`${recordStructure.ckRecordType}ID` = ?", whereArgs: [localObjectID]);
    }

    shouldTrackEvent ??= true;
    if (shouldTrackEvent)
    {
      databaseEventHistory.add(CKDatabaseEvent<T>(
        this,
        CKDatabaseEventType.delete,
        CKDatabaseEventSource.local,
        localObjectID,
        localObject
      ));
    }
  }
}

class CKDatabaseEvent<T extends Object>
{
  final CKDatabaseEventType _eventType;
  final CKDatabaseEventSource _source;
  final String _objectID;
  T? localObject;

  final CKLocalDatabaseManager _databaseManager;

  CKDatabaseEvent(this._databaseManager, this._eventType, this._source, this._objectID, [this.localObject]);

  Future<void> synchronize() async
  {
    switch (_source)
    {
      case CKDatabaseEventSource.local:
        await performOnCloudDatabase();
        break;

      case CKDatabaseEventSource.cloud:
        await performOnLocalDatabase();
        break;
    }
  }

  Future<void> performOnCloudDatabase() async
  {
    if (localObject == null) return;

    CKRecordOperationType operationType;
    switch (_eventType)
    {
      case CKDatabaseEventType.insert:
        operationType = CKRecordOperationType.CREATE;
        break;

      case CKDatabaseEventType.update:
        operationType = CKRecordOperationType.UPDATE;
        break;

      case CKDatabaseEventType.delete:
        operationType = CKRecordOperationType.DELETE;
        break;
    }

    var modifyOperation = CKRecordModifyOperation<T>(_databaseManager._cloudDatabase, objectsToModify: [Tuple2<T,CKRecordOperationType>(localObject!, operationType)]);
    var responseCallback = await modifyOperation.execute();
    print(responseCallback);
  }

  Future<void> performOnLocalDatabase() async
  {
    switch (_eventType)
    {
      case CKDatabaseEventType.insert:
        if (localObject == null) return;
        await _databaseManager.insert<T>(localObject!, shouldUseReplace: true, shouldTrackEvent: false);
        break;

      case CKDatabaseEventType.update:
        if (localObject == null) return;
        await _databaseManager.update<T>(localObject!, shouldTrackEvent: false);
        break;

      case CKDatabaseEventType.delete:
        await _databaseManager.delete<T>(_objectID, shouldTrackEvent: false);
        break;
    }
  }
}

enum CKDatabaseEventType
{
  insert,
  update,
  delete
}

enum CKDatabaseEventSource
{
  cloud,
  local
}

class CKDatabaseEventList
{
  final List<CKDatabaseEvent> _l;
  CKDatabaseEventList() : _l = [];

  void add(CKDatabaseEvent element)
  {
    _l.add(element);
    _cleanEvents();
  }

  Future<void> synchronizeAll() async
  {
    for (var i=0; i < _l.length; i++)
    {
      await _l[i].synchronize();
      _l.removeAt(i);
      i--;
    }
  }

  void _cleanEvents() // TODO: Account for local vs cloud changes
  {
    this._l.forEach((event) {
      switch (event._eventType)
      {
        case CKDatabaseEventType.insert:
          var deleteEvents = this._l.where((testEvent) => testEvent._objectID == event._objectID && testEvent._eventType == CKDatabaseEventType.delete);
          if (deleteEvents.isNotEmpty)
          {
            this._l.remove(event);
            this._l.remove(deleteEvents.first);

            this._l.removeWhere((testEvent) => testEvent._objectID == testEvent._objectID);
            return;
          }

          var updateEvents = this._l.where((testEvent) => testEvent._objectID == event._objectID && testEvent._eventType == CKDatabaseEventType.update);
          if (updateEvents.isNotEmpty)
          {
            event.localObject = updateEvents.last.localObject;
            updateEvents.forEach((updateEvent) {
              this._l.remove(updateEvent);
            });
          }
          break;

        case CKDatabaseEventType.update:
          var updateEvents = this._l.where((testEvent) => testEvent != event && testEvent._objectID == event._objectID && testEvent._eventType == CKDatabaseEventType.update);
          if (updateEvents.isNotEmpty)
          {
            event.localObject = updateEvents.last.localObject;
            updateEvents.forEach((updateEvent) {
              this._l.remove(updateEvent);
            });
          }
          break;

        case CKDatabaseEventType.delete:
          break;
      }
    });
  }
}