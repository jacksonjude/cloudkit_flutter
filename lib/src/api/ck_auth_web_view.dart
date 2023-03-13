import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../ck_constants.dart';

class CKAuthWebView extends StatefulWidget {
  final String title = "iCloud Authentication";

  final String authenticationURL;
  final String redirectURLPattern;

  CKAuthWebView({
    Key? key,
    required this.authenticationURL,
    required this.redirectURLPattern,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _CKAuthWebViewState();
}

class _CKAuthWebViewState extends State<CKAuthWebView> {
  late WebViewController webViewController;

  @override
  void initState() {
    super.initState();

    webViewController = WebViewController()
      ..loadRequest(Uri.parse(widget.authenticationURL));

    webViewController.setJavaScriptMode(JavaScriptMode.unrestricted);
    webViewController.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (NavigationRequest request) {
          if (request.url.startsWith(widget.redirectURLPattern)) {
            var redirectURI = Uri.dataFromString(request.url);
            var ckWebAuthTokenEncoded = redirectURI
                .queryParameters[CKConstants.WEB_AUTH_TOKEN_PARAMETER];
            if (ckWebAuthTokenEncoded == null) {
              Navigator.pop(context, CKAuthCallback(CKAuthState.failure));
            } else {
              var ckWebAuthToken =
                  Uri.decodeQueryComponent(ckWebAuthTokenEncoded);
              Navigator.pop(
                  context,
                  CKAuthCallback(
                    CKAuthState.success,
                    authToken: ckWebAuthToken,
                  ));
            }
          }

          return NavigationDecision.navigate;
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () =>
              Navigator.pop(context, CKAuthCallback(CKAuthState.cancel)),
        ),
        title: Text(widget.title),
      ),
      body: Builder(
        builder: (BuildContext context) {
          return WebViewWidget(
            controller: webViewController,
          );
        },
      ),
    );
  }
}

enum CKAuthState { success, failure, cancel }

class CKAuthCallback {
  final CKAuthState state;
  final String? authToken;

  CKAuthCallback(CKAuthState state, {String? authToken})
      : state = state,
        authToken = authToken;
}
