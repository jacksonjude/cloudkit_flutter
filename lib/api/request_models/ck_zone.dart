import '../../ck_constants.dart';

/// A container class for a CloudKit zone ID.
class CKZone
{
  final String _zoneName;

  CKZone([String? zoneName]) : this._zoneName = zoneName ?? CKConstants.DEFAULT_ZONE_NAME;

  /// Convert the zone to JSON.
  Map<String, dynamic> toJSON() => {
    'zoneName': _zoneName
  };
}