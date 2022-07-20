import 'package:flutter_test/flutter_test.dart';
import 'package:cloudkit_flutter/cloudkit_flutter.dart';

import 'cloudkit_flutter_test.reflectable.dart'; // Import generated code
// Run `flutter pub run build_runner build test` from the root directory to generate cloudkit_flutter_test.reflectable.dart code

import 'model/schedule.dart';
import 'model/week_schedule.dart';

const scheduleStructureString =
"""CKRecordData: {
  localType: Schedule
  ckRecordType: Schedule
  fields: [
    CKFieldData: {
      localName: uuid
      ckName: recordName
      type: CKFieldType: {
        local: String
        record: STRING
      }
    }, 
    CKFieldData: {
      localName: code
      ckName: scheduleCode
      type: CKFieldType: {
        local: String
        record: STRING
      }
    }, 
    CKFieldData: {
      localName: periodTimes
      ckName: periodTimes
      type: CKFieldType: {
        local: List<String>
        record: STRING_LIST
      }
    }, 
    CKFieldData: {
      localName: periodNumbers
      ckName: periodNumbers
      type: CKFieldType: {
        local: List<int>
        record: INT64_LIST
      }
    }]
}""";

const scheduleObjectString =
"""Schedule: {
  code: T4.
  periodTimes: [08:30-10:15, 10:20-10:40, 10:45-12:30]
  periodNumbers: [1, 9, 8]
}""";

const weekScheduleObjectString =
"""WeekSchedule: {
  startTime: 2019-06-30 12:00:00.000
  schedules: [H, H, H, H, H]
}""";

void main() {
  initializeReflectable();

  CKRecordParser.createRecordStructures([
    Schedule,
    WeekSchedule
  ]);

  test('record structure conversion', () {
    expect(CKRecordParser.getRecordStructureFromLocalType(Schedule).toString(), scheduleStructureString);

    Schedule localSchedule = CKRecordParser.recordToLocalObject<Schedule>({
      "recordName": "3D017D61-02FA-4D6E-BE27-BEE14C9057A5",
      "recordType": "Schedule",
      "fields": {
        "periodTimes": {
          "value": [
            "08:30-10:15",
            "10:20-10:40",
            "10:45-12:30"
          ],
          "type": "STRING_LIST"
        },
        "periodNumbers": {
          "value": [
            1,
            9,
            8
          ],
          "type": "INT64_LIST"
        },
        "scheduleCode": {
          "value": "T4.",
          "type": "STRING"
        }
      }
    }, CKDatabase.PUBLIC_DATABASE);
    expect(localSchedule.toString(), scheduleObjectString);

    WeekSchedule localWeekSchedule = CKRecordParser.recordToLocalObject<WeekSchedule>({
      "recordName": "3B253A57-EF12-4087-AF55-0D0A8F1DA599",
      "recordType": "WeekSchedules",
      "fields": {
        "schedules": {
          "value": [
            "H",
            "H",
            "H",
            "H",
            "H"
          ],
          "type": "STRING_LIST"
        },
        "weekStartDate": {
          "value": 1561921200000,
          "type": "TIMESTAMP"
        }
      }
    }, CKDatabase.PUBLIC_DATABASE);
    expect(localWeekSchedule.toString(), weekScheduleObjectString);
  });
}
