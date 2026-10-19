import 'dart:async';
import 'package:flutter/material.dart';

import '../../../controller/cart_controller.dart';
import '../price_format.dart';
import '../atomics/marketplace_thumbnail.dart';

/// Apre la presentazione del carrello, senza introdurre UI nel service.
Future<void> showMarketplaceCartSheet({
  required BuildContext context,
  required CartController controller,
}) {
  unawaited(controller.refresh());
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => MarketplaceCartSheet(controller: controller),
  );
}

class MarketplaceCartSheet extends StatelessWidget {
  const MarketplaceCartSheet({super.key, required this.controller});

  final CartController controller;

  String _price(double value) =>
      '${value.toStringAsFixed(2).replaceAll('.', ',')} €';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final items = controller.items;
        final listings = controller.listingItems;
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Carrello',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                if (controller.isLoading) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  const Text('Recupero del carrello…'),
                ] else if (controller.isPersistent && controller.error == null)
                  Text(controller.isSaving
                      ? 'Salvataggio sul dispositivo…'
                      : controller.isSyncing
                          ? 'Sincronizzazione del carrello…'
                          : controller.isGuest
                              ? 'Carrello ospite · salvato su questo dispositivo'
                              : controller.hasPendingChanges
                                  ? 'Modifiche da sincronizzare'
                                  : 'Carrello sincronizzato con il tuo account'),
                if (controller.error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(controller.error!,
                            semanticsLabel: controller.error),
                        TextButton(
                            onPressed: controller.retry,
                            child: const Text('Riprova carrello')),
                      ],
                    ),
                  ),
                if (items.isEmpty && listings.isEmpty && controller.canEdit)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('Il tuo carrello è vuoto. Esplora le carte!'),
                  ),
                for (final item in listings)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  MarketplaceThumbnail(
                                      imageUrl: item.card.imageUrl,
                                      width: 48,
                                      height: 68),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: Text(item.card.name,
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium)),
                                ]),
                            Text(
                                '${item.listing.sellerName} · ${item.listing.condition} · ${item.listing.language}'),
                            Text(
                                '${item.quantity} × ${pknPrice(item.listing.pricePkn)}'),
                            if (!item.listing.isAvailable ||
                                item.quantity > item.listing.stock)
                              const Text(
                                  'Disponibilità da verificare prima dell’acquisto.'),
                            Row(children: [
                              IconButton(
                                  tooltip: 'Diminuisci ${item.card.name}',
                                  onPressed: controller.canEdit
                                      ? () => controller
                                          .decreaseListing(item.listing.id)
                                      : null,
                                  icon: const Icon(Icons.remove)),
                              Text('${item.quantity}'),
                              IconButton(
                                  tooltip: 'Aumenta ${item.card.name}',
                                  onPressed: !controller.canEdit ||
                                          !item.listing.isAvailable ||
                                          item.quantity >= item.listing.stock
                                      ? null
                                      : () => controller.addListing(
                                          item.card, item.listing),
                                  icon: const Icon(Icons.add)),
                              const Spacer(),
                              IconButton(
                                  tooltip: 'Rimuovi offerta ${item.listing.id}',
                                  onPressed: controller.canEdit
                                      ? () => controller
                                          .removeListing(item.listing.id)
                                      : null,
                                  icon: const Icon(Icons.delete_outline)),
                            ]),
                          ])),
                if (listings.isNotEmpty) ...[
                  const Divider(),
                  Text('Totale carte: ${pknPrice(controller.totalPkn)}',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text(
                      'Prezzi e disponibilità sono quelli delle offerte salvate. Spedizione e totale finale vanno verificati al checkout; acquisto non ancora collegato.'),
                ],
                if (items.isNotEmpty && listings.isNotEmpty)
                  const Padding(
                      padding: EdgeInsets.only(top: 20),
                      child: Text('Articoli demo · totale separato')),
                for (final item in items)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(item.card.icon, color: item.card.color),
                    title: Text(item.card.name),
                    subtitle:
                        Text('${item.quantity} × ${_price(item.card.price)}'),
                    trailing: IconButton(
                      tooltip: 'Rimuovi ${item.card.name}',
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () => controller.removeCard(item.card.id),
                    ),
                  ),
                if (items.isNotEmpty) ...[
                  const Divider(),
                  Text('Totale di esempio: ${_price(controller.totalPrice)}',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  const Text('Demo: nessun acquisto verrà effettuato.'),
                ],
                if (items.isNotEmpty || listings.isNotEmpty)
                  Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                          onPressed:
                              controller.canEdit ? controller.clear : null,
                          icon: const Icon(Icons.remove_shopping_cart_outlined),
                          label: const Text('Svuota carrello'))),
              ],
            ),
          ),
        );
      },
    );
  }
}
