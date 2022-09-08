import '/src/ck_constants.dart';
import '/src/parsing/ck_record_parser.dart';
import '/src/database/ck_database_event.dart';
import '/src/api/request_models/ck_record_change.dart';

/// An annotation to link a local model class to a CloudKit record type.
class CKRecordTypeAnnotation<T extends Object>
{
  /// The CloudKit record type.
  final String type;

  const CKRecordTypeAnnotation(this.type);

  CKDatabaseEvent<T> createCloudEvent(CKRecordChange recordChange)
  {
    return CKDatabaseEvent<T>(recordChange, CKDatabaseEventSource.cloud);
  }

  T recordToLocalObject(dynamic recordMap, CKDatabase database)
  {
    return CKRecordParser.recordToLocalObject<T>(recordMap as Map<String,dynamic>, database);
  }

  Future<void> preloadAssets(T localObject) async
  {
    await CKRecordParser.preloadAssets<T>(localObject);
  }
}