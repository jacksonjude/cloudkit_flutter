import '/src/ck_constants.dart';
import '/src/api/ck_subscription.dart';

class CKSubscriptionOperation
{
  final CKSubscriptionOperationType operationType;
  final CKSubscription subscription;

  CKSubscriptionOperation(this.operationType, this.subscription);

  Map<String, dynamic> toJSON() => {
    "operationType": operationType.toString(),
    "subscription": subscription.toJSON()
  };
}

class CKSubscriptionOperationType extends StringConstant
{
  static const CREATE = CKSubscriptionOperationType("create");
  static const UPDATE = CKSubscriptionOperationType("update");
  static const DELETE = CKSubscriptionOperationType("delete");

  const CKSubscriptionOperationType(String operationType) : super(operationType);
}