import 'package:sqlbrite/sqlbrite.dart';

import '/src/parsing/ck_record_parser.dart';
import '/src/api/ck_operation.dart';
import '/src/api/request_models/ck_record_change.dart';
import 'ck_local_database_manager.dart';

/// A database change event.
class CKDatabaseEvent<T extends Object>
{
  final CKRecordChange _recordChange;
  final CKDatabaseEventSource _source;

  String get _objectID => _recordChange.recordMetadata.id;

  CKDatabaseEvent(this._recordChange, this._source);

  /// Sync the database change event to the cloud or local database.
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

  /// Perform the change on the cloud database.
  Future<void> performOnCloudDatabase(CKLocalDatabaseManager databaseManager) async
  {
    if (_recordChange.localObject == null) return;

    var recordJSON = CKRecordParser.localObjectToRecord<T>(_recordChange.localObject!);
    var modifyOperation = CKRecordModifyOperation(databaseManager.cloudDatabase, zoneID: databaseManager.cloudZone, recordChanges: [CKRecordChange(_recordChange.recordMetadata.id, _recordChange.operationType, T, recordJSON: recordJSON)]);
    var modifyCallback = await modifyOperation.execute();
    if (modifyCallback.response == null) return;

    for (var recordMetadata in modifyCallback.response!)
    {
      if (recordMetadata.recordType == null) continue;
      await databaseManager.updateChangeTag(recordMetadata);
    }
  }

  /// Perform the change on the local database.
  Future<void> performOnLocalDatabase(CKLocalDatabaseManager databaseManager, [IBriteBatch? batch]) async
  {
    if (await databaseManager.isChangeTagEqual(_recordChange.recordMetadata)) return;

    switch (_recordChange.operationType)
    {
      case CKRecordOperationType.CREATE:
      case CKRecordOperationType.UPDATE:
      case CKRecordOperationType.REPLACE:
      case CKRecordOperationType.FORCE_UPDATE:
      case CKRecordOperationType.FORCE_REPLACE:
        if (_recordChange.localObject == null) return;
        await databaseManager.insert<T>(_recordChange.localObject!, recordChangeTag: _recordChange.recordMetadata.changeTag, shouldUseReplace: true, shouldTrackEvent: false, batch: batch);
        break;

      case CKRecordOperationType.DELETE:
      case CKRecordOperationType.FORCE_DELETE:
        await databaseManager.delete<T>(_recordChange.recordMetadata.id, shouldTrackEvent: false, batch: batch);
        break;
    }
  }
}

/// The source of a database event.
enum CKDatabaseEventSource
{
  cloud,
  local
}

/// A list of database events.
class CKDatabaseEventList
{
  final List<CKDatabaseEvent> _l;
  final CKLocalDatabaseManager _databaseManager;
  CKDatabaseEventList(this._databaseManager) : _l = [];

  bool isSyncing = false;

  /// Add a database event.
  void add(CKDatabaseEvent element)
  {
    _l.add(element);
    if (!isSyncing) _cleanEvents();
  }

  /// Sync all database events.
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
      switch (event._recordChange.operationType)
      {
        case CKRecordOperationType.CREATE:
          var deleteEvents = this._l.where((testEvent) => testEvent._objectID == event._objectID && testEvent._recordChange.operationType == CKRecordOperationType.DELETE);
          if (deleteEvents.isNotEmpty)
          {
            this._l.remove(event);
            this._l.remove(deleteEvents.first);

            this._l.removeWhere((testEvent) => testEvent._objectID == event._objectID);
            return;
          }

          var updateEvents = this._l.where((testEvent) => testEvent._objectID == event._objectID && testEvent._recordChange.operationType == CKRecordOperationType.UPDATE);
          if (updateEvents.isNotEmpty)
          {
            event._recordChange.localObject = updateEvents.last._recordChange.localObject;
            updateEvents.forEach((updateEvent) {
              this._l.remove(updateEvent);
            });
          }
          break;

        case CKRecordOperationType.UPDATE:
        case CKRecordOperationType.REPLACE:
        case CKRecordOperationType.FORCE_UPDATE:
        case CKRecordOperationType.FORCE_REPLACE:
          var updateEvents = this._l.where((testEvent) => testEvent != event && testEvent._objectID == event._objectID && testEvent._recordChange.operationType == CKRecordOperationType.UPDATE);
          if (updateEvents.isNotEmpty)
          {
            event._recordChange.localObject = updateEvents.last._recordChange.localObject;
            updateEvents.forEach((updateEvent) {
              this._l.remove(updateEvent);
            });
          }
          break;

        case CKRecordOperationType.DELETE:
          break;
      }
    });
  }
}
