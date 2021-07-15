import 'ck_zone.dart';
import 'ck_query.dart';

class CKRecordQueryRequest
{
  final CKZone zoneID;
  final int? resultsLimit;
  final CKQuery query;

  CKRecordQueryRequest(this.zoneID, this.resultsLimit, this.query);

  Map<String, dynamic> toJSON() => {
    'zoneID': zoneID.toJSON(),
    'resultsLimit': resultsLimit,
    'query': query.toJSON()
  };
}