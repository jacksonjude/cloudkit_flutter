import 'package:flutter/material.dart';
import 'package:tuple/tuple.dart';

import 'ck_api_manager.dart';
import 'request_models/ck_record_query_request.dart';
import 'request_models/ck_record_zone_changes_request.dart';
import 'request_models/ck_zone.dart';
import 'request_models/ck_query.dart';
import 'request_models/ck_filter.dart';
import 'request_models/ck_sort_descriptor.dart';
import 'request_models/ck_sync_token.dart';
import 'request_models/ck_record_modify_request.dart';
import '../parsing/ck_record_parser.dart';
import '../ck_constants.dart';

/// The status after an operation has been executed.
enum CKOperationState
{
  success,
  authFailure,
  unknownError
}

/// Contains a [CKOperationState] with the response from an operation.
class CKOperationCallback<T>
{
  final CKOperationState state;
  final T? response;

  CKOperationCallback(this.state, {this.response});
}

/// Contains a [CKSyncToken], a [CKOperationState], and the changed records from a fetch changes operation.
class CKChangesOperationCallback<T> extends CKOperationCallback<List<T>>
{
  final List<T> changedRecords;
  final CKSyncToken? syncToken;

  CKChangesOperationCallback(CKOperationState state, this.changedRecords, this.syncToken) : super(state, response: changedRecords);
  CKChangesOperationCallback.withOperationCallback(CKOperationCallback operationCallback, this.syncToken) : changedRecords = operationCallback.response ?? [], super(operationCallback.state, response: operationCallback.response);
}

/// Denotes the protocol type of an operation.
enum CKOperationProtocol
{
  get,
  post
}

/// The base class for an operation.
abstract class CKOperation
{
  final CKAPIManager _apiManager;
  final CKDatabase _database;
  final BuildContext? _context; // to launch web view authentication, if needed

  CKOperation(CKDatabase database, {CKAPIManager? apiManager, BuildContext? context}) : _apiManager = apiManager ?? CKAPIManager.shared, _database = database, _context = context;

  String _getAPIPath();

  /// Execute the operation.
  Future<CKOperationCallback> execute();
}

/// The base class for a GET operation.
abstract class CKGetOperation extends CKOperation
{
  CKGetOperation(CKDatabase database, {CKAPIManager? apiManager, BuildContext? context}) : super(database, apiManager: apiManager, context: context);

  /// Execute the GET operation.
  @override
  Future<CKOperationCallback> execute() async => await this._apiManager.callAPI(_database, _getAPIPath(), CKOperationProtocol.get, context: _context);
}

/// The base class for a POST operation.
abstract class CKPostOperation extends CKOperation
{
  CKPostOperation(CKDatabase database, {CKAPIManager? apiManager, BuildContext? context}) : super(database, apiManager: apiManager, context: context);

  Map<String,dynamic>? _getBody();

  /// Execute the POST operation.
  @override
  Future<CKOperationCallback> execute() async => await this._apiManager.callAPI(_database, _getAPIPath(), CKOperationProtocol.post, operationBody: _getBody(), context: _context);
}

/// An operation to fetch the current user ID.
class CKCurrentUserOperation extends CKGetOperation
{
  CKCurrentUserOperation(CKDatabase database, {CKAPIManager? apiManager, BuildContext? context}) : super(database, apiManager: apiManager, context: context);

  @override
  String _getAPIPath() => "users/current";

  /// Execute the current user operation.
  @override
  Future<CKOperationCallback<String>> execute() async
  {
    CKOperationCallback apiCallback = await super.execute();
    String? userString;
    if (apiCallback.state == CKOperationState.success) userString = apiCallback.response["userRecordName"];

    return CKOperationCallback<String>(apiCallback.state, response: userString);
  }
}

