import 'ck_field_annotation.dart';
import '/src/ck_constants.dart';
import '/src/parsing/types/ck_reference.dart';
import '/src/api/request_models/ck_zone.dart';

/// An annotation to link a local model class field to a CloudKit reference record field.
class CKReferenceFieldAnnotation<T extends Object> extends CKFieldAnnotation
{
  const CKReferenceFieldAnnotation(String name) : super(name);

  CKReference createReference(String referenceUUID, CKDatabase database, {CKZone? zone}) =>
      CKReference<T>(referenceUUID, database, zoneID: zone);

  List<CKReference<T>> createReferenceList() => <CKReference<T>>[];
}