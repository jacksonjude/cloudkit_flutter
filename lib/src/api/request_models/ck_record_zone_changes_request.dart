import '../../parsing/ck_record_parser.dart';

import 'ck_zone.dart';
import 'ck_sync_token.dart';

/// A container class for the zone ID, result limit, and sync token for a CloudKit record zone changes request.
class CKRecordZoneChangesRequest<T extends Object>
{
  final CKZone _zoneID;
  final CKSyncToken? _syncToken;
  final int? _resultsLimit;
  final List<String>? _recordFields;

  CKRecordZoneChangesRequest(this._zoneID, this._syncToken, this._resultsLimit, this._recordFields);

  /// Convert the record zone changes to JSON.
  Map<String, dynamic> toJSON() => {
    'zoneID': _zoneID.toJSON(),
    'syncToken': _syncToken.toString(),
    'resultsLimit': _resultsLimit,
    'desiredRecordTypes': [CKRecordParser.getRecordStructureFromLocalType(T).ckRecordType],
    'desiredKeys': _recordFields
  };
}