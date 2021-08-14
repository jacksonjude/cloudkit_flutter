import 'package:reflectable/reflectable.dart';

import '../reflector.dart';

/// Represents the field type for the local field and the CloudKit record field.
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

  /// The local type as a string.
  final String local;
  /// The CloudKit record type as a string.
  final String record;
  /// The local type as a Type object.
  final Type? type;

  const CKFieldType(this.local, this.record, {this.type});

  /// Get the CKFieldType from a Type object.
  static CKFieldType fromLocalType(Type T)
  {
    return ALL_TYPES.firstWhere((fieldType) => fieldType.local == T.toString(), orElse: () {
      if (RegExp(r"^CKReference<(\w+)>$").hasMatch(T.toString())) return CKFieldType.REFERENCE_TYPE;
      else if (RegExp(r"^List<CKReference<(\w+)>>$").hasMatch(T.toString())) return CKFieldType.LIST_REFERENCE_TYPE;

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

  /// Get the [CKFieldType] from a CloudKit record type string.
  static CKFieldType fromRecordType(String recordType)
  {
    return ALL_TYPES.firstWhere((fieldType) => fieldType.record == recordType);
  }

  @override
  String toString()
  {
    String stringOutput = "";

    stringOutput += "CKFieldType: {";
    stringOutput += "\n        local: " + local;
    stringOutput += "\n        record: " + record;
    stringOutput += "\n      }";

    return stringOutput;
  }
}

/// The base class for a model class custom field type.
@reflector
abstract class CKCustomFieldType<T>
{
  /// The raw value of the custom field.
  T rawValue;

  CKCustomFieldType.fromRecordField(T raw) : rawValue = raw;
  T toRecordField() => rawValue;

  /// Get the [CKFieldType] of this custom field type.
  CKFieldType getFieldType(Type thisType) => CKFieldType(thisType.toString(), CKFieldType.fromLocalType(T).record, type: thisType);

  @override
  bool operator ==(other) => other is CKCustomFieldType && this.rawValue == other.rawValue;

  @override
  int get hashCode => rawValue.hashCode;
}