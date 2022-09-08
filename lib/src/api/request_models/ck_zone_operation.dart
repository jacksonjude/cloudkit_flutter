import '/src/ck_constants.dart';
import 'ck_zone.dart';

class CKZoneOperation
{
  CKZone zone;
  CKZoneOperationType operationType;

  CKZoneOperation(this.zone, this.operationType);

  Map<String, dynamic> toJSON() => {
    "zone": {"zoneID": zone.toJSON()},
    "operationType": operationType.toString()
  };
}

class CKZoneOperationType extends StringConstant
{
  static const CREATE = CKZoneOperationType("create");
  static const DELETE = CKZoneOperationType("delete");

  const CKZoneOperationType(String operation) : super(operation);
}