import 'package:cloudkit_flutter/src/api/request_models/ck_zone_operation.dart';
import 'package:tuple/tuple.dart';
import 'package:quiver/iterables.dart';

import '/src/parsing/ck_record_structure.dart';
import 'ck_api_manager.dart';
import 'ck_notification_manager.dart';
import 'ck_subscription.dart';
import 'request_models/ck_record_query_request.dart';
import 'request_models/ck_record_zone_changes_request.dart';
import 'request_models/ck_zone.dart';
import 'request_models/ck_query.dart';
import 'request_models/ck_filter.dart';
import 'request_models/ck_sort_descriptor.dart';
import 'request_models/ck_sync_token.dart';
import 'request_models/ck_record_modify_request.dart';
import 'request_models/ck_subscription_operation.dart';
import 'request_models/ck_record_change.dart';
import '/src/parsing/ck_record_parser.dart';
import '/src/parsing/types/ck_field_type.dart';
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
class CKChangesOperationCallback<T> extends CKOperationCallback<List<T?>>
{
  final CKSyncToken? syncToken;
  final List<CKRecordChange<T>> recordChanges;

  CKChangesOperationCallback(CKOperationState state, this.recordChanges, this.syncToken) :
        super(state, response: recordChanges.map((recordChange) => recordChange.localObject).toList());
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

  Map<String, dynamic>? _getBody();

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
  final bool _shouldPreloadAssets;

  CKRecordQueryOperation(CKDatabase database, {CKRecordQueryRequest? queryRequest, CKZone? zoneID, int? resultsLimit, List<CKFilter>? filters, List<CKSortDescriptor>? sortDescriptors, bool? preloadAssets, CKAPIManager? apiManager}) : _shouldPreloadAssets = preloadAssets ?? false, super(CKAPIModule.DATABASE, database: database, apiManager: apiManager)
  {
    var recordStructure = CKRecordParser.getRecordStructureFromLocalType(T);
    this._recordQueryRequest = queryRequest ?? CKRecordQueryRequest(zoneID ?? CKZone(), resultsLimit, CKQuery(recordStructure.ckRecordType, filterBy: filters, sortBy: sortDescriptors));
  }

  @override
  String _getAPIPath() => "records/query";

  @override
  Map<String, dynamic>? _getBody() => _recordQueryRequest.toJSON();

