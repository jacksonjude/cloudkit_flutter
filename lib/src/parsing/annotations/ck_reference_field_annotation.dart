import 'ck_field_annotation.dart';
import '../../ck_constants.dart';
import '../types/ck_reference.dart';
import '../../api/request_models/ck_zone.dart';

/// An annotation to link a local model class field to a CloudKit reference record field.
class CKReferenceFieldAnnotation<T> extends CKFieldAnnotation
{
  const CKReferenceFieldAnnotation(String name) : super(name);

  CKReference createReference(String referenceUUID, CKDatabase database, {CKZone? zone}) =>
      CKReference<T>(referenceUUID, database, zoneID: zone);
}