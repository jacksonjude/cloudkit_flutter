import 'package:flutter/cupertino.dart';

import 'ck_api_manager.dart';
import 'request_models/ck_record_query_request.dart';
import 'request_models/ck_zone.dart';
import 'request_models/ck_query.dart';
import 'request_models/ck_filter.dart';
import '../parsing/ck_record_parser.dart';

enum CKOperationState
{
  success,
  authFailure,
  unknownError
}

class CKOperationCallback
{
  final CKOperationState state;
  final dynamic response;

  CKOperationCallback(this.state, {this.response});
}

enum CKOperationProtocol
{
  get,
  post
}

abstract class CKOperation
{
  final CKAPIManager apiManager;
  final String database;
  final BuildContext? context; // to launch web view authentication, if needed

  CKOperation(String database, {CKAPIManager? apiManager, BuildContext? context}) : apiManager = apiManager ?? CKAPIManager.shared(), database = database, context = context;

  String getAPIPath();
  CKOperationProtocol getAPIProtocol();

  Future<CKOperationCallback> execute();
}

abstract class CKGetOperation extends CKOperation
{
  CKGetOperation(String database, {CKAPIManager? apiManager, BuildContext? context}) : super(database, apiManager: apiManager, context: context);

  CKOperationProtocol getAPIProtocol() => CKOperationProtocol.get;

  @override
  Future<CKOperationCallback> execute() async => await this.apiManager.callAPI(database, getAPIPath(), getAPIProtocol(), context: context);
}

abstract class CKPostOperation extends CKOperation
{
  CKPostOperation(String database, {CKAPIManager? apiManager, BuildContext? context}) : super(database, apiManager: apiManager, context: context);

  Map<String,dynamic>? getBody();
  CKOperationProtocol getAPIProtocol() => CKOperationProtocol.post;

  @override
  Future<CKOperationCallback> execute() async => await this.apiManager.callAPI(database, getAPIPath(), getAPIProtocol(), operationBody: getBody(), context: context);
}

class CKCurrentUserOperation extends CKGetOperation
{
  CKCurrentUserOperation(String database, {CKAPIManager? apiManager, BuildContext? context}) : super(database, apiManager: apiManager, context: context);

  @override
  String getAPIPath() => "users/current";

  @override
  Future<CKOperationCallback> execute() async
  {
    CKOperationCallback apiCallback = await super.execute();
    String? userString;
    if (apiCallback.state == CKOperationState.success) userString = apiCallback.response["userRecordName"];

    return CKOperationCallback(apiCallback.state, response: userString);
  }
}

class CKRecordQueryOperation<T extends Object> extends CKPostOperation
{
  late final CKRecordQueryRequest recordQueryRequest;
  late final bool shouldPreloadAssets;

  CKRecordQueryOperation(String database, {CKRecordQueryRequest? queryRequest, CKZone? zoneID, List<CKFilter>? filters, bool? preloadAssets, CKAPIManager? apiManager, BuildContext? context}) : super(database, apiManager: apiManager, context: context)
  {
    var recordStructure = CKRecordParser.getRecordStructureFromLocalType(T);
    this.recordQueryRequest = queryRequest ?? CKRecordQueryRequest(zoneID ?? CKZone(), null, CKQuery(recordStructure.ckRecordType, filterBy: filters));
    this.shouldPreloadAssets = preloadAssets ?? false;
  }

  @override
  String getAPIPath() => "records/query";

  @override
  Map<String,dynamic>? getBody() => recordQueryRequest.toJSON();

  @override
  Future<CKOperationCallback> execute() async
  {
    CKOperationCallback apiCallback = await super.execute();

    List<T> newLocalObjects = [];
    if (apiCallback.state == CKOperationState.success)
    {
      await Future.forEach(apiCallback.response["records"], (recordMap) async {
        var newObject = CKRecordParser.recordToLocalObject<T>(recordMap as Map<String,dynamic>, database: database);

        if (shouldPreloadAssets) await CKRecordParser.preloadAssets<T>(newObject);

        newLocalObjects.add(newObject);
      });
    }

    return CKOperationCallback(apiCallback.state, response: newLocalObjects);
  }
}