import 'dart:convert';
import 'dart:js_interop';

@JS('window.opener.postMessage')
external void _postMessageToOpener(JSAny? message, String targetOrigin);

@JS('window.parent.postMessage')
external void _postMessageToParent(JSAny? message, String targetOrigin);

@JS('window.close')
external void _closeWindow();

void notifyAuthWindowAuthenticated() {
  final message = jsonEncode({
    'type': 'pokoin-auth-complete',
    'ok': true,
    'status': 'authenticated',
  });
  try {
    _postMessageToOpener(message.toJS, '*');
  } catch (_) {
    // The auth page may have been opened as a normal tab without an opener.
  }
  try {
    _postMessageToParent(message.toJS, '*');
  } catch (_) {
    // A popup may not have a useful parent.
  }
}

void closeAuthWindow() {
  try {
    _closeWindow();
  } catch (_) {
    // Browsers may block closing tabs that were not script-opened.
  }
}
