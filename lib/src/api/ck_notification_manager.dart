import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:async/async.dart';

import '/src/ck_constants.dart';
import 'ck_api_manager.dart';
import 'ck_operation.dart';
import 'request_models/ck_zone.dart';
import 'ck_subscription.dart';

/// The manager for registering and listening to APNS notifications
class CKNotificationManager
{
  CKAPNSToken? _token;
  StreamController<CKNotification>? _notificationStreamController;
  Queue<CKNotification>? _notificationQueue;
  CancelableOperation<http.Response>? _subscriptionRequest;
  int _retryTimeout = 1;

  static CKNotificationManager? _instance;

  /// Get the shared instance of the [CKNotificationManager].
  static CKNotificationManager get shared
  {
    if (_instance == null) _instance = CKNotificationManager();
    return _instance!;
  }

  /// Register for remote notifications in the given [CKAPNSEnvironment].
  Future<Stream<CKNotification>> registerForRemoteNotifications(CKAPNSEnvironment environment, {CKAPIManager? apiManager}) async
  {
    await _createToken(environment, apiManager: apiManager);

    _notificationQueue = Queue<CKNotification>();

    Future<void> subscribe() async {
      var subscribeFuture = http.post(Uri.parse(_token!.webCourierURL));
      _subscriptionRequest = CancelableOperation<http.Response>.fromFuture(subscribeFuture);

      var response = await _subscriptionRequest?.valueOrCancellation();
      if (response == null) return;

      if (response.statusCode == 502) // timeout
      {
        subscribe();
      }
      else if (response.statusCode == 403) // invalid token
      {
        print("Regenerating notification token: ${response.reasonPhrase}, ${response.body}; Retry in ${_retryTimeout}s");
        await _createToken(environment, apiManager: apiManager, shouldResetToken: true);
        Timer(Duration(seconds: _retryTimeout), () {
          _retryTimeout *= 2;
          subscribe();
        });
      }
      else if (response.statusCode != 200) // error
      {
        print("Notification error: ${response.reasonPhrase}, ${response.body}; Retry in ${_retryTimeout}s");
        Timer(Duration(seconds: _retryTimeout), () {
          _retryTimeout *= 2;
          subscribe();
        });
      }
      else
      {
        _retryTimeout = 1;
        if (_notificationStreamController == null || _notificationStreamController!.isClosed) return;

        var notification = CKNotification.fromJSON(jsonDecode(response.body));
        if (!_notificationStreamController!.isPaused && _notificationStreamController!.hasListener)
        {
          _notificationStreamController!.add(notification);
        }
        else
        {
          _notificationQueue!.add(notification);
        }

        subscribe();
      }
    }

    _notificationStreamController = StreamController<CKNotification>(
      onListen: () {
        subscribe();
      },
      onPause: () {},
      onResume: () {
        while (_notificationQueue!.isNotEmpty)
        {
          var queueNotification = _notificationQueue!.removeFirst();
          _notificationStreamController!.add(queueNotification);
        }
      },
      onCancel: () {
        _subscriptionRequest?.cancel();
      }
    );

    return _notificationStreamController!.stream;
  }

  /// Unregister for remote notifications.
  Future<void> unregisterForRemoteNotifications() async
  {
    await _notificationStreamController?.close();
  }

  Future<void> _createToken(CKAPNSEnvironment environment, {CKAPIManager? apiManager, bool shouldResetToken = false}) async
  {
    var savedToken = await _fetchNotificationToken();
    if (savedToken != null && !shouldResetToken)
    {
      _token = savedToken;
      return;
    }

    var createTokenOperation = CKAPNSCreateTokenOperation(environment, apiManager: apiManager);
    var createTokenCallback = await createTokenOperation.execute();
    _token = createTokenCallback.response;

    if (_token != null)
    {
      await _saveNotificationToken(_token!);

      var registerTokenOperation = CKAPNSRegisterTokenOperation(_token!, apiManager: apiManager);
      await registerTokenOperation.execute();
    }
  }

  Future<void> _saveNotificationToken(CKAPNSToken token) async
  {
    WidgetsFlutterBinding.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(CKConstants.NOTIFICATION_TOKEN_STORAGE_KEY, jsonEncode(token.toJSON()));
  }

  Future<CKAPNSToken?> _fetchNotificationToken() async
  {
    WidgetsFlutterBinding.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    var tokenJSON = prefs.getString(CKConstants.NOTIFICATION_TOKEN_STORAGE_KEY);
    return tokenJSON != null ? CKAPNSToken.fromJSON(jsonDecode(tokenJSON)) : null;
  }
}

/// A token container class for receiving APNS notifications.
class CKAPNSToken
{
  /// The APNS token string.
  final String token;
  /// The APNS environment (development or production).
  final CKAPNSEnvironment environment;
  /// The URL for receiving long-poll notifications.
  final String webCourierURL;

  const CKAPNSToken(this.token, this.environment, this.webCourierURL);

  /// Create a token from JSON.
  static CKAPNSToken fromJSON(Map<String, dynamic> json) =>
      CKAPNSToken(json["apnsToken"], CKAPNSEnvironment(json["apnsEnvironment"]), json["webcourierURL"]);

  /// Convert the token to JSON.
  Map<String, dynamic>? toJSON() => {
    "apnsToken": token,
    "apnsEnvironment": environment.toString(),
    "webcourierURL": webCourierURL
  };
}

/// A string constant class for APNS environments.
class CKAPNSEnvironment extends StringConstant
{
  static const PRODUCTION = CKAPNSEnvironment("production");
  static const DEVELOPMENT = CKAPNSEnvironment("development");

  const CKAPNSEnvironment(String apnsEnvironment) : super(apnsEnvironment);
}

/// A representation of received CloudKit notification JSON objects.
class CKNotification
{
  /// The subscription type of the notification (query or zone).
  CKSubscriptionType type;
  /// The notification id.
  String id;
  /// The CloudKit container of the notification.
  String container;

  CKNotification(this.type, this.id, this.container);

  /// Create a notification from JSON.
  static CKNotification fromJSON(Map<String, dynamic> json)
  {
    var ckInfo = json["ck"];
    var notificationID = ckInfo["nid"];
    var containerID = ckInfo["cid"];

    if (ckInfo["fet"] != null)
    {
      return CKZoneNotification(notificationID, containerID, ckInfo["fet"]);
    }
    if (ckInfo["qry"] != null)
    {
      return CKQueryNotification(notificationID, containerID, ckInfo["qry"]);
    }
    return CKNotification(CKSubscriptionType.UNKNOWN, notificationID, containerID);
  }
}

/// A representation of query-type CloudKit notification
class CKQueryNotification extends CKNotification
{
  CKQueryNotification(String id, String container, Map<String, dynamic> queryInfo) : super(CKSubscriptionType.QUERY, id, container);
}

/// A representation of zone-type CloudKit notification
class CKZoneNotification extends CKNotification
{
  /// The CloudKit zone id.
  CKZone zoneID;
  /// The CloudKit database.
  CKDatabase database;
  /// The subscription id that triggered the notification.
  String subscriptionID;

  CKZoneNotification(String id, String container, Map<String, dynamic> zoneInfo) :
        zoneID = CKZone(zoneInfo["zid"]),
        database = CKDatabase.databases[zoneInfo["dbs"]],
        subscriptionID = zoneInfo["sid"],
        super(CKSubscriptionType.ZONE, id, container);
}