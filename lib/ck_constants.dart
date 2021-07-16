/// A class for CloudKit-related constants.
class CKConstants
{
  static const API_ENDPOINT = "https://api.apple-cloudkit.com";
  static const API_VERSION = "1";
  static const API_URL_BASE = "$API_ENDPOINT/database/$API_VERSION";

  static const API_TOKEN_PARAMETER = "ckAPIToken";
  static const WEB_AUTH_TOKEN_PARAMETER = "ckWebAuthToken";
  static const REDIRECT_URL_PARAMETER = "redirectURL";
  static const REDIRECT_URL_PATTERN_PREFIX = "cloudkit-";

  static const WEB_AUTH_TOKEN_STORAGE_KEY = "CK_WEB_AUTH_TOKEN";

  static const RECORD_NAME_FIELD = "recordName";
  static const RECORD_TYPE_FIELD = "recordType";
  static const RECORD_FIELDS_FIELD = "fields";

  static const DEFAULT_ZONE_NAME = "_defaultZone";

  /// Test if a CloudKit record field name is a system field name.
  static bool isSystemFieldName(String fieldName)
  {
    switch (fieldName)
    {
      case "recordName":
      case "share":
      case "parent":
      case "createdUserRecordName":
      case "createdTimestamp":
      case "modifiedTimestamp":
      case "modifiedUserRecordName":
        return true;
    }

    return false;
  }
}

/// A container class to denote the CloudKit environment as a string.
class CKEnvironment
{
  static const PRODUCTION_ENVIRONMENT = CKDatabase("production");
  static const DEVELOPMENT_ENVIRONMENT = CKDatabase("development");

  final String _environment;

  const CKEnvironment(this._environment);

  @override
  String toString() => _environment;
}

/// A container class to denote the CloudKit database as a string.
class CKDatabase
{
  static const PUBLIC_DATABASE = CKDatabase("public");
  static const SHARED_DATABASE = CKDatabase("shared");
  static const PRIVATE_DATABASE = CKDatabase("private");

  final String _database;

  const CKDatabase(this._database);

  @override
  String toString() => _database;
}