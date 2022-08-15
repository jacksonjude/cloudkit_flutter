import 'package:flutter/material.dart';

import '../../api/request_models/ck_record_zone_changes_request.dart';
import '../../api/request_models/ck_sync_token.dart';
import '../../api/request_models/ck_zone.dart';
import '../../api/ck_local_database_manager.dart';
import '../../api/ck_operation.dart';
import '../../api/ck_api_manager.dart';
import '../../ck_constants.dart';

/// An annotation to link a local model class to a CloudKit record type.
class CKRecordTypeAnnotation<T extends Object>
{
  /// The CloudKit record type.
  final String type;

  const CKRecordTypeAnnotation(this.type);

  CKDatabaseEvent<T> createEvent(String localObjectID, CKDatabaseEventType type, {T? localObject, CKLocalDatabaseManager? manager})
  {
    var managerToUse = manager ?? CKLocalDatabaseManager.shared;
    return CKDatabaseEvent<T>(managerToUse, type, CKDatabaseEventSource.cloud, localObjectID, localObject);
  }

  CKRecordZoneChangesOperation<T> createRecordZoneChangesOperation(CKZone zone, CKDatabase database, {CKRecordZoneChangesRequest? zoneChangesRequest, CKSyncToken? syncToken, int? resultsLimit, List<String>? recordFields, bool? preloadAssets, CKAPIManager? apiManager, BuildContext? context})
  {
    return CKRecordZoneChangesOperation<T>(zone, database, zoneChangesRequest: zoneChangesRequest, syncToken: syncToken, resultsLimit: resultsLimit, recordFields: recordFields, preloadAssets: preloadAssets, apiManager: apiManager, context: context);
  }
}