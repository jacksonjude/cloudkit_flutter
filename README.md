# cloudkit_flutter

CloudKit support for Flutter via [CloudKit Web Services](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference).

## Support

This library currently only supports Android (and iOS, although its usefulness there is fairly limited). The lack of Flutter Web support is due to one of the dependencies, [webview_flutter](https://pub.dev/packages/webview_flutter/score "webview_flutter"), not supporting the Flutter Web platform 🙄.

## Setup

Within your app, there are two stages involved in setting up this library. First, you must initialize the API manager with your CloudKit container, environment, and API token. Second, you must create your model classes based on the record types in CloudKit.

### API Initilization

Before calls to the CloudKit API can be made, three values must be provided to the `CKAPIManager`:
- CloudKit Container: The container ID used by CloudKit, which is typically `iCloud.` + your bundle ID.
- CloudKit API Token: A token which must be created via the CloudKit dashboard. **Importantly, you must select the last option within 'URL Redirect' for the 'Sign in Callback'. The custom URL can be any short string, such as 'redirect'.**
- CloudKit Environment: Changes whether the production or development environment is used. Corresponding strings are provided in the `CKEnvironment` class.

To initilize the manager, these three values must be passed into `CKAPIManager.initManager(String container, String apiToken, String environment)`. This call should preferably be done in conjunction with the reflection setup initilization, as described below.

### Model Classes - Annotation

In this library, model classes must be annotated and then scanned so that reflection can be used to seamlessly convert JSON CloudKit records to a local Dart object.

There are three main types of annotations used in model files:

- `@CKRecordTypeAnnotation`: to denote the name of the record type on CloudKit, and placed before the class declaration
- `@CKRecordNameAnnotation`: to label the field within the local class where the CloudKit record name (a UUID) is stored
- `@CKFieldAnnotation`: to associate fields in the local Dart object with record fields in CloudKit

Additionally, for the class to be scanned via reflection, you must tag the class with `@reflector` before the class declaration.

Below is an example of these annotations being used in a Dart file:

```dart
import 'package:cloudkit_flutter/cloudkit_flutter_model.dart';

@reflector
@CKRecordTypeAnnotation("Schedule")  // The name of the CloudKit record type is included in the annotation
class Schedule
{
	@CKRecordNameAnnotation() // No CloudKit record field name is needed as the field is always 'recordName'
	String? uuid;

	@CKFieldAnnotation("scheduleCode") // The name of the CloudKit record field is included in the annotation
	String? code;

	@CKFieldAnnotation("periodTimes")
	List<String>? blockTimes;

	@CKFieldAnnotation("periodNumbers")
	List<int>? blockNumbers;
}
```

### Model Classes - Supported Field Types

Currently, most of the field types supported in CloudKit can be used in local model classes.

Many are fairly basic:
- `String`
- `int`
- `double`
- `DateTime`
- `List<String>`
- `List<int>`

There are a couple that require some explaination:
- `CKReference` / `List<CKReference>`
The reference field type in CloudKit is used to create relations between two record types. The `CKReference` class has been created to represent this relation. To fetch the object associated with the reference, simply call the `fetchFromCloud<T>()` function, providing the corresponding local type (in place of `T`) when doing so.
- `CKAsset`
The asset field type in CloudKit allows for the storage of literal bytes of data as a discrete asset. One common use for this type is to store an image. The `CKAsset` class has been created to represent this type, and it likewise has a `fetchAsset()` function to retrieve and cache the stored bytes. It also includes a `getAsImage()` function to convert the cached bytes to an image, if possible.
- Subclasses of `CKCustomFieldType`
See below.

\**More base field types will be added in later versions*

### Model Classes - Custom Field Types

Sometimes, a field within a CloudKit database only stores a raw value, to be later converted into an enum or more fully defined class when it reaches an app. To allow for custom classes to be used as types within model classes, the `CKCustomFieldType` class has been created.

There are several requirements for a subclass of `CKCustomFieldType`:
- The class itself must provide a raw value type within the class declaration
- There must be a default constructor which calls `super.fromRecordField(T rawValue)`
- There must be a `fromRecordField(T rawValue)` constructor
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

### Model Classes - Reflection Setup

**Whenever you make changes to your model classes or `CKCustomFieldType` subclasses**, you must regenerate object code to allow for reflection to be used within the library. To do this simply run `flutter pub run build_runner build lib` from the root folder of your Flutter project.

Finally, you must indicate to the `CKRecordParser` class which model classes should be scanned. Do this via the `CKRecordParser.createRecordStructures(List<Type>)` function, listing the names of the local model classes. To scan the Schedule class for example, we would call `CKRecordParser.createRecordStructures([Schedule])`. This call should preferably be done in conjunction with the API Initilization, as described above.

## Usage

The main way to access the CloudKit API is through `CKOperation`, which is run though the `execute()` function. There are multiple kinds of operations, which are described below. \**More operations will be added in later versions*

On creation, all operations require a string argument for the database (public, shared, private) to be used for the request. Optionally, a specific instance of a `CKAPIManager` can be passed in, although the shared instance is used by default. Additionally, a `BuildContext` can be optionally passed into the operation, in the offchance that an iCloud sign-in view is necessary.

### CKCurrentUserOperation

This operation fetches the CloudKit ID of the current user. It is also the simplest way to test if the user is signed in to iCloud, which is necessary to access the private database. Hence, the operation can be called at app launch or via a button to initiate the iCloud sign-in prompt.

Besides the default arguments for an operation as described above, this operation does not require any additional arguments.

Returned from the `execute()` call is the CloudKit ID of the signed-in user as a string.

### CKRecordQueryOperation

This operation is the main method to retrieve records from CloudKit.

When creating the operation, you must pass in a local type for the operation to recieve. For example: `CKRecordQueryOperation<Schedule>(CKDatabase.PUBLIC_DATABASE)` would fetch all `Schedule` records from the public database. Optionally, you can pass in a specific `CKZone` (`zoneID`) or a `List<CKFilter>` (`filters`) to filter the results. You can also pass in a bool (`preloadAssets`) to denote whether or not to preload any `CKAsset` fields in fetched records.

Returned from the `execute()` call is an array of local objects with the type provided to the operation.

## Import points

To reduce the amount of included classes, you can choose to import a single section of the library, as described below.

### cloudkit_flutter.dart

Includes all exposed classes.

### cloudkit_flutter_init.dart

Includes classes necessary to initialize the API manager (CKAPIManager) and record parser (CKRecordParser).

### cloudkit_flutter_model.dart

Includes classes necessary to annotate model files (CKRecordTypeAnnotation, CKRecordNameAnnotation, CKFieldAnnotation), use special field types (CKReference, CKAsset), and create custom field types (CKCustomFieldType).

### cloudkit_flutter_api.dart

Includes classes necessary to call the CloudKit API (CKOperation + subclasses, CKZone, CKFilter).
