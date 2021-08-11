import 'package:cloudkit_flutter/cloudkit_flutter_model.dart';

@reflector
@CKRecordTypeAnnotation("WeekSchedule")
class WeekSchedule
{
  @CKRecordNameAnnotation()
  String? uuid;

  @CKFieldAnnotation("weekStartDate")
  DateTime? startTime;

  @CKFieldAnnotation("schedules")
  List<String>? schedules;

  @override
  String toString() {
    String stringOutput = "";

    stringOutput += "WeekSchedule: {";
    stringOutput += "\n  startTime: " + (startTime ?? "null").toString();
    stringOutput += "\n  schedules: " + (schedules ?? "null").toString();
    stringOutput += "\n}";

    return stringOutput;
  }
}