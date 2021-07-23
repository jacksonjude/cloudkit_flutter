import '../../api/ck_operation.dart';
import '../../api/request_models/ck_filter.dart';
import '../../api/request_models/ck_zone.dart';
import '../../ck_constants.dart';
import 'ck_field_type.dart';

/// A representation of a CloudKit reference.
class CKReference
{
  final String referenceUUID;
  final CKDatabase _database;
  final CKZone _zoneID;

  dynamic _cachedObject;

  CKReference(this.referenceUUID, this._database, {CKZone? zoneID}) : _zoneID = zoneID ?? CKZone();

  /// Fetch the referenced object from CloudKit
  Future<T?> fetchFromCloud<T extends Object>() async
  {
    var referenceUUIDFilter = CKFilter(CKConstants.RECORD_NAME_FIELD, CKFieldType.STRING_TYPE, referenceUUID, CKComparator.EQUALS);
    var queryOperation = CKRecordQueryOperation<T>(_database, zoneID: _zoneID, filters: [referenceUUIDFilter]);
    var operationCallback = await queryOperation.execute();

    if (operationCallback.state == CKOperationState.success && operationCallback.response.length > 0)
    {
      _cachedObject = operationCallback.response[0];
      return _cachedObject;
    }
  }

  /// Get the cached object
  T? getObject<T>() => _cachedObject as T?;

  /// Convert the reference to JSON.
  Map<String,dynamic> toJSON() => {
    CKConstants.RECORD_NAME_FIELD: referenceUUID,
    "zoneID": _zoneID.toJSON()
  };
}