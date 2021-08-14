import 'dart:collection';

import 'package:flutter/material.dart';

import 'package:idb_shim/idb_browser.dart';
import 'package:idb_sqflite/idb_sqflite.dart';
import 'package:sqflite/sqflite.dart' show databaseFactory;
import 'package:flutter/foundation.dart' show kIsWeb;

import '../parsing/ck_record_parser.dart';
import '../parsing/ck_record_structure.dart';
import '../ck_constants.dart';

class CKLocalDatabaseManager
{
  static const _defaultDatabaseName = "cloudkit_flutter_sync.db";
  static const _defaultVersionNumber = 1;

  static const _readwriteTransaction = "readwrite";
  static const _readTransaction = "read";

  late final _databaseName;
  late final _databaseVersion;
  late final Database _databaseInstance;

  CKLocalDatabaseManager(this._databaseName, this._databaseVersion) : _databaseEventHistory = CKDatabaseEventList();

  static CKLocalDatabaseManager? _instance;

  /// Get the shared instance of the [CKLocalDatabaseManager].
  static CKLocalDatabaseManager shared()
  {
    if (_instance == null) _instance = CKLocalDatabaseManager(_defaultDatabaseName, _defaultVersionNumber);
    return _instance!;
  }

  CKDatabaseEventList _databaseEventHistory;

  static void initializeDatabase(Map<Type,CKRecordStructure> recordStructures, {CKLocalDatabaseManager? manager}) async
  {
    WidgetsFlutterBinding.ensureInitialized();

    var managerToInit = manager ?? CKLocalDatabaseManager.shared();

    IdbFactory factory;

    if (kIsWeb)
    {
      var browserFactory = getIdbFactory();
      if (browserFactory == null) throw DatabaseError("Cannot create factory");
      factory = browserFactory;
    }
    else
    {
      factory = getIdbFactorySqflite(databaseFactory);
    }

    managerToInit._databaseInstance = await factory.open(
      managerToInit._databaseName,
      version: managerToInit._databaseVersion,
      onUpgradeNeeded: (event) {
        var db = event.database;
        recordStructures.forEach((type, recordStructure) {
          var recordIDField = recordStructure.fields.firstWhere((field) => field.ckName == CKConstants.RECORD_NAME_FIELD);
          db.createObjectStore(type.toString(), keyPath: recordIDField.ckName);
        });
      }
    );
  }

  Future<String> insertLocalObject<T extends Object>(T localObject, {bool? shouldTrackEvent}) async
  {
    Map<String,dynamic> simpleJSON = CKRecordParser.localObjectToSimpleJSON<T>(localObject);
    var key = await insertJSONObject(simpleJSON);

    shouldTrackEvent ??= true;
    if (shouldTrackEvent)
    {
      _databaseEventHistory.add(CKDatabaseEvent<T>(
        this,
        CKDatabaseEventType.insert,
        key,
        localObject
      ));
    }

    return key;
  }

  Future<String> insertJSONObject<T extends Object>(Map<String,dynamic> jsonObject) async
  {
    var transaction = _databaseInstance.transaction(T.toString(), _readwriteTransaction);
    var store = transaction.objectStore(T.toString());
    var key = await store.put(jsonObject) as String;
    await transaction.completed;

    return key;
  }

  Future<T?> queryLocalObject<T extends Object>(String recordID) async
  {
    var simpleJSON = await queryJSONObject(recordID);
    if (simpleJSON == null) return null;

    T localObject = CKRecordParser.simpleJSONToLocalObject(simpleJSON);
    return localObject;
  }

  Future<Map<String,dynamic>?> queryJSONObject<T extends Object>(String recordID) async
  {
    var transaction = _databaseInstance.transaction(T.toString(), _readTransaction);
    var store = transaction.objectStore(T.toString());
    var jsonObjectData = await store.getObject(recordID);
    await transaction.completed;

    return jsonObjectData as Map<String,dynamic>?;
  }

