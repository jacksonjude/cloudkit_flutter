import 'types/ck_field_type.dart';
import 'annotations/ck_field_annotation.dart';

class CKFieldStructure
{
  final String localName;
  final String ckName;
  final CKFieldType type;
  final String ckRecordType;
  final CKFieldAnnotation annotation;

  const CKFieldStructure(this.localName, this.ckName, this.type, this.ckRecordType, this.annotation);

  @override
  String toString() {
    String stringOutput = "";

    stringOutput += "\n    CKFieldData: {";
    stringOutput += "\n      localName: " + localName;
    stringOutput += "\n      ckName: " + ckName;
    stringOutput += "\n      type: " + type.toString();
    stringOutput += "\n    }";

    return stringOutput;
  }
}

class CKFieldPath
{
  final String recordType;
  final String recordName;
  final String fieldName;

  CKFieldPath(this.recordType, this.recordName, this.fieldName);

  CKFieldPath.fromFieldStructure(this.recordName, CKFieldStructure fieldStructure) :
        recordType = fieldStructure.ckRecordType,
        fieldName = fieldStructure.ckName;

  @override
  String toString() => recordName + "_" + fieldName;
}