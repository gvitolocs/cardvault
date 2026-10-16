import 'dart:convert';
import 'dart:js_interop';

@JS('window.opener.postMessage')
external void _postMessageToOpener(JSAny? message, String targetOrigin);

@JS('window.parent.postMessage')
external void _postMessageToParent(JSAny? message, String targetOrigin);

@JS('window.close')
external void _closeWindow();

void notifyAuthWindowAuthenticated() {
  postAuthBridgeMessage({
    'type': 'pokoin-auth-complete',
    'ok': true,
    'status': 'authenticated',
  }, '*');
}

void closeAuthWindow() {
  try {
    _closeWindow();
  } catch (_) {
    // Browsers may block closing tabs that were not script-opened.
  }
}

void postAuthBridgeMessage(Map<String, Object?> payload, String targetOrigin) {
  final json = jsonEncode(payload);
  try {
    _postMessageToOpener(json.toJS, targetOrigin);
  } catch (_) {
    // The bridge can also be embedded in a hidden iframe.
  }
  try {
    _postMessageToParent(json.toJS, targetOrigin);
  } catch (_) {
    // A popup may not have a useful parent.
  }
}