  Future<void> updateLocalObject<T extends Object>(T updatedLocalObject, {bool? shouldTrackEvent}) async
  {
    var recordStructure = CKRecordParser.getRecordStructureFromLocalType(T);
    var updatedLocalObjectJSON = CKRecordParser.localObjectToSimpleJSON<T>(updatedLocalObject);

    var recordIDField = recordStructure.fields.firstWhere((field) => field.ckName == CKConstants.RECORD_NAME_FIELD);
    String localObjectID = updatedLocalObjectJSON[recordIDField.ckName];

    var currentLocalObjectJSON = await queryJSONObject<T>(localObjectID) ?? updatedLocalObjectJSON;
    currentLocalObjectJSON.addAll(updatedLocalObjectJSON);

    await insertJSONObject<T>(currentLocalObjectJSON);

    shouldTrackEvent ??= true;
    if (shouldTrackEvent)
    {
      var currentLocalObject = CKRecordParser.simpleJSONToLocalObject<T>(currentLocalObjectJSON);

      _databaseEventHistory.add(CKDatabaseEvent<T>(
        this,
        CKDatabaseEventType.update,
        localObjectID,
        currentLocalObject
      ));
    }
  }

  Future<void> deleteLocalObject<T extends Object>(String localObjectID, {bool? shouldTrackEvent}) async
  {
    var transaction = _databaseInstance.transaction(T.toString(), _readwriteTransaction);
    var store = transaction.objectStore(T.toString());
    await store.delete(localObjectID);
    await transaction.completed;

    shouldTrackEvent ??= true;
    if (shouldTrackEvent)
    {
      _databaseEventHistory.add(CKDatabaseEvent<T>(
        this,
        CKDatabaseEventType.delete,
        localObjectID
      ));
    }
  }
}

class CKDatabaseEvent<T extends Object>
{
  final CKDatabaseEventType _eventType;
  final String _objectID;
  T? localObject;

  final CKLocalDatabaseManager _databaseManager;

  CKDatabaseEvent(this._databaseManager, this._eventType, this._objectID, [this.localObject]);

  void performOnCloudDatabase()
  {
    // TODO: Perform on cloud
  }

  void performOnLocalDatabase() async
  {
    switch (_eventType)
    {
      case CKDatabaseEventType.insert:
        if (localObject == null) return;
        await _databaseManager.insertLocalObject<T>(localObject!, shouldTrackEvent: false);
        break;

      case CKDatabaseEventType.update:
        if (localObject == null) return;
        await _databaseManager.updateLocalObject<T>(localObject!, shouldTrackEvent: false);
        break;

      case CKDatabaseEventType.delete:
        await _databaseManager.deleteLocalObject<T>(_objectID, shouldTrackEvent: false);
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

class CKDatabaseEventList extends ListBase<CKDatabaseEvent>
{
  final List<CKDatabaseEvent> l;
  CKDatabaseEventList() : l = [];

  set length(int newLength) { l.length = newLength; }
  int get length => l.length;
  CKDatabaseEvent operator [](int index) => l[index];
  void operator []=(int index, CKDatabaseEvent value) { l[index] = value; }

  @override
  void add(CKDatabaseEvent<Object> element)
  {
    super.add(element);
    _cleanEvents();
  }

  void _cleanEvents()
  {
    this.l.forEach((event) {
      switch (event._eventType)
      {
        case CKDatabaseEventType.insert:
          var deleteEvents = this.l.where((testEvent) => testEvent._objectID == event._objectID && testEvent._eventType == CKDatabaseEventType.delete);
          if (deleteEvents.isNotEmpty)
          {
            this.l.remove(event);
            this.l.remove(deleteEvents.first);

            this.l.removeWhere((testEvent) => testEvent._objectID == testEvent._objectID);
            return;
          }

          var updateEvents = this.l.where((testEvent) => testEvent._objectID == event._objectID && testEvent._eventType == CKDatabaseEventType.update);
          if (updateEvents.isNotEmpty)
          {
            event = CKDatabaseEvent(event._databaseManager, event._eventType, event._objectID, updateEvents.last.localObject);
            updateEvents.forEach((updateEvent) {
              this.l.remove(updateEvent);
            });
          }
          break;

        case CKDatabaseEventType.update:
          var updateEvents = this.l.where((testEvent) => testEvent != event && testEvent._objectID == event._objectID && testEvent._eventType == CKDatabaseEventType.update);
          if (updateEvents.isNotEmpty)
          {
            event.localObject = updateEvents.last.localObject;
            updateEvents.forEach((updateEvent) {
              this.l.remove(updateEvent);
            });
          }
          break;

        case CKDatabaseEventType.delete:
          break;
      }
    });
  }
}