import 'package:flutter_test/flutter_test.dart';
import 'package:cloudkit_flutter/cloudkit_flutter.dart';

import 'cloudkit_flutter_test.reflectable.dart'; // Import generated code
// Run `flutter pub run build_runner build test` from the root directory to generate cloudkit_flutter_test.reflectable.dart code

import 'model/schedule.dart';
import 'model/week_schedule.dart';
import 'model/employee.dart';
import 'model/department.dart';

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

void main() async {
  initializeReflectable();

  CKRecordParser.createRecordStructures([
    Schedule,
    WeekSchedule,
    Employee,
    Department
  ], shouldInitializeDatabase: false);

  testRecordParser();
  await testPublicDatabase();
}

void testRecordParser()
{
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

Future<void> testPublicDatabase() async
{
  const String ckContainer = "iCloud.com.jacksonjude.CloudKitTest";
  const String ckAPIToken = "0a4566adae1a9ae667cb694b82400eac08ef228f0bba384273248012a7dfc54c";
  const CKEnvironment ckEnvironment = CKEnvironment.DEVELOPMENT_ENVIRONMENT;

  await CKAPIManager.initManager(ckContainer, ckAPIToken, ckEnvironment, shouldFetchWebAuthToken: false);

  test('recordName filter fetch', () async {
    var recordNameFilter = CKFilter(CKConstants.RECORD_NAME_FIELD, CKFieldType.STRING_TYPE, "8D863AD6-F966-DB2B-B809-AC258B72BDCE", CKComparator.EQUALS);
    var recordNameQueryOperation = CKRecordQueryOperation<Employee>(CKDatabase.PUBLIC_DATABASE, filters: [recordNameFilter], preloadAssets: true);
    CKOperationCallback<List<Employee>> recordNameQueryCallback = await recordNameQueryOperation.execute();
    expect(recordNameQueryCallback.state, CKOperationState.success);
    if (recordNameQueryCallback.state == CKOperationState.success && recordNameQueryCallback.response!.length > 0)
    {
      var employee = recordNameQueryCallback.response![0];
      expect(employee.name, "Bob");
      var department = await employee.department?.fetchFromCloud();
      expect(department?.name, "Athletics");
    }
  });

  test('other field filter fetch', () async {
    var nicknameFilter = CKFilter("nicknames", CKFieldType.LIST_STRING_TYPE, "Bobby", CKComparator.LIST_CONTAINS);
    var nicknameQueryOperation = CKRecordQueryOperation<Employee>(CKDatabase.PUBLIC_DATABASE, filters: [nicknameFilter], preloadAssets: true);
    CKOperationCallback<List<Employee>> nicknameQueryCallback = await nicknameQueryOperation.execute();
    expect(nicknameQueryCallback.state, CKOperationState.success);
    expect(nicknameQueryCallback.response?.length, 1);
  });
}
