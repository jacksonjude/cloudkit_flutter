import '/src/ck_constants.dart';
import '/src/parsing/ck_record_parser.dart';

class CKRecordChange<T>
{
  CKRecordMetadata recordMetadata;
  CKRecordOperationType operationType;
  T? localObject;
  Map<String, dynamic>? recordJSON;

  CKRecordChange(String objectID, this.operationType, Type objectType, {this.localObject, this.recordJSON, String? recordChangeTag}) : recordMetadata = CKRecordMetadata(objectID, localType: objectType, changeTag: recordChangeTag);
}

class CKRecordMetadata
{
  String id;
  Type? localType;
  String? recordType;
  String? changeTag;

  CKRecordMetadata(this.id, {Type? localType, String? recordType, this.changeTag}) :
        localType = localType ?? CKRecordParser.getRecordStructureFromRecordType(recordType!).localType,
        recordType = recordType ?? (localType != dynamic ? CKRecordParser.getRecordStructureFromLocalType(localType!).ckRecordType : null);
}

/// A string constant class for record operation types.
class CKRecordOperationType extends StringConstant
{
  static const CREATE = CKRecordOperationType("create");
  static const UPDATE = CKRecordOperationType("update");
  static const FORCE_UPDATE = CKRecordOperationType("forceUpdate");
  static const REPLACE = CKRecordOperationType("replace");
  static const FORCE_REPLACE = CKRecordOperationType("forceReplace");
  static const DELETE = CKRecordOperationType("delete");
  static const FORCE_DELETE = CKRecordOperationType("forceDelete");

  const CKRecordOperationType(String operation) : super(operation);
}