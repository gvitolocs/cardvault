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
      required this.onLogin,
      this.onOpenCard});
  final ScannerController controller;
  final VoidCallback onSaved, onLogin;
  final Future<void> Function(ScannedCard)? onOpenCard;
  @override
  State<ScannedCardsSheet> createState() => _ScannedCardsSheetState();
}

class _ScannedCardsSheetState extends State<ScannedCardsSheet> {
  final _sheet = DraggableScrollableController();
  ScannerController get controller => widget.controller;
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
                                tooltip: 'Apri o chiudi carte scansionate',
                                onPressed: _toggle,
                                icon: const Icon(Icons.unfold_more)),
                          ]),
                          const Text(
                              'Controlla le carte e trasferiscile in Clipboard',
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
                            child: Text(controller.message!)),
                      if (controller.pricing)
                        const Padding(
                            padding: EdgeInsets.all(8),
                            child: Text(
                                'Caricamento immagini e prezzi indicativi…')),
                      if (controller.cards.isNotEmpty) ...[
                        const Tooltip(
                            message:
                                'Salvataggio diretto temporaneamente indisponibile',
                            child: OutlinedButton(
                                onPressed: null, child: Text('Save'))),
                        FilledButton.icon(
                            onPressed: controller.busy
                                ? null
                                : () async {
                                    FocusScope.of(context).unfocus();
                                    await controller.copyToClipboard();
                                  },
                            icon: const Icon(Icons.content_paste_outlined),
                            label: const Text('Copy to Clipboard')),
                        const SizedBox(height: 12),
                      ] else
                        const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                                'Premi Ready e inquadra le carte: i risultati vengono raccolti qui.',
                                textAlign: TextAlign.center)),
                      for (final card in controller.cards)
                        ScannedCardEditor(
                            key: ValueKey(card.id),
                            card: card,
                            canRemove: !controller.busy,
                            enabled: !controller.busy,
                            requirePrice: false,
                            onOpen: widget.onOpenCard == null || controller.busy
                                ? null
                                : () => widget.onOpenCard!(card),
                            onCandidate: (candidate) =>
                                controller.chooseCandidate(card.id, candidate),
                            onChanged: controller.edit,
                            onRemove: () => controller.remove(card.id)),
                      if (controller.cards.isNotEmpty)
                        const Padding(
                            padding: EdgeInsets.all(8),
                            child: Text(
                                'Le bozze in Clipboard restano disponibili dopo la chiusura dell’app. Nessuna pubblicazione automatica.')),
                    ])),
              ]))));
}
