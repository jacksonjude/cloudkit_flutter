# cloudkit_flutter

CloudKit support for Flutter via [CloudKit Web Services](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference), with built-in database synchronization. Inspired by [DroidNubeKit](https://github.com/jaumecornado/DroidNubeKit).

1. [Supported Platforms](#supported-platforms)
2. [Setup](#setup)
3. [Model Classes](#model-classes)
    * [Annotation](#annotation)
    * [Supported Field Types](#supported-field-types)
    * [Custom Field Types](#custom-field-types)
    * [Reflection Setup](#reflection-setup)
4. [API Initialization](#api-initialization)
5. [Local Database Setup](#local-database-setup)
    * [Database Initialization](#database-initialization)
    * [Cloud Sync](#cloud-sync)
6. [Usage](#usage)
    * [Local Database Operations](#local-database-operations)
    * [API Operations](#api-operations)
    * [API Request Models](#api-request-models)
7. [Library Sections](#library-sections)

## Supported Platforms

Currently, this library only supports Android (and iOS, although the built-in CloudKit library makes this fairly obsolete). The lack of Flutter Web support is due to one of the dependencies, [webview_flutter](https://pub.dev/packages/webview_flutter/score "webview_flutter"), not supporting the Flutter Web platform 🙄.

## Setup

Within your app, there are three stages involved in setting up this library, described in the sections below:
- Create your model classes based on the record types in CloudKit and pass them into the [CKRecordParser](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_init/CKRecordParser-class.html).
- Initialize the [CKAPIManager](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_init/CKAPIManager-class.html) with your CloudKit container, environment, and API token.
- Initialize the [CKLocalDatabaseManager](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_init/CKLocalDatabaseManager-class.html) on a database or zone to sync CloudKit records automatically.

## Model Classes

### Annotation

In this library, model classes must be annotated and then scanned so that reflection can be used to seamlessly convert JSON CloudKit records to a local Dart object.

There are three main types of annotations used in model files:

- [@CKRecordTypeAnnotation](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_model/CKRecordTypeAnnotation-class.html): to denote the name of the record type on CloudKit, and placed before the class declaration
- [@CKRecordNameAnnotation](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_model/CKRecordNameAnnotation-class.html): to label the field within the local class where the CloudKit record name (a UUID) is stored
- [@CKFieldAnnotation](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_model/CKFieldAnnotation-class.html): to associate fields in the local Dart object with record fields in CloudKit
- [@CKCKReferenceFieldAnnotation](): a subclass of `CKFieldAnnotation`, used to associate a [CKReference](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_model/CKReference-class.html) field

Additionally, for the class to be scanned via reflection, you must tag the class with `@reflector` before the class declaration.

Below is an example of these annotations being used in a Dart file:

```dart
import 'package:cloudkit_flutter/cloudkit_flutter_model.dart';

@reflector
@CKRecordTypeAnnotation<Employee>("Employee")  // Include the CloudKit record type and the local type
class Schedule
{
  @CKRecordNameAnnotation() // No CloudKit record field name is needed as the field is always 'recordName'
  String? uuid;
  
  @CKFieldAnnotation("name") // Include the name of the CloudKit record field
  String? name;
  
  @CKFieldAnnotation("nicknames")
  List<String>? nicknames;
  
  @CKFieldAnnotation("genderRaw")
  Gender? gender;
  
  @CKFieldAnnotation("profileImage")
  CKAsset? profileImage;
  
  @CKReferenceFieldAnnotation<Department>("department") // Include the CloudKit reference record type and the local type
  CKReference<Department>? department;
}
```

### Supported Field Types

Currently, most of the field types supported in CloudKit can be used in local model classes.

Many are fairly basic:
- `String`
- `int`
- `double`
- `DateTime`
- `List<String>`
- `List<int>`

There are a couple that require some explanation:
- [CKReference](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_model/CKReference-class.html):
  The reference field type in CloudKit is used to create relations between two record types. The `CKReference` class has been created to represent this relation. To fetch the object associated with the reference, simply call the `fetch()` or `fetchCloud()` function.
- [CKAsset](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_model/CKAsset-class.html):
  The asset field type in CloudKit allows for the storage of literal bytes of data as a discrete asset. One common use for this type is to store an image. The `CKAsset` class has been created to represent this type, and it likewise has a `fetchAsset()` function to retrieve and cache the stored bytes. It also includes a `getAsImage()` function to convert the cached bytes to an image, if possible.
- Subclasses of [CKCustomFieldType](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_model/CKCustomFieldType-class.html):
  See [below](#custom-field-types).

\**More base field types will be added in later versions*

### Custom Field Types

Sometimes, a field within a CloudKit database only stores a raw value, to be later converted into an enum or more fully defined class when it reaches an app. To allow for custom classes to be used as types within model classes, the [CKCustomFieldType](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_model/CKCustomFieldType-class.html) class has been created.

There are several requirements for a subclass of [CKCustomFieldType](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_model/CKCustomFieldType-class.html):
- The class itself must provide a raw value type within the class declaration
- There must be a default constructor which calls [super.fromRecordField(T rawValue)](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_model/CKCustomFieldType/CKCustomFieldType.fromRecordField.html)
- There must be a [fromRecordField(T rawValue)](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_model/CKCustomFieldType/CKCustomFieldType.fromRecordField.html) constructor
- The class must be tagged with `@reflector`, similar to the model classes

Below is a basic example of a custom field type class, `Gender`, which has `int` as its raw value type:
```dart
import 'package:cloudkit_flutter/cloudkit_flutter_model.dart';

@reflector
class Gender extends CKCustomFieldType<int>
{
  // Static instances of Gender with a raw value and name
  static final female = Gender.withName(0, "Female");
  static final male = Gender.withName(1, "Male");
  static final other = Gender.withName(2, "Other");
  static final unknown = Gender.withName(3, "Unknown");
  static final genders = [female, male, other, unknown];
  
  String name;
  
  // Required constructors
  Gender() : name = unknown.name, super.fromRecordField(unknown.rawValue);
  Gender.fromRecordField(int raw) : name = genders[raw].name, super.fromRecordField(raw);
  
  // Used to create static instances above
  Gender.withName(int raw, String name) : name = name, super.fromRecordField(raw);
  
  // The default toString() for CKCustomFieldType outputs the rawValue, but here it makes more sense to output the name
  @override
  String toString() => name;
}
```

### Reflection Setup

**Whenever you make changes to your model classes or [CKCustomFieldType](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_model/CKCustomFieldType-class.html) subclasses**, you must regenerate object code to allow for reflection to be used within the library:
- Ensure that the [build_runner](https://pub.dev/packages/build_runner) package is installed in your app's pubspec, as it is required to run the following command.
- Generate the object code by running the following from the root folder of your Flutter project:
```sh
flutter pub run build_runner build lib
```
- Call `initializeReflectable()` (found within generated `*.reflectable.dart` files) at the start of your app before any other library calls are made.
- Call the [CKRecordParser.createRecordStructures](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_init/CKRecordParser/createRecordStructures.html) function, listing the direct types of the local model classes within the list:
```dart
CKRecordParser.createRecordStructures(List<Type> classTypes)
```
This call should directly precede the call to [CKAPIManager.initManager](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_init/CKAPIManager/initManager.html), as described [below](#api-initialization).

## API Initialization

Before calls to the CloudKit API can be made, four values must be provided to the [CKAPIManager](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_init/CKAPIManager-class.html):
- CloudKit Container: The container ID used by CloudKit, which is typically `iCloud.` + your bundle ID.
- CloudKit API Token: A token which must be created via the [CloudKit dashboard](https://icloud.developer.apple.com) under the "Tokens & Keys" section. **Importantly, you must select the option labelled ('cloudkit-' + container id + '://') within 'URL Redirect' for the 'Sign in Callback'. The custom URL can be any short string, such as 'redirect'.**
- CloudKit Environment: Changes whether the production or development environment is used. Corresponding values are provided as constants in the [CKEnvironment](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_init/CKEnvironment-class.html) class.
- Global Navigator Key: An optional `GlobalKey<NavigatorState>` which is passed into the `navigatorKey` property of your app widget. Used to display a popup screen for iCloud Sign-In when the private database is accessed.

To initialize the manager, these four values must be passed into [CKAPIManager.initManager](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_init/CKAPIManager/initManager.html):
```dart
CKAPIManager.initManager(String container, String apiToken, CKEnvironment environment, {GlobalKey<NavigatorState>? navigatorKey, CKAPIManager? manager}) async
```
This call should directly follow the call to [CKRecordParser.createRecordStructures](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_init/CKRecordParser/createRecordStructures.html), as described [above](#reflection-setup).

## Local Database Setup

The [CKLocalDatabaseManager](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_init/CKLocalDatabaseManager-class.html) is built on top of an SQLite database, and contains helper functions to automatically insert and query records as Dart model objects, while converting to JSON under the hood. It can also leverage notifications to automatically sync records as they are changed in real time.

### Database Initialization

Before an instance of [CKLocalDatabaseManager](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_init/CKLocalDatabaseManager-class.html) can be used, it must be provided:
- The `CKRecordStructure` objects generated by [CKRecordParser.createRecordStructures](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_init/CKRecordParser/createRecordStructures.html).
- (Optional) A [CKDatabase](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_api/CKDatabase-class.html) target, defaults to `CKDatabase.PRIVATE_DATABASE`
- (Optional) A [CKZone](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_api/CKZone-class.html) target, defaults to `CKZone()`

To initialize the database, these three values must be passed into [CKLocalDatabaseManager.initDatabase](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_init/CKLocalDatabaseManager/initDatabase.html):
```dart
CKLocalDatabaseManager.initDatabase(Map<Type,CKRecordStructure> recordStructures, {CKDatabase? database, CKZone? zone, CKLocalDatabaseManager? manager}) async
```

### Cloud Sync

To begin cloud synchronization, simply call [CKLocalDatabaseManager.shared.initCloudSync](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_init/CKLocalDatabaseManager/initCloudSync.html):
```dart
CKLocalDatabaseManager.shared.initCloudSync(CKAPNSEnvironment environment, {String? subscriptionID, CKAPIManager? apiManager}) async
```

This call will automatically create a zone subscription and register an APNS token to listen for changes in CloudKit. When changes occur, a notification is sent which triggers a [CKRecordZoneChangesOperation](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_api/CKRecordZoneChangesOperation-class.html) to sync the local database with the cloud.

## Usage

If syncing through the Local SQLite Database is [enabled](#cloud-sync), can use the [database operations](#local-database-operations) to query or modify the CloudKit database.

Alternatively, you can directly access the CloudKit API through [CKOperation](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_api/CKOperation-class.html) instances, which come in many [subclasses](#api-operations).

### Local Database Operations

#### [query](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_database/CKLocalDatabaseManager/query.html)

This method queries a list of Dart objects on the SQLite database for the provided type and SQLite `where` string:
```dart
Future<List<T>> CKLocalDatabaseManager.shared.query<T>([String? where, List? whereArgs]) async
```

#### [queryByID](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_database/CKLocalDatabaseManager/queryByID.html)

This method queries a Dart object on the SQLite database for the provided type with the given `id`:
```dart
Future<T?> CKLocalDatabaseManager.shared.queryByID<T>(String recordID) async
```

#### [insert](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_database/CKLocalDatabaseManager/insert.html)

This method inserts a given Dart object into the SQLite database, automatically tracking the event for upload to the cloud:
```dart
CKLocalDatabaseManager.shared.insert<T>(T localObject, {bool shouldUseReplace = false, bool shouldTrackEvent = true}) async
```

Optionally, the SQLite `REPLACE` command can be used instead, avoiding database collisions if the record already exists.

#### [update](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_database/CKLocalDatabaseManager/update.html)

This method updates a record in the SQLite database with the given Dart object, automatically tracking the event for upload to the cloud:
```dart
CKLocalDatabaseManager.shared.update<T>(T updatedLocalObject, {bool shouldTrackEvent = true}) async
```

#### [delete](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_database/CKLocalDatabaseManager/delete.html)

This method deletes a record in the SQLite database with the given id, automatically tracking the event for upload to the cloud:
```dart
CKLocalDatabaseManager.shared.delete<T>(String localObjectID, {bool shouldTrackEvent = true}) async
```

#### [streamObjects](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_database/CKLocalDatabaseManager/streamObjects.html)

This method creates a `Stream<List<T>>` object, which updates when changes occur in the database on the given object type, and can optionally filter results by an SQLite `where` string:
```dart
Stream<List<T>> CKLocalDatabaseManager.shared.streamObjects<T>([String? where, List? whereArgs])
```

#### [streamByID](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_database/CKLocalDatabaseManager/streamByID.html)

This method creates a `Stream<T>` object, which updates when changes occur in the database on the record with the given id:
```dart
Stream<T> CKLocalDatabaseManager.shared.streamObject<T>(String objectID)
```

#### [streamField](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_database/CKLocalDatabaseManager/streamField.html)

This method creates a `Stream<V>` object, which updates when changes occur in the database on a `CKReference` field within a record. It requires the `parentObject` and the reference field name:
```dart
Stream<V> CKLocalDatabaseManager.shared.streamObject<U, V>(U parentObject, String referenceFieldName)
```

#### [streamListField](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_database/CKLocalDatabaseManager/streamListField.html)

This method creates a `Stream<V>` object, which updates when changes occur in the database on a `List<CKReference>` field within a record. It requires the `parentObject` and the reference field name, and can optionally filter results by SQLite `where` and SQLite `orderBy` strings:
```dart
Stream<V> CKLocalDatabaseManager.shared.streamListField<U, V>(U parentObject, String referenceListFieldName, {String? where, List? whereArgs, String? orderBy})
```

### API Operations

On creation, all operations require a string argument for the database (public, shared, private) to be used for the request. Optionally, a specific instance of a [CKAPIManager](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_init/CKAPIManager-class.html) can be passed in, with the shared instance used by default.

#### [CKCurrentUserOperation](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_api/CKCurrentUserOperation-class.html)

This operation fetches the CloudKit ID of the current user. It is also the simplest way to test if the user is signed in to iCloud, which is necessary to access the private database. Hence, the operation can be called at app launch or via a button to initiate the iCloud sign-in prompt.

Besides the default arguments for an operation as described above, this operation does not require any additional arguments.

Returned from the [execute](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_api/CKCurrentUserOperation/execute.html) call is the CloudKit ID of the signed-in user as a string.

#### [CKRecordQueryOperation](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_api/CKRecordQueryOperation-class.html)

This operation is the main method to retrieve records from CloudKit.

When creating the operation, you must pass in a local type to receive and a target database. For example, the following would fetch all `Employee` records from the public database:
```dart
CKRecordQueryOperation<Employee>(CKDatabase.PUBLIC_DATABASE)
```
Optionally, you can pass in a specific `zoneID` ([CKZone](#ckzone)), a list of `filters` ([CKFilter](#ckfilter)), or a list of `sortDescriptors` ([CKSortDescriptor](#cksortdescriptor) to organize the results. You can also pass in a `preloadAssets` bool to indicate whether any [CKAsset](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_model/CKAsset-class.html) fields in fetched records should be preloaded.

Returned from the [execute](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_api/CKRecordQueryOperation/execute.html) call is an array of local objects of the provided type.

\**More operations will be added in later versions*

### API Request Models

In addition to the multiple kinds of operations, CloudKit provides several request parameters within its API, represented in this library by the classes below.

#### [CKFilter](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_api/CKFilter-class.html)

Filters are created through four main values: the name of the CloudKit record field to compare (`fieldName`), the [CKFieldType](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_model/CKFieldType-class.html) of that record field (`fieldType`), the value to be compared against (`fieldValue`), and the [CKComparator](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_api/CKComparator-class.html) object for the desired comparison.

#### [CKSortDescriptor](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_api/CKSortDescriptor-class.html)

Sort descriptors are created through two main values: the name of the CloudKit record field to sort by (`fieldName`) and a boolean to indicate the direction (`ascending`).

#### [CKZone](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_api/CKZone-class.html)

Zone objects are currently only containers for a zone ID string (`zoneName`), and can be used to specify a specific CloudKit zone for an operation. A zone object with an empty zone name will be set to the default zone.

#### [CKQuery](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_api/CKQuery-class.html)

Query objects are containers to store the CloudKit record type (`recordType`), a list of [CKFilter](#ckfilter) (`filterBy`), and a list of [CKSortDescriptor](#cksortdescriptor) (`sortBy`).

#### [CKRecordQueryRequest](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_api/CKRecordQueryRequest-class.html)

Record query request objects represent the information needed to perform a [CKRecordQueryOperation](#ckrecordqueryoperation), including a [CKZone](#ckzone) (`zoneID`), a result limit (`resultsLimit`), and a [CKQuery](#ckquery) object (`query`).

## Library Sections

To reduce the amount of included classes, you can choose to import a single section of the library, as described below.

### [cloudkit_flutter.dart](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter/cloudkit_flutter-library.html)

Includes all exposed classes.

### [cloudkit_flutter_init.dart](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_init/cloudkit_flutter_init-library.html)

Includes classes necessary to initialize the record parser ([CKRecordParser](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_init/CKRecordParser-class.html)), API manager ([CKAPIManager](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_init/CKAPIManager-class.html)), and local database ([CKLocalDatabaseManager](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_init/CKLocalDatabaseManager-class.html)).

### [cloudkit_flutter_model.dart](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_model/cloudkit_flutter_model-library.html)

Includes classes necessary to annotate model files ([CKRecordTypeAnnotation](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_model/CKRecordTypeAnnotation-class.html), [CKRecordNameAnnotation](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_model/CKRecordNameAnnotation-class.html), [CKFieldAnnotation](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_model/CKFieldAnnotation-class.html), [CKReferenceFieldAnnotation](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_model/CKReferenceFieldAnnotation-class.html)), use special field types ([CKReference](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_model/CKReference-class.html), [CKAsset](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_model/CKAsset-class.html)), and create custom field types ([CKCustomFieldType](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_model/CKCustomFieldType-class.html)).

### [cloudkit_flutter_database.dart](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_database/cloudkit_flutter_database-library.html)

Includes classes necessary to access the local SQLite database ([CKLocalDatabaseManager](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_database/CKLocalDatabaseManager-class.html), [CKDatabaseEvent](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_database/CKDatabaseEvent-class.html)).

### [cloudkit_flutter_api.dart](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_api/cloudkit_flutter_api-library.html)

Includes classes necessary to call the CloudKit API ([CKOperation](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_api/CKOperation-class.html) + subclasses, [CKZone](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_api/CKZone-class.html), [CKFilter](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_api/CKFilter-class.html), [CKSortDescriptor](https://pub.dev/documentation/cloudkit_flutter/latest/cloudkit_flutter_api/CKSortDescriptor-class.html)).
