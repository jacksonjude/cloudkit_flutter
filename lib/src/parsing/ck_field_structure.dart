import 'types/ck_field_type.dart';
import 'annotations/ck_field_annotation.dart';

class CKFieldStructure
{
  final String localName;
  final String ckName;
  final CKFieldType type;
  final CKFieldAnnotation annotation;

  const CKFieldStructure(this.localName, this.ckName, this.type, this.annotation);

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