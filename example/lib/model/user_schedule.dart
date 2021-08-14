import 'package:cloudkit_flutter/cloudkit_flutter_model.dart';

@reflector
@CKRecordTypeAnnotation("UserSchedule")
class UserSchedule
{
  @CKRecordNameAnnotation()
  String? uuid;

  @CKFieldAnnotation("profileImage")
  CKAsset? profileImage;

  @CKFieldAnnotation("periodNames")
  List<String>? periodNames;

  @CKFieldAnnotation("genderRaw")
  Gender? gender;

  @override
  String toString()
  {
    String stringOutput = "";

    stringOutput += "UserSchedule: {";
    stringOutput += "\n  profileImage: " + (profileImage ?? "null").toString();
    stringOutput += "\n  periodNames: " + (periodNames ?? "null").toString();
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