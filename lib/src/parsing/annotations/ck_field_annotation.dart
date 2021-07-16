/// An annotation to link a local model class field to a CloudKit record field.
class CKFieldAnnotation
{
  /// The CloudKit record field name.
  final String name;

  const CKFieldAnnotation(this.name);
}