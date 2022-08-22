/// A class for CloudKit-related constants.
class CKConstants
{
  static const API_ENDPOINT = "https://api.apple-cloudkit.com";
  static const API_VERSION = "1";

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

class StringConstant
{
  final String _value;

  const StringConstant(this._value);

  @override
  String toString() => _value;
}

class CKAPIModule extends StringConstant
{
  static const DATABASE = CKAPIModule("database");
  static const DEVICE = CKAPIModule("device");

  const CKAPIModule(String module) : super(module);
}

/// A container class to denote the CloudKit environment as a string.
class CKEnvironment extends StringConstant
{
  static const PRODUCTION_ENVIRONMENT = CKEnvironment("production");
  static const DEVELOPMENT_ENVIRONMENT = CKEnvironment("development");

  const CKEnvironment(String environment) : super(environment);
}

/// A container class to denote the CloudKit database as a string.
class CKDatabase extends StringConstant
{
  static const PUBLIC_DATABASE = CKDatabase("public");
  static const SHARED_DATABASE = CKDatabase("shared");
  static const PRIVATE_DATABASE = CKDatabase("private");

  static const databases = [PUBLIC_DATABASE, SHARED_DATABASE, PRIVATE_DATABASE];

  const CKDatabase(String database) : super(database);
}