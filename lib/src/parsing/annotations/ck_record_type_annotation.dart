import '../../api/ck_local_database_manager.dart';

/// An annotation to link a local model class to a CloudKit record type.
class CKRecordTypeAnnotation<T extends Object>
{
  /// The CloudKit record type.
  final String type;

  const CKRecordTypeAnnotation(this.type);

  CKDatabaseEvent createEvent(String localObjectID, CKDatabaseEventType type, {T? localObject, CKLocalDatabaseManager? manager})
  {
    var managerToUse = manager ?? CKLocalDatabaseManager.shared;
    return CKDatabaseEvent<T>(managerToUse, type, CKDatabaseEventSource.cloud, localObjectID, localObject);
  }
}