import 'package:cloudkit_flutter/cloudkit_flutter_model.dart';
import 'department.dart';

@reflector
@CKRecordTypeAnnotation<Employee>("Employee")
class Employee
{
  @CKRecordNameAnnotation()
  String? uuid;

  @CKFieldAnnotation("name")
  String? name;

  @CKFieldAnnotation("nicknames")
  List<String>? nicknames;

  @CKFieldAnnotation("genderRaw")
  Gender? gender;

  @CKFieldAnnotation("profileImage")
  CKAsset? profileImage;

  @CKReferenceFieldAnnotation<Department>("department")
  CKReference<Department>? department;

  @override
  String toString()
  {
    String stringOutput = "";

    stringOutput += "Employee: {";
    stringOutput += "\n  uuid: " + (uuid ?? "null");
    stringOutput += "\n  name: " + (name ?? "null");
    stringOutput += "\n  nicknames: " + (nicknames ?? "null").toString();
    stringOutput += "\n  gender: " + (gender ?? "null").toString();
    stringOutput += "\n}";

    return stringOutput;
  }
}

@reflector
class Gender extends CKCustomFieldType<int>
{
  static final unknown = Gender.withName(3, "Unknown");
  static final female = Gender.withName(0, "Female");
  static final male = Gender.withName(1, "Male");
  static final other = Gender.withName(2, "Other");
  static final genders = [female, male, other, unknown];

  String name;

  Gender() :
    name = unknown.name,
    super.fromRecordField(unknown.rawValue);
  Gender.fromRecordField(int raw) :
    name = genders[raw].name,
    super.fromRecordField(raw);

  Gender.withName(int raw, String name) :
    name = name,
    super.fromRecordField(raw);

  @override
  String toString() => name;
}