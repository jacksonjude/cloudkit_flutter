import 'package:reflectable/reflectable.dart';

import '../reflector.dart';

// Types as strings (needed because it is difficult to directly get the type of an object with a generic, such as List<String>)
class CKFieldType
{
  static const STRING_TYPE = CKFieldType("String", "STRING");
  static const INT_TYPE = CKFieldType("int", "INT64");
  static const DOUBLE_TYPE = CKFieldType("double", "DOUBLE");
  static const LIST_STRING_TYPE = CKFieldType("List<String>", "STRING_LIST");
  static const LIST_INT_TYPE = CKFieldType("List<int>", "INT64_LIST");
  static const DATETIME_TYPE = CKFieldType("DateTime", "TIMESTAMP");

  static const REFERENCE_TYPE = CKFieldType("CKReference", "REFERENCE");
  static const LIST_REFERENCE_TYPE = CKFieldType("List<CKReference>", "REFERENCE_LIST");

  static const ASSET_TYPE = CKFieldType("CKAsset", "ASSETID");

  static const ALL_TYPES = [STRING_TYPE, INT_TYPE, DOUBLE_TYPE, LIST_STRING_TYPE, LIST_INT_TYPE, DATETIME_TYPE, REFERENCE_TYPE, LIST_REFERENCE_TYPE, ASSET_TYPE];

  final String local;
  final String record;
  final Type? type;

  const CKFieldType(this.local, this.record, {this.type});

  static CKFieldType fromLocalType(Type T)
  {
    return ALL_TYPES.firstWhere((fieldType) => fieldType.local == T.toString(), orElse: () {
      try
      {
        ClassMirror currentClassMirrorForType = reflector.reflectType(T) as ClassMirror; //TODO: Messy solution :(
        var newTestInstance = currentClassMirrorForType.newInstance("", []);
        if (newTestInstance is CKCustomFieldType) return newTestInstance.getFieldType(T);
      }
      on Exception catch (e)
      {
        print(e);
      }

      throw UnimplementedError("Type (" + T.toString() + ") does not have a corresponding field type");
    });
  }

  static CKFieldType fromRecordType(String recordType)
  {
    return ALL_TYPES.firstWhere((fieldType) => fieldType.record == recordType);
  }

  @override
  String toString() {
    String stringOutput = "";

    stringOutput += "CKFieldType: {";
    stringOutput += "\n        local: " + local;
    stringOutput += "\n        record: " + record;
    stringOutput += "\n      }";

    return stringOutput;
  }
}

@reflector
abstract class CKCustomFieldType<T>
{
  T rawValue;

  CKCustomFieldType.fromRecordField(T raw) : rawValue = raw;
  T toRecordField() => rawValue;

  CKFieldType getFieldType(Type thisType) => CKFieldType(thisType.toString(), CKFieldType.fromLocalType(T).record, type: thisType);
}