import 'ck_record_change.dart';
import 'ck_zone.dart';

/// A container class for a CloudKit record modify request.
class CKRecordModifyRequest
{
  final List<CKRecordOperation> _operations;
  final CKZone _zoneID;
  final bool? _atomic;
  final List<String>? _recordFields;
  final bool? _numbersAsStrings;

  CKRecordModifyRequest(this._operations, this._zoneID, this._atomic, this._recordFields, this._numbersAsStrings);

  /// Convert the record modify request to JSON.
  Map<String, dynamic> toJSON() => {
    'operations': _operations.map((operation) => operation.toJSON()),
    'zoneID': _zoneID.toJSON(),
    'atomic': _atomic,
    'desiredKeys': _recordFields,
    'numbersAsStrings': _numbersAsStrings
  };
}

/// A container class for a single CloudKit record operation.
class CKRecordOperation
{
  final CKRecordOperationType _operationType;
  final Map<String, dynamic> _record;
  final List<String>? _recordFields;

  CKRecordOperation(this._operationType, this._record, this._recordFields);

  /// Convert the record operation to JSON.
  Map<String, dynamic> toJSON() => {
    'operationType': _operationType.toString(),
    'record': _record,
    'desiredKeys': _recordFields
  };
}