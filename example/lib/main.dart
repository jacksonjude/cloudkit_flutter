import 'package:flutter/material.dart';
import 'dart:developer';

import 'package:cloudkit_flutter/cloudkit_flutter_init.dart';
import 'package:cloudkit_flutter/cloudkit_flutter_api.dart';

import 'model/employee.dart';

import 'main.reflectable.dart'; // Import generated code.
// Run `flutter pub run build_runner build example` from the root directory to generate example.reflectable.dart code

void main() async
{
  await initializeCloudKit();
  runApp(CKTestApp());
}

// To run this example code, you must have a CloudKit container with the following structure (as can be inferred from model/employee.dart):
// Employee: {
//   name: String
//   nicknames: List<String>
//   genderRaw: int
//   profileImage: CKAsset
// }
//
// Once the container is created, enter the CloudKit container and API token (set up via the CloudKit dashboard & with the options specified in README.md) below:

Future<void> initializeCloudKit() async
{
  const String ckContainer = ""; // YOUR CloudKit CONTAINER NAME HERE
  const String ckAPIToken = ""; // YOUR CloudKit API TOKEN HERE
  const CKEnvironment ckEnvironment = CKEnvironment.DEVELOPMENT_ENVIRONMENT;

  initializeReflectable();

  CKRecordParser.createRecordStructures([
    Employee
  ]);

  await CKAPIManager.initManager(ckContainer, ckAPIToken, ckEnvironment);
}

class CKTestApp extends StatelessWidget
{
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context)
  {
    return MaterialApp(
      title: 'iCloud Test',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: CKTestPage(title: "iCloud Test"),
    );
  }
}

class CKTestPage extends StatefulWidget
{
  CKTestPage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  _CKTestPageState createState() => _CKTestPageState();
}

class _CKTestPageState extends State<CKTestPage>
{
  CKSignInState isSignedIn = CKSignInState.NOT_SIGNED_IN;
  String currentUserOutput = "Get current user ID (and check if signed in)";
  String employeeOutput = "Fetch employee";

  void getCurrentUserCallback(CKSignInState isSignedIn, String currentUserOutput)
  {
    setState(() {
      this.isSignedIn = isSignedIn;
      this.currentUserOutput = currentUserOutput;
    });
  }

  void getEmployeeCallback(String employeeOutput)
  {
    setState(() {
      this.employeeOutput = employeeOutput;
    });
  }

  @override
  Widget build(BuildContext context)
  {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          children: [
            Text(currentUserOutput),
            CKSignInButton(isSignedIn: isSignedIn, callback: getCurrentUserCallback),
            Padding(padding: EdgeInsets.all(8.0)),
            Text(employeeOutput),
            FetchEmployeeTestButton(isSignedIn: isSignedIn, callback: getEmployeeCallback),
          ],
          mainAxisAlignment: MainAxisAlignment.center,
        ),
      ),
    );
  }
}

class CKSignInButton extends StatefulWidget
{
  final Function(CKSignInState, String) callback;
  final CKSignInState isSignedIn;

  CKSignInButton({Key? key, required this.isSignedIn, required this.callback}) : super(key: key);

  @override
  State<StatefulWidget> createState() => CKSignInButtonState();
}

enum CKSignInState
{
  NOT_SIGNED_IN,
  SIGNING_IN,
  RE_SIGNING_IN,
  IS_SIGNED_IN
}

class CKSignInButtonState extends State<CKSignInButton>
{
  IconData getIconForCurrentState()
  {
    switch (widget.isSignedIn)
    {
      case CKSignInState.NOT_SIGNED_IN:
        return Icons.check_box_outline_blank;
      case CKSignInState.SIGNING_IN:
        return Icons.indeterminate_check_box_outlined;
      case CKSignInState.RE_SIGNING_IN:
        return Icons.indeterminate_check_box;
      case CKSignInState.IS_SIGNED_IN:
        return Icons.check_box;
    }
  }

  @override
  Widget build(BuildContext context)
  {
    return ElevatedButton(
        onPressed: () async {
          if (widget.isSignedIn == CKSignInState.IS_SIGNED_IN)
          {
            widget.callback(CKSignInState.RE_SIGNING_IN, "Re-signing in...");
          }
          else
          {
            widget.callback(CKSignInState.SIGNING_IN, "Signing in...");
          }

          var getCurrentUserOperation = CKCurrentUserOperation(CKDatabase.PUBLIC_DATABASE, context: context);
          var operationCallback = await getCurrentUserOperation.execute();

          switch (operationCallback.state)
          {
            case CKOperationState.success:
              var currentUserID = operationCallback.response as String;
              widget.callback(CKSignInState.IS_SIGNED_IN, currentUserID);
              break;

            case CKOperationState.authFailure:
              widget.callback(CKSignInState.NOT_SIGNED_IN, "Authentication failure");
              break;

            case CKOperationState.unknownError:
              widget.callback(CKSignInState.NOT_SIGNED_IN, "Unknown error");
              break;
          }
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Sign In with iCloud"),
            Padding(padding: EdgeInsets.all(4.0)),
            Icon(getIconForCurrentState())
          ],
        )
    );
  }
}

class FetchEmployeeTestButton extends StatefulWidget
{
  final Function(String) callback;
  final CKSignInState isSignedIn;

  FetchEmployeeTestButton({Key? key, required this.isSignedIn, required this.callback}) : super(key: key);

  @override
  State<StatefulWidget> createState() => FetchEmployeeTestButtonState();
}

class FetchEmployeeTestButtonState extends State<FetchEmployeeTestButton>
{
  @override
  Widget build(BuildContext context)
  {
    return ElevatedButton(
        onPressed: () async {
          if (widget.isSignedIn != CKSignInState.IS_SIGNED_IN)
          {
            widget.callback("Catch: Not signed in");
            return;
          }

          var queryOperation = CKRecordQueryOperation<Employee>(CKDatabase.PRIVATE_DATABASE, preloadAssets: true, context: context);
          CKOperationCallback queryCallback = await queryOperation.execute();

          List<Employee> employees = [];
          if (queryCallback.state == CKOperationState.success) employees = queryCallback.response;

          switch (queryCallback.state)
          {
            case CKOperationState.success:
              if (employees.length > 0)
              {
                testEmployee(employees[0]);
                widget.callback("Success");
              }
              else
              {
                widget.callback("No Employee records");
              }
              break;

            case CKOperationState.authFailure:
              widget.callback("Authentication failure");
              break;

            case CKOperationState.unknownError:
              widget.callback("Unknown error");
              break;
          }
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Fetch Employees"),
          ],
        )
    );
  }
}

void testEmployee(Employee testEmployee) async
{
  log(testEmployee.toString());

  // These are the nicknames for the employee, automatically converted from CloudKit to the local object
  var nicknames = testEmployee.nicknames ?? [];
  log(nicknames.toString());

  // This is the data for a profile image, which can be casted (via .getAsImage()) due to `preloadAssets: true` when the operation was called
  var _ = (testEmployee.profileImage?.getAsImage() ?? AssetImage("assets/generic-user.png")) as ImageProvider;
  // If `preloadAssets: false`, the asset would have to be downloaded directly:
  await testEmployee.profileImage?.fetchAsset();
  log(testEmployee.profileImage?.size.toString() ?? 0.toString());

  // This is a custom `Gender` object, converted from a raw int form in CloudKit
  var gender = testEmployee.gender ?? Gender.unknown;
  log(gender.toString());
}