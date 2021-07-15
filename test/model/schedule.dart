import 'package:cloudkit_flutter/cloudkit_flutter_model.dart';

@reflector
@CKRecordTypeAnnotation("Schedule")
class Schedule
{
  @CKRecordNameAnnotation()
  String? uuid;

  @CKFieldAnnotation("scheduleCode")
  String? code;

  @CKFieldAnnotation("periodTimes")
  List<String>? blockTimes;

  @CKFieldAnnotation("periodNumbers")
  List<int>? blockNumbers;

  @override
  String toString() {
    String stringOutput = "";

    stringOutput += "Schedule: {";
    stringOutput += "\n  code: " + (code ?? "null");
    stringOutput += "\n  blockTimes: " + (blockTimes ?? "null").toString();
    stringOutput += "\n  blockNumbers: " + (blockNumbers ?? "null").toString();
    stringOutput += "\n}";

    return stringOutput;
  }
}