import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '/src/ck_constants.dart';
import 'ck_api_manager.dart';
import 'ck_operation.dart';

class CKNotificationManager
{
  CKAPNSToken? _token;
  StreamController<CKNotification>? _notificationStreamController;
  Queue<CKNotification>? _notificationQueue;

  static CKNotificationManager? _instance;

  static CKNotificationManager get shared
  {
    if (_instance == null) _instance = CKNotificationManager();
    return _instance!;
  }

  Future<Stream<CKNotification>> registerForRemoteNotifications(CKAPNSEnvironment environment, {CKAPIManager? apiManager}) async
  {
    await _createToken(environment, apiManager: apiManager);

    _notificationQueue = Queue<CKNotification>();

    Future<void> subscribe() async {
      var response = await http.post(Uri.parse(_token!.webCourierURL));
      if (response.statusCode == 502) // timeout
      {
        subscribe();
      }
      else if (response.statusCode == 403) // invalid token
      {
        print("Regenerating notification token: ${response.reasonPhrase}, ${response.body}");
        await _createToken(environment, apiManager: apiManager, shouldResetToken: true);
        Timer(Duration(seconds: 1), () => subscribe());
      }
      else if (response.statusCode != 200) // error
      {
        print("Notification error: ${response.reasonPhrase}, ${response.body}");
        Timer(Duration(seconds: 1), () => subscribe());
      }
      else
      {
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
      onCancel: () {}
    );

    return _notificationStreamController!.stream;
  }

  Future<void> unregisterForRemoteNotifications() async
  {
    await _notificationStreamController?.close();
  }

  Future<void> _createToken(CKAPNSEnvironment environment, {CKAPIManager? apiManager, bool shouldResetToken = false}) async
  {
    var savedToken = await fetchNotificationToken();
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
      await saveNotificationToken(_token!);

      var registerTokenOperation = CKAPNSRegisterTokenOperation(_token!, apiManager: apiManager);
      await registerTokenOperation.execute();
    }
  }

  Future<void> saveNotificationToken(CKAPNSToken token) async
  {
    WidgetsFlutterBinding.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(CKConstants.NOTIFICATION_TOKEN_STORAGE_KEY, jsonEncode(token.toJSON()));
  }

  Future<CKAPNSToken?> fetchNotificationToken() async
  {
    WidgetsFlutterBinding.ensureInitialized();
    final prefs = await SharedPreferences.getInstance();
    var tokenJSON = prefs.getString(CKConstants.NOTIFICATION_TOKEN_STORAGE_KEY);
    return tokenJSON != null ? CKAPNSToken.fromJSON(jsonDecode(tokenJSON)) : null;
  }
}

class CKAPNSToken
{
  final String token;
  final CKAPNSEnvironment environment;
  final String webCourierURL;

  const CKAPNSToken(this.token, this.environment, this.webCourierURL);

  static CKAPNSToken fromJSON(Map<String, dynamic> json) =>
      CKAPNSToken(json["apnsToken"], CKAPNSEnvironment(json["apnsEnvironment"]), json["webcourierURL"]);

  Map<String, dynamic>? toJSON() => {
    "apnsToken": token,
    "apnsEnvironment": environment.toString(),
    "webcourierURL": webCourierURL
  };
}

class CKAPNSEnvironment extends StringConstant
{
  static const PRODUCTION = CKAPNSEnvironment("production");
  static const DEVELOPMENT = CKAPNSEnvironment("development");

  const CKAPNSEnvironment(String apnsEnvironment) : super(apnsEnvironment);
}

class CKNotification
{
  CKNotificationType type;
  String id;
  String container;

  CKNotification(this.type, this.id, this.container);

  static CKNotification fromJSON(Map<String, dynamic> json)
  {
    var ckInfo = json["ck"];
    var notificationID = ckInfo["nid"];
    var containerID = ckInfo["cid"];

    if (ckInfo["fet"] != null)
    {
      return CKZoneNotification(notificationID, containerID);
    }
    if (ckInfo["qry"] != null)
    {
      return CKZoneNotification(notificationID, containerID);
    }
    return CKNotification(CKNotificationType.UNKNOWN, notificationID, containerID);
  }
}

class CKQueryNotification extends CKNotification
{
  CKQueryNotification(String id, String container) : super(CKNotificationType.QUERY, id, container);
}

class CKZoneNotification extends CKNotification
{
  CKZoneNotification(String id, String container, ) : super(CKNotificationType.ZONE, id, container);
}

class CKNotificationType extends StringConstant
{
  static const ZONE = CKNotificationType("ZONE");
  static const QUERY = CKNotificationType("QUERY");
  static const UNKNOWN = CKNotificationType("UNKNOWN");

  const CKNotificationType(String notificationType) : super(notificationType);
}