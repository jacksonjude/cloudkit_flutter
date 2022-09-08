/// A representation of a CloudKit sort descriptor.
class CKSortDescriptor
{
  final String _fieldName;
  final bool _ascending;

  CKSortDescriptor(this._fieldName, this._ascending);

  /// Convert the sort descriptor to JSON.
  Map<String, dynamic> toJSON() => {
    'fieldName': _fieldName,
    'ascending': _ascending
  };

  static CKSortDescriptor fromJSON(Map<String, dynamic> json) => CKSortDescriptor(
    json['fieldName'],
    json['ascending']
  );
}