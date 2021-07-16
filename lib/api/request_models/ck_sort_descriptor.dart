class CKSortDescriptor
{
  final String fieldName;
  final bool ascending;

  CKSortDescriptor(this.fieldName, this.ascending);

  Map<String, dynamic> toJSON() => {
    'fieldName': fieldName,
    'ascending': ascending
  };
}