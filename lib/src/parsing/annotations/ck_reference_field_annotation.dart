import 'ck_field_annotation.dart';
import '/src/ck_constants.dart';
import '/src/parsing/types/ck_reference.dart';
import '/src/api/request_models/ck_zone.dart';

/// An annotation to link a local model class reference field to a CloudKit record reference field.
class CKReferenceFieldAnnotation<T extends Object> extends CKFieldAnnotation
{
  final bool isParent;

  const CKReferenceFieldAnnotation(String name, {this.isParent = false}) : super(name);

  CKReference createReference(String referenceUUID, CKDatabase database, {CKZone? zone}) =>
      CKReference<T>(referenceUUID, database, zoneID: zone);

  List<CKReference<T>> createReferenceList() => <CKReference<T>>[];
}