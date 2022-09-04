import 'package:sqlbrite/sqlbrite.dart';
import 'package:tuple/tuple.dart';

import '/src/api/request_models/ck_record_modify_request.dart';
import '/src/api/ck_operation.dart';
import 'ck_local_database_manager.dart';

class CKDatabaseEvent<T extends Object>
{
  final CKDatabaseEventType _eventType;
  final CKDatabaseEventSource _source;
  final String _objectID;
  T? localObject;

  CKDatabaseEvent(this._eventType, this._source, this._objectID, [this.localObject]);

  Future<void> synchronize(CKLocalDatabaseManager databaseManager, [IBriteBatch? batch]) async
  {
    switch (_source)
    {
      case CKDatabaseEventSource.local:
        await performOnCloudDatabase(databaseManager);
        break;

      case CKDatabaseEventSource.cloud:
        await performOnLocalDatabase(databaseManager, batch);
        break;
    }
  }

  Future<void> performOnCloudDatabase(CKLocalDatabaseManager databaseManager) async
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

    var modifyOperation = CKRecordModifyOperation<T>(databaseManager.cloudDatabase, zoneID: databaseManager.cloudZone, objectsToModify: [Tuple2<T,CKRecordOperationType>(localObject!, operationType)]);
    var responseCallback = await modifyOperation.execute();
    print(responseCallback);
  }

  Future<void> performOnLocalDatabase(CKLocalDatabaseManager databaseManager, [IBriteBatch? batch]) async
  {
    switch (_eventType)
    {
      case CKDatabaseEventType.insert:
        if (localObject == null) return;
        await databaseManager.insert<T>(localObject!, shouldUseReplace: true, shouldTrackEvent: false, batch: batch);
        break;

      case CKDatabaseEventType.update:
        if (localObject == null) return;
        await databaseManager.update<T>(localObject!, shouldTrackEvent: false, batch: batch);
        break;

      case CKDatabaseEventType.delete:
        await databaseManager.delete<T>(_objectID, shouldTrackEvent: false, batch: batch);
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
  final CKLocalDatabaseManager _databaseManager;
  CKDatabaseEventList(this._databaseManager) : _l = [];

  bool isSyncing = false;

  void add(CKDatabaseEvent element)
  {
    _l.add(element);
    _cleanEvents();
  }

  Future<void> synchronizeAll() async
  {
    if (isSyncing) return;
    isSyncing = true;

    var syncBatch = _databaseManager.batch();

    for (var i=0; i < _l.length; i++)
    {
      await _l[i].synchronize(_databaseManager, syncBatch);
      _l.removeAt(i);
      i--;
    }

    await syncBatch.commit(noResult: true);

    isSyncing = false;
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
