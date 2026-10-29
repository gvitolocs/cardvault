import 'package:flutter/material.dart';
import '../../../controller/scan_clipboard_controller.dart';
import '../atomics/themed_icon.dart';
import '../../../style/app_theme_icons.dart';

class ScanClipboardButton extends StatelessWidget {
  const ScanClipboardButton(
      {super.key, required this.controller, required this.onPressed});
  final ScanClipboardController controller;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) => IconButton(
          tooltip:
              'Clipboard · ${controller.pendingCount} da controllare o listare',
          onPressed: onPressed,
          icon: TweenAnimationBuilder<double>(
              key: ValueKey(controller.transferRevision),
              tween: Tween(
                  begin: controller.transferRevision == 0 ? 1 : 1.35, end: 1),
              duration: const Duration(milliseconds: 500),
              curve: Curves.elasticOut,
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: Badge(
                  isLabelVisible: controller.pendingCount > 0,
                  label: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: Text('${controller.pendingCount}',
                          key: ValueKey(controller.pendingCount))),
                  child: const ThemedIcon(
                      slot: AppThemeIcon.clipboard,
                      fallback: Icons.content_paste_outlined)))));
}
