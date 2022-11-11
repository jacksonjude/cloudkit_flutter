import '/src/parsing/ck_record_parser.dart';
import '/src/api/ck_operation.dart';
import '/src/api/request_models/ck_record_change.dart';
import 'ck_local_database_manager.dart';

/// A database change event.
class CKDatabaseEvent<T extends Object>
{
  final CKRecordChange recordChange;
  final CKDatabaseEventSource source;

  String get _objectID => recordChange.recordMetadata.id;

  CKDatabaseEvent(this.recordChange, this.source);

  /// Sync the database change event to the cloud or local database.
  Future<void> synchronize(CKLocalDatabaseManager databaseManager, [CKLocalDatabaseBatch? batch, List<CKRecordChange>? cloudRecordChanges]) async
  {
    switch (source)
    {
      case CKDatabaseEventSource.local:
        await performOnCloudDatabase(databaseManager, cloudRecordChanges);
        break;

      case CKDatabaseEventSource.cloud:
        await performOnLocalDatabase(databaseManager, batch);
        break;
    }
  }

  /// Perform the change on the cloud database.
  Future<void> performOnCloudDatabase(CKLocalDatabaseManager databaseManager, List<CKRecordChange>? cloudRecordChanges) async
  {
    if (recordChange.localObject == null) return;

    var recordJSON = CKRecordParser.localObjectToRecord<T>(recordChange.localObject!);
    var currentRecordChange = CKRecordChange(recordChange.recordMetadata.id, recordChange.operationType, T, recordJSON: recordJSON, recordChangeTag: recordChange.recordMetadata.changeTag);

    if (cloudRecordChanges != null)
    {
      cloudRecordChanges.add(currentRecordChange);
      return;
    }

    var modifyOperation = CKRecordModifyOperation(databaseManager.cloudDatabase, zoneID: databaseManager.cloudZone, recordChanges: [
      currentRecordChange
    ]);
    var modifyCallback = await modifyOperation.execute();
    if (modifyCallback.response == null) return;

    for (var recordMetadata in modifyCallback.response!)
    {
      if (recordMetadata.recordType == null) continue;
      await databaseManager.updateChangeTag(recordMetadata);
    }
  }

  /// Perform the change on the local database.
  Future<void> performOnLocalDatabase(CKLocalDatabaseManager databaseManager, [CKLocalDatabaseBatch? batch]) async
  {
    if (recordChange.operationType != CKRecordOperationType.DELETE && recordChange.operationType != CKRecordOperationType.FORCE_DELETE)
    {
      var changeTagIsEqual = await databaseManager.isChangeTagEqual(recordChange.recordMetadata);
      if (changeTagIsEqual) return;
    }

    switch (recordChange.operationType)
    {
      case CKRecordOperationType.CREATE:
      case CKRecordOperationType.UPDATE:
      case CKRecordOperationType.REPLACE:
      case CKRecordOperationType.FORCE_UPDATE:
      case CKRecordOperationType.FORCE_REPLACE:
        if (recordChange.localObject == null) return;
        await databaseManager.insert<T>(recordChange.localObject!, recordChangeTag: recordChange.recordMetadata.changeTag, shouldUseReplace: true, shouldTrackEvent: false, batch: batch);
        break;

      case CKRecordOperationType.DELETE:
      case CKRecordOperationType.FORCE_DELETE:
        await databaseManager.delete<T>(recordChange.recordMetadata.id, shouldTrackEvent: false, batch: batch);
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

  void addAll(List<CKDatabaseEvent> elements)
  {
    _l.addAll(elements);
    if (!isSyncing) _cleanEvents();
  }

  /// Sync all database events.
  Future<void> synchronizeAll() async
  {
    if (isSyncing) return;
    isSyncing = true;

    var syncBatch = _databaseManager.batch();
    var cloudRecordChanges = <CKRecordChange>[];

    for (var i=0; i < _l.length; i++)
    {
      await _l[i].synchronize(_databaseManager, syncBatch, cloudRecordChanges);
      _l.removeAt(i);
      i--;
    }

    isSyncing = false;

    await syncBatch.commit();

    if (cloudRecordChanges.length > 0)
    {
      var modifyOperation = CKRecordModifyOperation(_databaseManager.cloudDatabase, zoneID: _databaseManager.cloudZone, recordChanges: cloudRecordChanges);
      var modifyCallback = await modifyOperation.execute();
      for (var recordMetadata in modifyCallback.response ?? [])
      {
        if (recordMetadata.recordType == null) continue;
        await _databaseManager.updateChangeTag(recordMetadata);
      }
    }
  }

  void _cleanEvents() // TODO: Account for local vs cloud changes
  {
    this._l.forEach((event) {
      switch (event.recordChange.operationType)
      {
        case CKRecordOperationType.CREATE:
          var deleteEvents = this._l.where((testEvent) => testEvent._objectID == event._objectID && testEvent.recordChange.operationType == CKRecordOperationType.DELETE);
          if (deleteEvents.isNotEmpty)
          {
            this._l.remove(event);
            this._l.remove(deleteEvents.first);

            this._l.removeWhere((testEvent) => testEvent._objectID == event._objectID);
            return;
          }

          var updateEvents = this._l.where((testEvent) => testEvent._objectID == event._objectID && testEvent.recordChange.operationType == CKRecordOperationType.UPDATE);
          if (updateEvents.isNotEmpty)
          {
            event.recordChange.localObject = updateEvents.last.recordChange.localObject;
            updateEvents.forEach((updateEvent) {
              this._l.remove(updateEvent);
            });
          }
          break;

        case CKRecordOperationType.UPDATE:
        case CKRecordOperationType.REPLACE:
        case CKRecordOperationType.FORCE_UPDATE:
        case CKRecordOperationType.FORCE_REPLACE:
          var updateEvents = this._l.where((testEvent) => testEvent != event && testEvent._objectID == event._objectID && testEvent.recordChange.operationType == CKRecordOperationType.UPDATE);
          if (updateEvents.isNotEmpty)
          {
            event.recordChange.localObject = updateEvents.last.recordChange.localObject;
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
