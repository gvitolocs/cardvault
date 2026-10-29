import 'package:flutter/widgets.dart';
import '../../../controller/app_appearance_controller.dart';

class AppAppearanceScope extends InheritedNotifier<AppAppearanceController> {
  const AppAppearanceScope(
      {super.key,
      required AppAppearanceController controller,
      required super.child})
      : super(notifier: controller);
  static AppAppearanceController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AppAppearanceScope>()
      ?.notifier;
}
