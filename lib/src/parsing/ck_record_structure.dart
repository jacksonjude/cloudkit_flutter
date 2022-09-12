import '/reflectable.dart';

import 'ck_field_structure.dart';
import 'annotations/ck_record_type_annotation.dart';

class CKRecordStructure
{
  final Type localType;
  final String ckRecordType;
  final ClassMirror localClassMirror;
  final CKRecordTypeAnnotation? recordTypeAnnotation;
  List<CKFieldStructure> fields = [];

  CKRecordStructure(this.localType, this.ckRecordType, this.localClassMirror, this.recordTypeAnnotation);

  @override
  String toString() {
    String stringOutput = "";

    stringOutput += "CKRecordData: {";
    stringOutput += "\n  localType: " + localType.toString();
    stringOutput += "\n  ckRecordType: " + ckRecordType;
    stringOutput += "\n  fields: " + fields.toString();
    stringOutput += "\n}";

    return stringOutput;
  }
}