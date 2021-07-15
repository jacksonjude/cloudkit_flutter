import '../../ck_constants.dart';

class CKZone
{
  late final String zoneName;

  CKZone([String? zoneName])
  {
    this.zoneName = zoneName ?? CKConstants.DEFAULT_ZONE_NAME;
  }

  Map<String, dynamic> toJSON() => {
    'zoneName': zoneName
  };
}