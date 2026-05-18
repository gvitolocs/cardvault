import 'package:web/web.dart' as web;

bool hasDesktopPointer() {
  return web.window.matchMedia('(hover: hover) and (pointer: fine)').matches;
}
