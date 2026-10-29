import 'dart:async';
import 'package:flutter/material.dart';
import '../../../constants/app_appearance_constants.dart';
import '../../../controller/app_appearance_controller.dart';
import '../../../model/app_appearance.dart';
import '../../shared/component/app_appearance_scope.dart';

/// Available to guests too: a visual preference does not require an account.
class AppearanceSettings extends StatelessWidget {
  const AppearanceSettings({super.key});
  @override
  Widget build(BuildContext context) {
    final controller = AppAppearanceScope.maybeOf(context);
    if (controller == null) return const SizedBox.shrink();
    return IconButton(
        tooltip: 'Tema dell’app: ${appAppearanceLabels[controller.appearance]}'
            '${controller.feedback == null ? '' : '\n${controller.feedback}'}',
        icon: Icon(Icons.palette_outlined,
            color: Theme.of(context).colorScheme.primary),
        onPressed: () => _choose(context, controller));
  }

  void _choose(BuildContext context, AppAppearanceController controller) {
    showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
            child: SingleChildScrollView(
                child: ListenableBuilder(
                    listenable: controller,
                    builder: (_, __) =>
                        Column(mainAxisSize: MainAxisSize.min, children: [
                          Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text('Tema dell’app',
                                  style:
                                      Theme.of(context).textTheme.titleLarge)),
                          for (final appearance in AppAppearance.values)
                            ListTile(
                                key: ValueKey('appearance-${appearance.id}'),
                                title: Text(appAppearanceLabels[appearance]!),
                                subtitle: Text(
                                    appAppearanceDescriptions[appearance]!),
                                leading: Icon(
                                    appearance == AppAppearance.dungeonCrawler
                                        ? Icons.explore_outlined
                                        : Icons.palette_outlined),
                                trailing: controller.appearance == appearance
                                    ? const Icon(Icons.check_rounded)
                                    : null,
                                onTap: () {
                                  unawaited(controller.select(appearance));
                                  Navigator.of(sheetContext).pop();
                                }),
                          const SizedBox(height: 16),
                        ])))));
  }
}
