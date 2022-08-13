import 'package:cloudkit_flutter/cloudkit_flutter_model.dart';
import 'employee.dart';

@reflector
@CKRecordTypeAnnotation<Department>("Department")
class Department
{
  @CKRecordNameAnnotation()
  String? uuid;

  @CKFieldAnnotation("name")
  String? name;

  @CKFieldAnnotation("location")
  String? location;

  @CKReferenceFieldAnnotation<Employee>("employees")
  List<CKReference<Employee>>? employees;

  @override
  String toString()
  {
    String stringOutput = "";

    stringOutput += "Department: {";
    stringOutput += "\n  uuid: " + (uuid ?? "null");
    stringOutput += "\n  name: " + (name ?? "null");
    stringOutput += "\n  location: " + (location ?? "null");
    stringOutput += "\n}";

    return stringOutput;
  }
}