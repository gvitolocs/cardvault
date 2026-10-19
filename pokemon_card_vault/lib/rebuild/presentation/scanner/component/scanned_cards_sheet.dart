import 'package:flutter/material.dart';
import '../../../controller/scanner_controller.dart';
import '../../../model/scanner.dart';
import '../../../style/scanner_style.dart';
import 'scanned_card_editor.dart';

class ScannedCardsSheet extends StatefulWidget {
  const ScannedCardsSheet(
      {super.key,
      required this.controller,
      required this.onSaved,
      required this.onLogin});
  final ScannerController controller;
  final VoidCallback onSaved, onLogin;
  @override
  State<ScannedCardsSheet> createState() => _ScannedCardsSheetState();
}

class _ScannedCardsSheetState extends State<ScannedCardsSheet> {
  final _sheet = DraggableScrollableController();
  ScannerController get controller => widget.controller;
  VoidCallback get onSaved => widget.onSaved;
  VoidCallback get onLogin => widget.onLogin;
  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_sheet.isAttached) {
      _sheet.animateTo(_sheet.size > .3 ? .16 : .94,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) => DraggableScrollableSheet(
          controller: _sheet,
          initialChildSize: .16,
          minChildSize: .16,
          maxChildSize: .94,
          snap: true,
          snapSizes: const [.16, .55, .94],
          builder: (context, scrollController) => Material(
              color: ScannerStyle.panel,
              shape: ScannerStyle.sheetShape,
              clipBehavior: Clip.antiAlias,
              elevation: 12,
              child: CustomScrollView(controller: scrollController, slivers: [
                SliverToBoxAdapter(
                    child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                        child: Column(children: [
                          Container(
                              width: 38,
                              height: 4,
                              decoration: BoxDecoration(
                                  color: ScannerStyle.muted,
                                  borderRadius: BorderRadius.circular(8))),
                          const SizedBox(height: 8),
                          Row(children: [
                            const Icon(Icons.layers_outlined,
                                color: ScannerStyle.accent),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Text(
                                    'Scansionate · ${controller.quantity}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700))),
                            IconButton(
                                tooltip: 'Ricarica scansioni',
                                onPressed:
                                    controller.busy || !controller.authenticated
                                        ? null
                                        : controller.reload,
                                icon: const Icon(Icons.refresh)),
                            IconButton(
                                tooltip: 'Apri o chiudi carte scansionate',
                                onPressed: _toggle,
                                icon: const Icon(Icons.unfold_more)),
                            const SizedBox(width: 8),
                          ]),
                          const Text('Apri e conferma per salvare il possesso',
                              style: TextStyle(
                                  fontSize: 12, color: ScannerStyle.muted)),
                        ]))),
                if (controller.busy)
                  const SliverToBoxAdapter(child: LinearProgressIndicator()),
                SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                    sliver: SliverList.list(children: [
                      if (controller.message != null)
                        Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(controller.message!,
                                semanticsLabel: controller.message)),
                      if (controller.needsReload)
                        FilledButton.tonal(
                            onPressed:
                                controller.busy ? null : controller.reload,
                            child: const Text('Ricarica e verifica scansioni')),
                      if (controller.pricing)
                        const Padding(
                            padding: EdgeInsets.all(8),
                            child: Text(
                                'Caricamento immagini e prezzi indicativi…')),
                      if (controller.cards.isNotEmpty &&
                          controller.authenticated)
                        FilledButton.icon(
                            onPressed: controller.busy || controller.needsReload
                                ? null
                                : () async {
                                    FocusScope.of(context).unfocus();
                                    if (await controller.save() && mounted) {
                                      onSaved();
                                    }
                                  },
                            icon: const Icon(Icons.check_circle_outline),
                            label: Text(controller.destination ==
                                    ScanDestination.collection
                                ? 'Conferma ${controller.quantity} ${controller.quantity == 1 ? 'carta' : 'carte'} in collezione'
                                : 'Conferma e pubblica ${controller.quantity} carte')),
                      if (!controller.authenticated) ...[
                        const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                                'Accedi per aggiungere le carte alla collezione o ai listing.')),
                        FilledButton(
                            onPressed: onLogin, child: const Text('Accedi')),
                      ] else if (controller.cards.isEmpty)
                        const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                                'Premi Ready e inquadra le carte: i risultati vengono raccolti automaticamente qui.',
                                textAlign: TextAlign.center)),
                      for (final card in controller.cards)
                        ScannedCardEditor(
                            key: ValueKey(card.id),
                            card: card,
                            canRemove: card.isLocal && !controller.busy,
                            enabled: !controller.busy &&
                                !controller.needsReload &&
                                !controller.confirmationPending,
                            requirePrice: controller.destination ==
                                ScanDestination.listing,
                            onCandidate: (candidate) =>
                                controller.chooseCandidate(card.id, candidate),
                            onChanged: controller.edit,
                            onRemove: () => controller.remove(card.id)),
                      if (controller.cards.isNotEmpty) ...[
                        const Padding(
                            padding: EdgeInsets.all(8),
                            child: Text(
                                'Verifica carta, lingua e finitura prima di confermare.')),
                      ],
                    ])),
              ]))));
}
