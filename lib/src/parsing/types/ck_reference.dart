import '/src/api/ck_operation.dart';
import '/src/api/request_models/ck_filter.dart';
import '/src/api/request_models/ck_zone.dart';
import '/src/ck_constants.dart';
import '/src/database/ck_local_database_manager.dart';
import 'ck_field_type.dart';

/// A representation of a CloudKit reference.
class CKReference<T extends Object>
{
  final String referenceUUID;
  final CKDatabase _database;
  final CKZone _zoneID;

  T? _cachedObject;

  CKReference(this.referenceUUID, this._database, {CKZone? zoneID}) : _zoneID = zoneID ?? CKZone();

  /// Fetch the referenced object from CloudKit.
  Future<T?> fetchCloud() async
  {
    var referenceUUIDFilter = CKFilter(CKConstants.RECORD_NAME_FIELD, CKFieldType.STRING_TYPE, referenceUUID, CKComparator.EQUALS);
    var queryOperation = CKRecordQueryOperation<T>(_database, zoneID: _zoneID, filters: [referenceUUIDFilter]);
    var operationCallback = await queryOperation.execute();

    if (operationCallback.state == CKOperationState.success && operationCallback.response!.length > 0)
    {
      _cachedObject = operationCallback.response![0];
      return _cachedObject;
    }

    return null;
  }

  /// Fetch the referenced object from SQLite.
  Future<T?> fetch({CKLocalDatabaseManager? manager}) async
  {
    var managerToUse = manager ?? CKLocalDatabaseManager.shared;
    var localObject = await managerToUse.queryByID<T>(referenceUUID);
    _cachedObject = localObject;
    return localObject;
  }

  /// Fetch a list of referenced objects from SQLite.
  static Future<List<T>> fetchAll<T extends Object>(List<CKReference<T>> references, {CKLocalDatabaseManager? manager}) async
  {
    List<T> localObjects = [];
    for (var reference in references)
    {
      var localObject = await reference.fetch(manager: manager);
      if (localObject == null) continue;
      localObjects.add(localObject);
    }
    return localObjects;
  }

  /// Get a stream for the referenced object from SQLite.
  Stream<T> stream({CKLocalDatabaseManager? manager})
  {
    var managerToUse = manager ?? CKLocalDatabaseManager.shared;
    return managerToUse.createQueryByID<T>(referenceUUID);
  }

  /// Get the cached object.
  T? get cache => _cachedObject;

  /// Convert the reference to JSON.
  Map<String,dynamic> toJSON() => {
    CKConstants.RECORD_NAME_FIELD: referenceUUID,
    "database": _database.toString(),
    "zoneID": _zoneID.toJSON()
  };
}