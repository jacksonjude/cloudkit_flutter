import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '/src/ck_constants.dart';

class CKAuthWebView extends StatefulWidget
{
  final String title = "iCloud Authentication";

  final String authenticationURL;
  final String redirectURLPattern;

  CKAuthWebView({Key? key, required this.authenticationURL, required this.redirectURLPattern}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _CKAuthWebViewState();
}

class _CKAuthWebViewState extends State<CKAuthWebView>
{
  @override
  void initState()
  {
    super.initState();
    // Enable hybrid composition, as detailed in https://pub.dev/packages/webview_flutter
    if (Platform.isAndroid) WebView.platform = SurfaceAndroidWebView();
  }

  @override
  Widget build(BuildContext context)
  {
    var signInRequired = true;

    Widget cancelButton;

    if (signInRequired == false) {
      cancelButton = IconButton(
        icon: Icon(Icons.arrow_back),
        onPressed: () => Navigator.pop(context, CKAuthCallback(CKAuthState.cancel)),
      );
    } else {
      cancelButton = Text("");
    }

    var webView = WebView(
      initialUrl: widget.authenticationURL,
      javascriptMode: JavascriptMode.unrestricted,
      navigationDelegate: (NavigationRequest request) async {
        if (request.url.contains("iforgot")) {
          var uri = Uri.parse(request.url);
          await launchUrl(uri, mode: LaunchMode.externalApplication);

          return NavigationDecision.prevent;
        }
        else if (request.url.startsWith(widget.redirectURLPattern))
        {
          var redirectURI = Uri.dataFromString(request.url);
          var ckWebAuthTokenEncoded = redirectURI.queryParameters[CKConstants.WEB_AUTH_TOKEN_PARAMETER];
          if (ckWebAuthTokenEncoded == null)
          {
            Navigator.pop(context, CKAuthCallback(CKAuthState.failure));
          }
          else
          {
            var ckWebAuthToken = Uri.decodeQueryComponent(ckWebAuthTokenEncoded);
            Navigator.pop(context, CKAuthCallback(CKAuthState.success, authToken: ckWebAuthToken));
          }
        }

        return NavigationDecision.navigate;
      },
    );

    var children = <Widget>[];

    children.add(webView);
    // children.add(Text("An AppleID is required.  Tap here to create one."));

    return Scaffold(
      appBar: AppBar(
        leading: cancelButton,
        title: Text(widget.title),
      ),
      body: Builder(builder: (BuildContext context) {
        return Stack(
          children: children,
        );
      })
    );
  }
}

enum CKAuthState
{
  success,
  failure,
  cancel
}

class CKAuthCallback
{
  final CKAuthState state;
  final String? authToken;

  CKAuthCallback(CKAuthState state, {String? authToken}) : state = state, authToken = authToken;
}