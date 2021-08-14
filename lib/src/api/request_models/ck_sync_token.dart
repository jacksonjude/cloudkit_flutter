/// A container class for a CloudKit sync token.
class CKSyncToken
{
  final String _rawValue;

  CKSyncToken(this._rawValue);

  @override toString() => _rawValue;
}