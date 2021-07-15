import 'types/ck_field_type.dart';

class CKFieldStructure {
  final String localName;
  final String ckName;
  final CKFieldType type;

  const CKFieldStructure(this.localName, this.ckName, this.type);

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