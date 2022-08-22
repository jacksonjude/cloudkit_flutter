import 'package:tuple/tuple.dart';
import 'package:quiver/iterables.dart';

import 'ck_api_manager.dart';
import 'request_models/ck_record_query_request.dart';
import 'request_models/ck_record_zone_changes_request.dart';
import 'request_models/ck_zone.dart';
import 'request_models/ck_query.dart';
import 'request_models/ck_filter.dart';
import 'request_models/ck_sort_descriptor.dart';
import 'request_models/ck_sync_token.dart';
import 'request_models/ck_record_modify_request.dart';
import '/src/parsing/ck_record_parser.dart';
import '/src/ck_constants.dart';

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
  final CKSyncToken? syncToken;
  final List<Tuple2<T,CKRecordChangeType>> recordChanges;

  // CKChangesOperationCallback(CKOperationState state, this.changedRecords, this.syncToken) : super(state, response: changedRecords);
  CKChangesOperationCallback.withOperationCallback(CKOperationCallback<List<T>> operationCallback, List<CKRecordChangeType>? changeTypes, this.syncToken) :
      recordChanges = zip([operationCallback.response ?? [], changeTypes ?? []]).map((recordChangePair) => Tuple2<T,CKRecordChangeType>.fromList(recordChangePair)).toList(),
      super(operationCallback.state, response: operationCallback.response);
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
  final CKAPIModule _apiModule;
  final CKDatabase? _database;

  CKOperation(this._apiModule, {CKDatabase? database, CKAPIManager? apiManager}) : _apiManager = apiManager ?? CKAPIManager.shared, _database = database;

  String _getAPIPath();

  /// Execute the operation.
  Future<CKOperationCallback> execute();
}

/// The base class for a GET operation.
abstract class CKGetOperation extends CKOperation
{
  CKGetOperation(CKAPIModule apiModule, {CKDatabase? database, CKAPIManager? apiManager}) : super(apiModule, database: database, apiManager: apiManager);

  /// Execute the GET operation.
  @override
  Future<CKOperationCallback> execute() async => await this._apiManager.callAPI(_apiModule, _getAPIPath(), CKOperationProtocol.get, database: _database);
}

/// The base class for a POST operation.
abstract class CKPostOperation extends CKOperation
{
  CKPostOperation(CKAPIModule apiModule, {CKDatabase? database, CKAPIManager? apiManager}) : super(apiModule, database: database, apiManager: apiManager);

  Map<String,dynamic>? _getBody();

  /// Execute the POST operation.
  @override
  Future<CKOperationCallback> execute() async => await this._apiManager.callAPI(_apiModule, _getAPIPath(), CKOperationProtocol.post, database: _database, operationBody: _getBody());
}

/// An operation to fetch the current user ID.
class CKCurrentUserOperation extends CKGetOperation
{
  CKCurrentUserOperation(CKDatabase database, {CKAPIManager? apiManager}) : super(CKAPIModule.DATABASE, database: database, apiManager: apiManager);

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

  CKRecordQueryOperation(CKDatabase database, {CKRecordQueryRequest? queryRequest, CKZone? zoneID, int? resultsLimit, List<CKFilter>? filters, List<CKSortDescriptor>? sortDescriptors, bool? preloadAssets, CKAPIManager? apiManager}) : super(CKAPIModule.DATABASE, database: database, apiManager: apiManager)
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

      for (var recordMap in recordsList)
      {
        var newObject = CKRecordParser.recordToLocalObject<T>(recordMap as Map<String,dynamic>, _database!);
        if (_shouldPreloadAssets) await CKRecordParser.preloadAssets<T>(newObject);
        newLocalObjects.add(newObject);
      }
    }

    return CKOperationCallback<List<T>>(apiCallback.state, response: newLocalObjects);
  }
}

enum CKRecordChangeType
{
  update,
  delete
}

/// An operation to fetch record zone changes.
class CKRecordZoneChangesOperation<T> extends CKRecordQueryOperation<T>
{
  final CKRecordZoneChangesRequest _recordZoneChangesRequest;
  CKSyncToken? _currentSyncToken;
  List<CKRecordChangeType>? _changeTypes;

  CKRecordZoneChangesOperation(CKZone zoneID, CKDatabase database, {CKRecordZoneChangesRequest? zoneChangesRequest, CKSyncToken? syncToken, int? resultsLimit, List<String>? recordFields, bool? preloadAssets, CKAPIManager? apiManager}) :
    this._recordZoneChangesRequest = zoneChangesRequest ?? CKRecordZoneChangesRequest<T>(zoneID, syncToken, resultsLimit, recordFields),
    this._currentSyncToken = syncToken,
    super(database, zoneID: zoneID, resultsLimit: resultsLimit, preloadAssets: preloadAssets, apiManager: apiManager);

  @override
  String _getAPIPath() => "changes/zone";

  @override
  Map<String,dynamic>? _getBody() => {
    "zones": [
      _recordZoneChangesRequest.toJSON()
    ]
  };

  @override
  List<dynamic> _handleResponse(dynamic response) // TODO: Error handling
  {
    if (response["zones"].length <= 0) return [];

    var zoneChangesResponse = response["zones"][0];
    _currentSyncToken = CKSyncToken(zoneChangesResponse["syncToken"]);

    List records = zoneChangesResponse["records"];
    _changeTypes = records.map((recordJSON) => !(recordJSON["deleted"] as bool) ? CKRecordChangeType.update : CKRecordChangeType.delete).toList();

    return records;
  }

  /// Execute the record zone changes.
  @override
  Future<CKChangesOperationCallback<T>> execute() async
  {
    CKOperationCallback<List<T>> recordChangesCallback = await super.execute();
    return CKChangesOperationCallback<T>.withOperationCallback(recordChangesCallback, _changeTypes, _currentSyncToken);
  }
}

/// An operation to modify records
class CKRecordModifyOperation<T extends Object> extends CKPostOperation
{
  late final CKRecordModifyRequest _recordModifyRequest;

  CKRecordModifyOperation(CKDatabase database, {CKRecordModifyRequest? modifyRequest, List<Tuple2<T,CKRecordOperationType>>? objectsToModify, CKZone? zoneID, bool? atomic, List<String>? recordFields, bool? numbersAsStrings, CKAPIManager? apiManager}) : super(CKAPIModule.DATABASE, database: database, apiManager: apiManager)
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