/// An operation to fetch records.
class CKRecordQueryOperation<T> extends CKPostOperation
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

  List<dynamic> _handleResponse(dynamic response) => response["records"];

  /// Execute the record query operation.
  @override
  Future<CKOperationCallback<List<T>>> execute() async
  {
    CKOperationCallback apiCallback = await super.execute();

    List<T> newLocalObjects = [];
    if (apiCallback.state == CKOperationState.success)
    {
      var recordsList = _handleResponse(apiCallback.response);

      await Future.forEach(recordsList, (recordMap) async {
        var newObject = CKRecordParser.recordToLocalObject<T>(recordMap as Map<String,dynamic>, _database);

        if (_shouldPreloadAssets) await CKRecordParser.preloadAssets<T>(newObject);

        newLocalObjects.add(newObject);
      });
    }

    return CKOperationCallback<List<T>>(apiCallback.state, response: newLocalObjects);
  }
}

/// An operation to fetch record zone changes.
class CKRecordZoneChangesOperation<T> extends CKRecordQueryOperation<T>
{
  final CKRecordZoneChangesRequest _recordZoneChangesRequest;
  CKSyncToken? _currentSyncToken;

  CKRecordZoneChangesOperation(CKZone zoneID, CKDatabase database, {CKRecordZoneChangesRequest? zoneChangesRequest, CKSyncToken? syncToken, int? resultsLimit, List<String>? recordFields, bool? preloadAssets, CKAPIManager? apiManager, BuildContext? context}) :
    this._recordZoneChangesRequest = zoneChangesRequest ?? CKRecordZoneChangesRequest<T>(zoneID, syncToken, resultsLimit, recordFields),
    this._currentSyncToken = syncToken,
    super(database, zoneID: zoneID, resultsLimit: resultsLimit, preloadAssets: preloadAssets, apiManager: apiManager, context: context);

  @override
  String _getAPIPath() => "changes/zone";

  @override
  Map<String,dynamic>? _getBody() => {
    "zones": [
      _recordZoneChangesRequest.toJSON()
    ]
  };

  @override
  List<dynamic> _handleResponse(dynamic response)
  {
    if (response["zones"].length <= 0) return [];

    var zoneChangesResponse = response["zones"][0];
    _currentSyncToken = CKSyncToken(zoneChangesResponse["syncToken"]);
    return zoneChangesResponse["records"];
  }

  /// Execute the record zone changes.
  @override
  Future<CKChangesOperationCallback<T>> execute() async
  {
    CKOperationCallback<List<T>> recordChangesCallback = await super.execute();

    return CKChangesOperationCallback<T>.withOperationCallback(recordChangesCallback, _currentSyncToken);
  }
}

/// An operation to modify records
class CKRecordModifyOperation<T extends Object> extends CKPostOperation
{
  late final CKRecordModifyRequest _recordModifyRequest;

  CKRecordModifyOperation(CKDatabase database, {CKRecordModifyRequest? modifyRequest, List<Tuple2<T,CKRecordOperationType>>? objectsToModify, CKZone? zoneID, bool? atomic, List<String>? recordFields, bool? numbersAsStrings, CKAPIManager? apiManager, BuildContext? context}) : super(database, apiManager: apiManager, context: context)
  {
    this._recordModifyRequest = modifyRequest ?? CKRecordModifyRequest((objectsToModify ?? []).map((objectOperationPair) {
      var object = objectOperationPair.item1;
      var operationType = objectOperationPair.item2;

      var recordJSON = CKRecordParser.localObjectToRecord<T>(object);
      return CKRecordOperation(operationType, recordJSON, null);
    }).toList(), zoneID ?? CKZone(), atomic, recordFields, numbersAsStrings);
  }

  @override
  String _getAPIPath() => "records/modify";

  @override
  Map<String,dynamic>? _getBody() => _recordModifyRequest.toJSON();

  @override
  Future<CKOperationCallback> execute() async
  {
    CKOperationCallback recordModifyCallback = await super.execute();
    return recordModifyCallback;
  }
}