## 0.1.0

- Automatic model class conversion from CloudKit JSON (via annotation & reflection, `CKRecordParser`)
- Support for most CloudKit base types & custom types with a raw base type (`CKCustomFieldType`)
- Built-in Sign in with iCloud authentication (via webview_flutter)
- `CKCurrentUserOperation` to fetch current user id (good test for CloudKit sign-in)
- `CKRecordQueryOperation` with `CKFilter`, `CKSortDescriptor`, and `CKZone` support

## 0.1.1

- Fixed error on SharedPreferences access (`fetchWebAuthToken` & `saveWebAuthToken`)
- Updated README & pubspec repo field