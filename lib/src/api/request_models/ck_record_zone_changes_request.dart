import '../../parsing/ck_record_parser.dart';

import 'ck_zone.dart';
import 'ck_sync_token.dart';

/// A container class for the zone ID, result limit, and sync token for a CloudKit record zone changes request.
class CKRecordZoneChangesRequest<T>
{
  final CKZone _zoneID;
  final int? _resultsLimit;
  final List<String>? _recordFields;
  final List<Type>? _recordTypes;
  CKSyncToken? syncToken;

  CKRecordZoneChangesRequest(this._zoneID, this.syncToken, this._resultsLimit, this._recordFields, this._recordTypes);

  /// Convert the record zone changes to JSON.
  Map<String, dynamic> toJSON() => {
    'zoneID': _zoneID.toJSON(),
    'syncToken': syncToken != null ? syncToken.toString() : null,
    'resultsLimit': _resultsLimit,
    'desiredRecordTypes': (_recordTypes ?? [T]).map((type) => CKRecordParser.getRecordStructureFromLocalType(type).ckRecordType).toList(),
    'desiredKeys': _recordFields
  };
}