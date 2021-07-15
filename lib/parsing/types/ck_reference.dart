import '../../api/ck_operation.dart';
import '../../api/request_models/ck_filter.dart';
import '../../api/request_models/ck_zone.dart';
import '../../ck_constants.dart';
import 'ck_field_type.dart';

class CKReference
{
  final String referenceUUID;
  final String database;
  final CKZone zoneID;

  CKReference(this.referenceUUID, this.database, {CKZone? zoneID}) : zoneID = zoneID ?? CKZone();

  Future<T?> fetchFromCloud<T extends Object>() async
  {
    var referenceUUIDFilter = CKFilter(CKComparator.EQUALS, CKConstants.RECORD_NAME_FIELD, referenceUUID, CKFieldType.STRING_TYPE);
    var queryOperation = CKRecordQueryOperation<T>(database, zoneID: zoneID, filters: [referenceUUIDFilter]);
    var operationCallback = await queryOperation.execute();

    if (operationCallback.state == CKOperationState.success && operationCallback.response.length > 0) return operationCallback.response[0];
  }

  Map<String,dynamic> toJSON() => {
    CKConstants.RECORD_NAME_FIELD: referenceUUID,
    "zoneID": zoneID.toJSON()
  };
}