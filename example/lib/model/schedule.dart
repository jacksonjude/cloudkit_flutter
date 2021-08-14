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
  List<String>? periodTimes;

  @CKFieldAnnotation("periodNumbers")
  List<int>? periodNumbers;

  @override
  String toString()
  {
    String stringOutput = "";

    stringOutput += "Schedule: {";
    stringOutput += "\n  code: " + (code ?? "null");
    stringOutput += "\n  periodTimes: " + (periodTimes ?? "null").toString();
    stringOutput += "\n  periodNumbers: " + (periodNumbers ?? "null").toString();
    stringOutput += "\n}";

    return stringOutput;
  }
}