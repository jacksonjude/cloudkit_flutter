import 'dart:developer';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ck_constants.dart';
import 'ck_auth_web_view.dart';
import 'ck_operation.dart';

/// The manager for making calls to the CloudKit API.
class CKAPIManager
{
  late final String _ckContainer;
  late final String _ckAPIToken;
  late final CKEnvironment _environment;
  late final String _redirectURLPattern;

  String? _ckAuthURL;
  String? _ckWebAuthToken;

  static CKAPIManager? _instance;

  /// Get the shared instance of the [CKAPIManager].
  static CKAPIManager shared()
  {
    if (_instance == null) _instance = CKAPIManager();
    return _instance!;
  }

  /// Initialize the shared API manager for the application. Optionally, a custom [CKAPIManager] can be passed in.
  static void initManager(String ckContainer, String ckAPIToken, CKEnvironment environment, {CKAPIManager? manager})
  {
    var managerToInit = manager ?? CKAPIManager.shared();

    managerToInit._ckContainer = ckContainer;
    managerToInit._ckAPIToken = ckAPIToken;
    managerToInit._environment = environment;
    managerToInit._redirectURLPattern = CKConstants.REDIRECT_URL_PATTERN_PREFIX + ckContainer.toLowerCase();

    managerToInit.fetchWebAuthToken();
  }

  /// Call the CloudKit API directly, given the database, api operation path, protocol (GET or POST), and optionally, the JSON body and [BuildContext].
  Future<CKOperationCallback> callAPI(CKDatabase database, String operationPath, CKOperationProtocol operationProtocol, {Map<String,dynamic>? operationBody, BuildContext? context}) async
  {
    if (this._ckAuthURL == null || this._ckWebAuthToken != null)
    {
      var getCurrentUserURIQueryParameters = Map<String,String>();
      getCurrentUserURIQueryParameters[CKConstants.API_TOKEN_PARAMETER] = this._ckAPIToken;
      if (this._ckWebAuthToken != null)
      {
        getCurrentUserURIQueryParameters[CKConstants.WEB_AUTH_TOKEN_PARAMETER] = this._ckWebAuthToken!;
      }

      var originalURI = Uri.parse(CKConstants.API_URL_BASE + "/" + this._ckContainer + "/" + this._environment.toString() + "/" + database.toString() + "/" + operationPath);
      var modifiedURIWithParameters = Uri.https(originalURI.authority, originalURI.path, getCurrentUserURIQueryParameters);

      var response;
      switch (operationProtocol)
      {
        case CKOperationProtocol.get:
          response = await http.get(modifiedURIWithParameters);
          break;
        case CKOperationProtocol.post:
          print(operationBody);
          response = await http.post(modifiedURIWithParameters, body: json.encode(operationBody ?? {}));
          break;
      }

      log(operationBody.toString());
      log(response.statusCode.toString());

      switch (response.statusCode)
      {
        case 200:
          var apiResponse = jsonDecode(response.body);
          return CKOperationCallback(CKOperationState.success, response: apiResponse);

        case 421:
          var authRequiredResponse = jsonDecode(response.body);
          this._ckAuthURL = authRequiredResponse[CKConstants.REDIRECT_URL_PARAMETER];
          break;

        case 401:
          return CKOperationCallback(CKOperationState.authFailure);

        default:
          return CKOperationCallback(CKOperationState.unknownError);
      }
    }

    var authState = await authenticateUser(context);
    switch (authState)
    {
      case CKAuthState.success:
        return await callAPI(database, operationPath, operationProtocol, operationBody: operationBody, context: context);
      case CKAuthState.failure:
      case CKAuthState.cancel:
        return CKOperationCallback(CKOperationState.authFailure);
    }
  }

  /// Open the "Sign-In to iCloud" webpage, if the stored ckAuthURL exists.
  Future<CKAuthState> authenticateUser(BuildContext? context) async
  {
    if (context == null || _ckAuthURL == null) return CKAuthState.failure;

    final CKAuthCallback authCallback = await Navigator.push(context,
      MaterialPageRoute(builder: (context) =>
        CKAuthWebView(
          authenticationURL: _ckAuthURL!,
          redirectURLPattern: _redirectURLPattern
        )
      )
    );

    switch (authCallback.state)
    {
      case CKAuthState.success:
        _ckWebAuthToken = authCallback.authToken;
        await saveWebAuthToken();
        break;
      case CKAuthState.failure:
      case CKAuthState.cancel:
        break;
    }

    print(authCallback.state);

    return authCallback.state;
  }

  /// Save the locally-stored ckWebAuthToken to [SharedPreferences].
  Future<void> saveWebAuthToken([String? ckWebAuthToken]) async
  {
    if (_ckWebAuthToken == null && ckWebAuthToken == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(CKConstants.WEB_AUTH_TOKEN_STORAGE_KEY, ckWebAuthToken ?? _ckWebAuthToken!);
  }

  /// Fetch the ckWebAuthToken from [SharedPreferences] into local storage.
  Future<String?> fetchWebAuthToken() async
  {
    final prefs = await SharedPreferences.getInstance();
    _ckWebAuthToken = prefs.getString(CKConstants.WEB_AUTH_TOKEN_STORAGE_KEY) ?? _ckWebAuthToken;
    return _ckWebAuthToken;
  }
}