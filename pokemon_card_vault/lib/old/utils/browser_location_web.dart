import 'package:web/web.dart' as web;

Uri? currentBrowserUri() {
  final location = web.window.location;
  return Uri.tryParse(
    '${location.protocol}//${location.host}${location.pathname}'
    '${location.search}${location.hash}',
  );
}

void assignPublicHome() {
  web.window.location.assign('/');
}
