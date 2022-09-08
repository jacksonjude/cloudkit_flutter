import '/src/ck_constants.dart';
import 'request_models/ck_zone.dart';
import 'request_models/ck_query.dart';

abstract class CKSubscription
{
  final CKSubscriptionType type;
  final String id;
  final CKZone zoneID;
  final Map<String, dynamic> notificationInfo; // TODO: Add NotificationInfo class

  CKSubscription(this.type, this.id, this.zoneID, {Map<String, dynamic>? notificationInfo}) : notificationInfo = notificationInfo ?? {"shouldSendContentAvailable": true};

  Map<String, dynamic> toJSON() => {
    "subscriptionType": type.toString(),
    "subscriptionID": id,
    "zoneID": zoneID.toJSON(),
    "notificationInfo": notificationInfo
  };

  static CKSubscription fromJSON(Map<String, dynamic> json)
  {
    String subscriptionID = json["subscriptionID"];
    Map<String, dynamic> notificationInfo = json["notificationInfo"];
    var zoneID = CKZone(json["zoneID"]["zoneName"]);

    var subscriptionType = CKSubscriptionType.types.firstWhere((type) => type.toString() == json["subscriptionType"]);
    switch (subscriptionType)
    {
      case CKSubscriptionType.ZONE:
        return CKZoneSubscription(subscriptionID, zoneID, notificationInfo: notificationInfo);

      case CKSubscriptionType.QUERY:
        var query = CKQuery.fromJSON(json["query"]);
        List firesOn = json["firesOn"];
        bool fireOnce = json["fireOnce"] ?? false;
        bool zoneWide = json["zoneWide"];
        return CKQuerySubscription(subscriptionID, zoneID, query, firesOn.cast<String>(), fireOnce, zoneWide, notificationInfo: notificationInfo);
    }

    throw Exception("Invalid subscription json");
  }
}

class CKZoneSubscription extends CKSubscription
{
  CKZoneSubscription(String id, CKZone zoneID, {Map<String, dynamic>? notificationInfo}) : super(CKSubscriptionType.ZONE, id, zoneID, notificationInfo: notificationInfo);

  Map<String, dynamic> toJSON() => super.toJSON();
}

class CKQuerySubscription extends CKSubscription
{
  CKQuery query;
  List<String> firesOn;
  bool fireOnce;
  bool zoneWide;

  CKQuerySubscription(String id, CKZone zoneID, this.query, this.firesOn, this.fireOnce, this.zoneWide, {Map<String, dynamic>? notificationInfo}) : super(CKSubscriptionType.QUERY, id, zoneID, notificationInfo: notificationInfo);

  Map<String, dynamic> toJSON() => super.toJSON().withAll({
    "query": query.toJSON(),
    "firesOn": firesOn,
    "fireOnce": fireOnce,
    "zoneWide": zoneWide
  });
}

/// A string constant class for notification types.
class CKSubscriptionType extends StringConstant
{
  static const ZONE = CKSubscriptionType("zone");
  static const QUERY = CKSubscriptionType("query");
  static const UNKNOWN = CKSubscriptionType("unknown");

  static const types = [ZONE, QUERY];

  const CKSubscriptionType(String subscriptionType) : super(subscriptionType);
}

extension JSONWithAll on Map<String, dynamic>
{
  Map<String, dynamic> withAll(Map<String, dynamic> jsonToAdd)
  {
    this.addAll(jsonToAdd);
    return this;
  }
}