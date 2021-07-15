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
}

class CKEnvironment
{
  static const PRODUCTION_ENVIRONMENT = "production";
  static const DEVELOPMENT_ENVIRONMENT = "development";
}

class CKDatabase
{
  static const PUBLIC_DATABASE = "public";
  static const SHARED_DATABASE = "shared";
  static const PRIVATE_DATABASE = "private";
}