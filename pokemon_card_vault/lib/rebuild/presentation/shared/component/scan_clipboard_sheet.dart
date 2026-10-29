import 'package:flutter/material.dart';
import '../../../controller/scan_clipboard_controller.dart';
import '../../../model/listing_draft.dart';
import '../atomics/marketplace_thumbnail.dart';

Future<ListingDraft?> showScanClipboardSheet(
        {required BuildContext context,
        required ScanClipboardController controller}) =>
    showModalBottomSheet<ListingDraft>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => ScanClipboardSheet(controller: controller));

class ScanClipboardSheet extends StatelessWidget {
  const ScanClipboardSheet({super.key, required this.controller});
  final ScanClipboardController controller;
  @override
  Widget build(BuildContext context) => SafeArea(
      child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .78,
          child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) {
                final items = [
                  ...controller.items.where((d) => d.pending).toList().reversed,
                  ...controller.items.where((d) => !d.pending).toList().reversed
                ];
                return CustomScrollView(slivers: [
                  SliverToBoxAdapter(
                      child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    'Clipboard · ${controller.pendingCount} da listare',
                                    style:
                                        Theme.of(context).textTheme.titleLarge),
                                const SizedBox(height: 8),
                                const Text(
                                    'Bozze salvate su questo dispositivo. Tocca una carta per controllare il prezzo e preparare il listing.'),
                                if (controller.loading)
                                  const LinearProgressIndicator(),
                                if (controller.error != null)
                                  Text(controller.error!),
                                if (!controller.available &&
                                    !controller.loading)
                                  TextButton(
                                      onPressed: controller.retryLoad,
                                      child: const Text('Riprova Clipboard')),
                                if (controller.message != null)
                                  Text(controller.message!),
                                if (items.isEmpty && controller.available)
                                  const Padding(
                                      padding:
                                          EdgeInsets.symmetric(vertical: 32),
                                      child: Text(
                                          'Nessuna bozza. Trasferisci le carte dalla linguetta dello scanner.')),
                              ]))),
                  SliverList.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final draft = items[index], card = draft.card;
                        return ListTile(
                            leading: MarketplaceThumbnail(
                                imageUrl: card.imageUrl, width: 42, height: 59),
                            title: Text(card.name),
                            subtitle: Text(
                                '${card.number} · ${card.condition} · ${card.language} · ×${card.quantity}\n'
                                '${switch (draft.status) {
                              DraftStatus.published => 'Pubblicata',
                              DraftStatus.publishing =>
                                'Pubblicazione in corso…',
                              DraftStatus.uncertain =>
                                'Pubblicazione da verificare',
                              _ => card.price.isEmpty
                                  ? 'Prezzo da controllare'
                                  : '${card.price} PK · Da controllare / listare',
                            }}'),
                            isThreeLine: true,
                            onTap: () => Navigator.of(context).pop(draft),
                            trailing: IconButton(
                                tooltip: 'Rimuovi bozza ${card.name}',
                                onPressed:
                                    draft.status == DraftStatus.publishing
                                        ? null
                                        : () => controller.remove(draft.id),
                                icon: const Icon(Icons.close)));
                      }),
                ]);
              })));
}
