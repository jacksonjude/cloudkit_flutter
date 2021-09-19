import 'ck_field_annotation.dart';
import '../../ck_constants.dart';
import '../types/ck_reference.dart';
import '../../api/request_models/ck_zone.dart';

/// An annotation to link a local model class field to a CloudKit reference record field.
class CKReferenceFieldAnnotation extends CKFieldAnnotation
{
  final CKReferenceGenerator _generator;

  const CKReferenceFieldAnnotation(String name, this._generator) : super(name);

  CKReference createReference(String referenceUUID, {CKDatabase? database, CKZone? zone}) =>
    _generator.createReference(referenceUUID, database: database, zone: zone);
}

class CKReferenceGenerator<T>
{
  /// The database for the reference generator.
  final CKDatabase? _database;

  const CKReferenceGenerator([this._database]);

  CKReference createReference(String referenceUUID, {CKDatabase? database, CKZone? zone}) =>
    CKReference<T>(referenceUUID, this._database ?? database!, zoneID: zone);
}