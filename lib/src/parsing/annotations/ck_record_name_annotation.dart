import 'ck_field_annotation.dart';
import '/src/ck_constants.dart';

/// An annotation to link the local model class UUID field to the CloudKit record name field.
class CKRecordNameAnnotation extends CKFieldAnnotation
{
  const CKRecordNameAnnotation() : super(CKConstants.RECORD_NAME_FIELD);
}