  /// Execute the record query operation.
  @override
  Future<CKOperationCallback<List<T>>> execute() async
  {
    CKOperationCallback apiCallback = await super.execute();

    List<T> newLocalObjects = [];
    if (apiCallback.state == CKOperationState.success)
    {
      var recordsList = apiCallback.response["records"];

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

/// An operation to fetch record zone changes.
class CKRecordZoneChangesOperation<T> extends CKPostOperation
{
  final CKRecordZoneChangesRequest _recordZoneChangesRequest;
  CKSyncToken? _currentSyncToken;
  List<CKRecordOperationType>? _changeTypes;
  bool _shouldPreloadAssets;

  CKRecordZoneChangesOperation(CKDatabase database, {CKRecordZoneChangesRequest? zoneChangesRequest, CKZone? zoneID, CKSyncToken? syncToken, List<Type>? recordTypes, int? resultsLimit, List<String>? recordFields, bool? preloadAssets, CKAPIManager? apiManager}) :
    this._recordZoneChangesRequest = zoneChangesRequest ?? CKRecordZoneChangesRequest<T>(zoneID!, syncToken, resultsLimit, recordFields, recordTypes),
    this._currentSyncToken = syncToken,
    this._shouldPreloadAssets = preloadAssets ?? false,
    super(CKAPIModule.DATABASE, database: database, apiManager: apiManager);

  @override
  String _getAPIPath() => "changes/zone";

  @override
  Map<String, dynamic>? _getBody() => {
    "zones": [
      _recordZoneChangesRequest.toJSON()
    ]
  };

  /// Execute the record zone changes.
  @override
  Future<CKChangesOperationCallback<T>> execute() async
  {
    CKOperationCallback recordZoneChangesCallback = await super.execute();

    if (recordZoneChangesCallback.response["zones"].length <= 0) return CKChangesOperationCallback<T>(recordZoneChangesCallback.state, [], null);

    var zoneChangesResponse = recordZoneChangesCallback.response["zones"][0];
    _currentSyncToken = CKSyncToken(zoneChangesResponse["syncToken"]);

    List records = zoneChangesResponse["records"];

    var fetchingMultipleRecordTypes = T == dynamic;
    Map<String,CKRecordStructure> recordStructures = {};

    if (fetchingMultipleRecordTypes)
    {
      var receivedRecordTypes = Set<String>();
      records.forEach((recordJSON) {
        if (recordJSON[CKConstants.RECORD_TYPE_FIELD] == null) return;
        receivedRecordTypes.add(recordJSON[CKConstants.RECORD_TYPE_FIELD]);
      });
      receivedRecordTypes.forEach((recordType) {
        var recordStructure = CKRecordParser.getRecordStructureFromRecordType(recordType);
        if (recordStructure.recordTypeAnnotation == null)
        {
          records.removeWhere((recordJSON) => recordJSON[CKConstants.RECORD_TYPE_FIELD] == recordType);
        }
        else
        {
          recordStructures[recordType] = recordStructure;
        }
      });
    }

    _changeTypes = records.map((recordJSON) => !(recordJSON["deleted"] as bool) ? CKRecordOperationType.UPDATE : CKRecordOperationType.DELETE).toList();

    var rawRecordChanges = zip([records, _changeTypes!]).map((recordChange) => Tuple2<dynamic, CKRecordOperationType>.fromList(recordChange)).toList();

    List<T?> newLocalObjects = [];
    List<String> recordIDs = [];
    List<Type> correspondingRecordTypes = [];
    List<String?> recordChangeTags = [];

    for (var recordChange in rawRecordChanges)
    {
      var recordMap = recordChange.item1;
      var changeType = recordChange.item2;

      recordIDs.add(recordMap[CKConstants.RECORD_NAME_FIELD]);
      recordChangeTags.add(recordMap[CKConstants.RECORD_CHANGE_TAG_FIELD]);

      T? newObject;
      if (fetchingMultipleRecordTypes)
      {
        switch (changeType)
        {
          case CKRecordOperationType.CREATE:
          case CKRecordOperationType.UPDATE:
            String recordType = recordMap[CKConstants.RECORD_TYPE_FIELD];
            newObject = recordStructures[recordType]!.recordTypeAnnotation!.recordToLocalObject(recordMap, _database!) as T;
            if (_shouldPreloadAssets) await recordStructures[recordType]!.recordTypeAnnotation!.preloadAssets(newObject!);
            correspondingRecordTypes.add(recordStructures[recordType]!.localType);
            break;

          case CKRecordOperationType.DELETE:
            correspondingRecordTypes.add(dynamic);
            break;
        }
      }
      else
      {
        switch (changeType)
        {
          case CKRecordOperationType.CREATE:
          case CKRecordOperationType.UPDATE:
            newObject = CKRecordParser.recordToLocalObject<T>(recordMap as Map<String,dynamic>, _database!);
            if (_shouldPreloadAssets) await CKRecordParser.preloadAssets<T>(newObject!);
            correspondingRecordTypes.add(T);
            break;

          case CKRecordOperationType.DELETE:
            correspondingRecordTypes.add(T);
            break;
        }
      }
      newLocalObjects.add(newObject);
    }

    var recordChanges = zip([recordIDs, _changeTypes!, correspondingRecordTypes, newLocalObjects, recordChangeTags])
        .map((List recordChangeTuple) => CKRecordChange<T>(recordChangeTuple[0], recordChangeTuple[1], recordChangeTuple[2], localObject: recordChangeTuple[3], recordChangeTag: recordChangeTuple[4]))
        .toList();

    if (zoneChangesResponse["moreComing"])
    {
      _recordZoneChangesRequest.syncToken = _currentSyncToken;
      var moreRecordChanges = await execute();
      recordChanges.addAll(moreRecordChanges.recordChanges);
    }

    return CKChangesOperationCallback<T>(recordZoneChangesCallback.state, recordChanges, _currentSyncToken);
  }
}

/// An operation to modify records.
class CKRecordModifyOperation extends CKPostOperation
{
  late final CKRecordModifyRequest _recordModifyRequest;

  CKRecordModifyOperation(CKDatabase database, {CKRecordModifyRequest? modifyRequest, List<CKRecordChange>? recordChanges, CKZone? zoneID, bool? atomic, List<String>? recordFields, bool? numbersAsStrings, CKAPIManager? apiManager}) : super(CKAPIModule.DATABASE, database: database, apiManager: apiManager)
  {
    this._recordModifyRequest = modifyRequest ?? CKRecordModifyRequest((recordChanges ?? []).map((recordChange) {
      var recordJSON = recordChange.recordJSON!;
      recordJSON[CKConstants.RECORD_CHANGE_TAG_FIELD] ??= recordChange.recordMetadata.changeTag;
      recordJSON[CKConstants.RECORD_FIELDS_FIELD].removeWhere((fieldName, fieldValue) => fieldValue["type"] == CKFieldType.ASSET_TYPE.record); // TODO: Handle asset field changes
      var operationType = recordChange.operationType;

      return CKRecordOperation(operationType, recordJSON, null);
    }).toList(), zoneID ?? CKZone(), atomic, recordFields, numbersAsStrings);
  }

  @override
  String _getAPIPath() => "records/modify";

  @override
  Map<String, dynamic>? _getBody() => _recordModifyRequest.toJSON();

  /// Execute the record modify operation.
  @override
  Future<CKOperationCallback<List<CKRecordMetadata>>> execute() async
  {
    CKOperationCallback recordModifyCallback = await super.execute();

    List<CKRecordMetadata> recordsMetadata = [];
    if (recordModifyCallback.response != null)
    {
      List modifiedRecords = recordModifyCallback.response["records"];
      recordsMetadata = modifiedRecords.map((recordJSON) =>
          CKRecordMetadata(recordJSON[CKConstants.RECORD_NAME_FIELD], recordType: recordJSON[CKConstants.RECORD_TYPE_FIELD], changeTag: recordJSON[CKConstants.RECORD_CHANGE_TAG_FIELD])
      ).toList();
    }

    return CKOperationCallback<List<CKRecordMetadata>>(recordModifyCallback.state, response: recordsMetadata);
  }
}

mixin _CKZoneHandler
{
  Future<CKOperationCallback<List<CKZone>>> parseZones(CKOperationCallback zoneListCallback) async
  {
    List zonesJSON = zoneListCallback.response["zones"];
    List<CKZone> zones = zonesJSON.expand((zoneJSON) {
      if (zoneJSON["serverErrorCode"] == null) return [CKZone(zoneJSON["zoneID"]["zoneName"])];

      print(zoneJSON["serverErrorCode"] + " -- " + zoneJSON["reason"]);
      return <CKZone>[];
    }).toList();
    return CKOperationCallback(CKOperationState.success, response: zones);
  }
}

class CKZoneFetchOperation extends CKGetOperation with _CKZoneHandler
{
  CKZoneFetchOperation(CKDatabase database, {CKAPIManager? apiManager}) : super(CKAPIModule.DATABASE, database: database, apiManager: apiManager);

  @override
  String _getAPIPath() => "zones/list";

  /// Execute the zone fetch operation.
  @override
  Future<CKOperationCallback<List<CKZone>>> execute() async
  {
    CKOperationCallback zoneListCallback = await super.execute();
    return parseZones(zoneListCallback);
  }
}

class CKZoneLookupOperation extends CKPostOperation with _CKZoneHandler
{
  List<CKZone> zones;

  CKZoneLookupOperation(this.zones, CKDatabase database, {CKAPIManager? apiManager}) : super(CKAPIModule.DATABASE, database: database, apiManager: apiManager);

  @override
  String _getAPIPath() => "zones/lookup";

  @override
  Map<String, dynamic> _getBody() => {
    "zones": zones.map((zone) => zone.toJSON()).toList()
  };

  /// Execute the zone fetch operation.
  @override
  Future<CKOperationCallback<List<CKZone>>> execute() async
  {
    CKOperationCallback zoneListCallback = await super.execute();
    return parseZones(zoneListCallback);
  }
}

class CKZoneModifyOperation extends CKPostOperation with _CKZoneHandler
{
  List<CKZoneOperation> operations;

  CKZoneModifyOperation(this.operations, CKDatabase database, {CKAPIManager? apiManager}) : super(CKAPIModule.DATABASE, database: database, apiManager: apiManager);

  @override
  String _getAPIPath() => "zones/modify";

  @override
  Map<String, dynamic> _getBody() => {
    "operations": operations.map((operation) => operation.toJSON()).toList()
  };

  /// Execute the zone fetch operation.
  @override
  Future<CKOperationCallback<List<CKZone>>> execute() async
  {
    CKOperationCallback zoneListCallback = await super.execute();
    return parseZones(zoneListCallback);
  }
}

mixin _CKSubscriptionHandler
{
  Future<CKOperationCallback<List<CKSubscription>>> parseSubscriptions(CKOperationCallback subscriptionListCallback) async
  {
    List subscriptionsJSON = subscriptionListCallback.response["subscriptions"];
    List<CKSubscription> subscriptions = subscriptionsJSON.expand((subscriptionJSON) {
      if (subscriptionJSON["serverErrorCode"] == null) return [CKSubscription.fromJSON(subscriptionJSON)];

      print(subscriptionJSON["serverErrorCode"] + " -- " + subscriptionJSON["reason"]);
      return <CKSubscription>[];
    }).toList();
    return CKOperationCallback<List<CKSubscription>>(CKOperationState.success, response: subscriptions);
  }
}

/// An operation to fetch subscriptions.
class CKSubscriptionFetchOperation extends CKGetOperation with _CKSubscriptionHandler
{
  CKSubscriptionFetchOperation(CKDatabase database, {CKAPIManager? apiManager}) : super(CKAPIModule.DATABASE, database: database, apiManager: apiManager);

  @override
  String _getAPIPath() => "subscriptions/list";

  /// Execute the subscription fetch operation.
  @override
  Future<CKOperationCallback<List<CKSubscription>>> execute() async
  {
    CKOperationCallback subscriptionListCallback = await super.execute();
    return parseSubscriptions(subscriptionListCallback);
  }
}

/// An operation to fetch subscriptions by id.
class CKSubscriptionLookupOperation extends CKPostOperation with _CKSubscriptionHandler
{
  List<String> subscriptionIDs;

  CKSubscriptionLookupOperation(this.subscriptionIDs, CKDatabase database, {CKAPIManager? apiManager}) : super(CKAPIModule.DATABASE, database: database, apiManager: apiManager);

  @override
  String _getAPIPath() => "subscriptions/lookup";

  @override
  Map<String, dynamic> _getBody() => {
    "subscriptions": subscriptionIDs.map((id) => {"subscriptionID": id}).toList()
  };

  /// Execute the subscription lookup operation.
  @override
  Future<CKOperationCallback<List<CKSubscription>>> execute() async
  {
    CKOperationCallback subscriptionListCallback = await super.execute();
    return parseSubscriptions(subscriptionListCallback);
  }
}

/// An operation to modify subscriptions.
class CKSubscriptionModifyOperation extends CKPostOperation with _CKSubscriptionHandler
{
  final List<CKSubscriptionOperation> operations;

  CKSubscriptionModifyOperation(this.operations, CKDatabase database, {CKAPIManager? apiManager}) : super(CKAPIModule.DATABASE, database: database, apiManager: apiManager);

  @override
  String _getAPIPath() => "subscriptions/modify";

  @override
  Map<String, dynamic>? _getBody() => {
    "operations": operations.map((subscription) => subscription.toJSON()).toList()
  };

  /// Execute the subscription modify operation.
  @override
  Future<CKOperationCallback<List<CKSubscription>>> execute() async
  {
    CKOperationCallback subscriptionListCallback = await super.execute();
    return parseSubscriptions(subscriptionListCallback);
  }
}

/// An operation to create an APNS token.
class CKAPNSCreateTokenOperation extends CKPostOperation
{
  final CKAPNSEnvironment _apnsEnvironment;

  CKAPNSCreateTokenOperation(this._apnsEnvironment, {CKAPIManager? apiManager}) : super(CKAPIModule.DEVICE, apiManager: apiManager);

  @override
  String _getAPIPath() => "tokens/create";

  @override
  Map<String, dynamic>? _getBody() => {
    "apnsEnvironment": _apnsEnvironment.toString()
  };

  /// Execute the create token operation.
  @override
  Future<CKOperationCallback<CKAPNSToken>> execute() async
  {
    CKOperationCallback createTokenCallback = await super.execute();
    return CKOperationCallback<CKAPNSToken>(createTokenCallback.state,
        response: createTokenCallback.state == CKOperationState.success ? CKAPNSToken.fromJSON(createTokenCallback.response) : null
    );
  }
}

/// An operation to register an APNS token.
class CKAPNSRegisterTokenOperation extends CKPostOperation
{
  final CKAPNSToken _token;

  CKAPNSRegisterTokenOperation(this._token, {CKAPIManager? apiManager}) : super(CKAPIModule.DEVICE, apiManager: apiManager);

  @override
  String _getAPIPath() => "tokens/register";

  @override
  Map<String, dynamic>? _getBody() => _token.toJSON();

  /// Execute the register token operation.
  @override
  Future<CKOperationCallback> execute() async
  {
    CKOperationCallback registerTokenCallback = await super.execute();
    return registerTokenCallback;
  }
}