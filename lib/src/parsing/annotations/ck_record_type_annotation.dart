import '../../api/ck_local_database_manager.dart';
import '../../ck_constants.dart';
import '../ck_record_parser.dart';

/// An annotation to link a local model class to a CloudKit record type.
class CKRecordTypeAnnotation<T extends Object>
{
  /// The CloudKit record type.
  final String type;

  const CKRecordTypeAnnotation(this.type);

  CKDatabaseEvent<T> createEvent(String localObjectID, CKDatabaseEventType type, {T? localObject})
  {
    return CKDatabaseEvent<T>(type, CKDatabaseEventSource.cloud, localObjectID, localObject);
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