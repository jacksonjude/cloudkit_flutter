import 'ck_zone.dart';
import 'ck_query.dart';

/// A container class for the zone ID, result limit, and query information for a CloudKit record query request.
class CKRecordQueryRequest
{
  final CKZone _zoneID;
  final int? _resultsLimit;
  final CKQuery _query;

  CKRecordQueryRequest(this._zoneID, this._resultsLimit, this._query);

  /// Convert the record query request to JSON.
  Map<String, dynamic> toJSON() => {
    'zoneID': _zoneID.toJSON(),
    'resultsLimit': _resultsLimit,
    'query': _query.toJSON()
  };
}