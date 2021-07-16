import 'package:cloudkit_flutter/api/request_models/ck_sort_descriptor.dart';
import 'package:cloudkit_flutter/ck_constants.dart';
import 'package:flutter/cupertino.dart';

import 'ck_api_manager.dart';
import 'request_models/ck_record_query_request.dart';
import 'request_models/ck_zone.dart';
import 'request_models/ck_query.dart';
import 'request_models/ck_filter.dart';
import '../parsing/ck_record_parser.dart';

/// The status after an operation has been executed.
enum CKOperationState
{
  success,
  authFailure,
  unknownError
}

/// Contains a [CKOperationState] with the response from an operation.
class CKOperationCallback
{
  final CKOperationState state;
  final dynamic response;

  CKOperationCallback(this.state, {this.response});
}

/// Denotes the protocol type of an operation.
enum CKOperationProtocol
{
  get,
  post
}

/// The base class for an operation
abstract class CKOperation
{
  final CKAPIManager _apiManager;
  final CKDatabase _database;
  final BuildContext? _context; // to launch web view authentication, if needed

  CKOperation(CKDatabase database, {CKAPIManager? apiManager, BuildContext? context}) : _apiManager = apiManager ?? CKAPIManager.shared(), _database = database, _context = context;

  String _getAPIPath();

  /// Execute the operation.
  Future<CKOperationCallback> execute();
}

abstract class CKGetOperation extends CKOperation
{
  CKGetOperation(CKDatabase database, {CKAPIManager? apiManager, BuildContext? context}) : super(database, apiManager: apiManager, context: context);

  /// Execute the GET operation
  @override
  Future<CKOperationCallback> execute() async => await this._apiManager.callAPI(_database, _getAPIPath(), CKOperationProtocol.get, context: _context);
}

abstract class CKPostOperation extends CKOperation
{
  CKPostOperation(CKDatabase database, {CKAPIManager? apiManager, BuildContext? context}) : super(database, apiManager: apiManager, context: context);

  Map<String,dynamic>? _getBody();

  /// Execute the POST operation.
  @override
  Future<CKOperationCallback> execute() async => await this._apiManager.callAPI(_database, _getAPIPath(), CKOperationProtocol.post, operationBody: _getBody(), context: _context);
}

class CKCurrentUserOperation extends CKGetOperation
{
  CKCurrentUserOperation(CKDatabase database, {CKAPIManager? apiManager, BuildContext? context}) : super(database, apiManager: apiManager, context: context);

  @override
  String _getAPIPath() => "users/current";

  /// Execute the current user operation.
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
  late final CKRecordQueryRequest _recordQueryRequest;
  late final bool _shouldPreloadAssets;

  CKRecordQueryOperation(CKDatabase database, {CKRecordQueryRequest? queryRequest, CKZone? zoneID, int? resultsLimit, List<CKFilter>? filters, List<CKSortDescriptor>? sortDescriptors, bool? preloadAssets, CKAPIManager? apiManager, BuildContext? context}) : super(database, apiManager: apiManager, context: context)
  {
    var recordStructure = CKRecordParser.getRecordStructureFromLocalType(T);
    this._recordQueryRequest = queryRequest ?? CKRecordQueryRequest(zoneID ?? CKZone(), resultsLimit, CKQuery(recordStructure.ckRecordType, filterBy: filters, sortBy: sortDescriptors));
    this._shouldPreloadAssets = preloadAssets ?? false;
  }

  @override
  String _getAPIPath() => "records/query";

  @override
  Map<String,dynamic>? _getBody() => _recordQueryRequest.toJSON();

  /// Execute the record query operation.
  @override
  Future<CKOperationCallback> execute() async
  {
    CKOperationCallback apiCallback = await super.execute();

    List<T> newLocalObjects = [];
    if (apiCallback.state == CKOperationState.success)
    {
      await Future.forEach(apiCallback.response["records"], (recordMap) async {
        var newObject = CKRecordParser.recordToLocalObject<T>(recordMap as Map<String,dynamic>, database: _database);

        if (_shouldPreloadAssets) await CKRecordParser.preloadAssets<T>(newObject);

        newLocalObjects.add(newObject);
      });
    }

    return CKOperationCallback(apiCallback.state, response: newLocalObjects);
  }
}