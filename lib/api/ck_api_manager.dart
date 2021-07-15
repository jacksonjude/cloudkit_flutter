import 'dart:developer';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ck_constants.dart';
import 'ck_auth_web_view.dart';
import 'ck_operation.dart';

class CKAPIManager
{
  late final String ckContainer;
  late final String ckAPIToken;
  late final String environment;
  late final String redirectURLPattern;

  String? ckAuthURL;
  String? ckWebAuthToken;

  static CKAPIManager? _instance;

  static CKAPIManager shared()
  {
    if (_instance == null) _instance = CKAPIManager();
    return _instance!;
  }

  static void initManager(String ckContainer, String ckAPIToken, String environment, {CKAPIManager? manager})
  {
    var managerToInit = manager ?? CKAPIManager.shared();

    managerToInit.ckContainer = ckContainer;
    managerToInit.ckAPIToken = ckAPIToken;
    managerToInit.environment = environment;
    managerToInit.redirectURLPattern = CKConstants.REDIRECT_URL_PATTERN_PREFIX + ckContainer.toLowerCase();

    managerToInit.fetchWebAuthToken();
  }

  Future<CKOperationCallback> callAPI(String database, String operationPath, CKOperationProtocol operationProtocol, {Map<String,dynamic>? operationBody, BuildContext? context}) async
  {
    if (this.ckAuthURL == null || this.ckWebAuthToken != null)
    {
      var getCurrentUserURIQueryParameters = Map<String,String>();
      getCurrentUserURIQueryParameters[CKConstants.API_TOKEN_PARAMETER] = this.ckAPIToken;
      if (this.ckWebAuthToken != null)
      {
        getCurrentUserURIQueryParameters[CKConstants.WEB_AUTH_TOKEN_PARAMETER] = this.ckWebAuthToken!;
      }

      var originalURI = Uri.parse(CKConstants.API_URL_BASE + "/" + this.ckContainer + "/" + this.environment + "/" + database + "/" + operationPath);
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
          this.ckAuthURL = authRequiredResponse[CKConstants.REDIRECT_URL_PARAMETER];
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

  Future<CKAuthState> authenticateUser(BuildContext? context) async
  {
    if (context == null) return CKAuthState.failure;

    final CKAuthCallback authCallback = await Navigator.push(context,
      MaterialPageRoute(builder: (context) =>
        CKAuthWebView(
          authenticationURL: ckAuthURL!,
          redirectURLPattern: redirectURLPattern
        )
      )
    );

    switch (authCallback.state)
    {
      case CKAuthState.success:
        ckWebAuthToken = authCallback.authToken;
        await saveWebAuthToken();
        break;
      case CKAuthState.failure:
      case CKAuthState.cancel:
        break;
    }

    print(authCallback.state);

    return authCallback.state;
  }

  Future<void> saveWebAuthToken() async
  {
    if (ckWebAuthToken == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(CKConstants.WEB_AUTH_TOKEN_STORAGE_KEY, ckWebAuthToken!);
  }

  Future<void> fetchWebAuthToken() async
  {
    final prefs = await SharedPreferences.getInstance();
    ckWebAuthToken = prefs.getString(CKConstants.WEB_AUTH_TOKEN_STORAGE_KEY) ?? ckWebAuthToken;
  }
}