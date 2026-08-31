import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'browser_location.dart';

/// Production `/` is the static marketing page. Punch out of the Flutter SPA.
void goPublicHome(BuildContext context) {
  if (kIsWeb) {
    final host = Uri.base.host;
    if (host == 'explorer.pokoin.com' || host == 'forum.pokoin.com') {
      context.go('/');
      return;
    }
    assignPublicHome();
    return;
  }
  context.go('/');
}
