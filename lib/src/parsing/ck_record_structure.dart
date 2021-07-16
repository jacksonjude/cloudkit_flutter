import 'package:reflectable/reflectable.dart';

import 'ck_field_structure.dart';

class CKRecordStructure {
  final Type localType;
  final String ckRecordType;
  final ClassMirror localClassMirror;
  List<CKFieldStructure> fields = [];

  CKRecordStructure(this.localType, this.ckRecordType, this.localClassMirror);

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