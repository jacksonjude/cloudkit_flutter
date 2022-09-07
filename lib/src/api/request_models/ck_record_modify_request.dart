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

/// A string constant class for record operation types.
class CKRecordOperationType
{
  static const CREATE = CKRecordOperationType("create");
  static const UPDATE = CKRecordOperationType("update");
  static const FORCE_UPDATE = CKRecordOperationType("forceUpdate");
  static const REPLACE = CKRecordOperationType("replace");
  static const FORCE_REPLACE = CKRecordOperationType("forceReplace");
  static const DELETE = CKRecordOperationType("delete");
  static const FORCE_DELETE = CKRecordOperationType("forceDelete");

  final String _operation;

  const CKRecordOperationType(this._operation);

  @override
  String toString() => _operation;
}