import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/pokemon_card.dart';
import '../models/user_card_collection_item.dart';
import '../providers/card_provider.dart';
import '../providers/marketplace_account_provider.dart';
import '../providers/user_card_collection_provider.dart';
import '../utils/card_navigation.dart';

class NftScreen extends ConsumerWidget {
  const NftScreen({super.key, this.cardId});

  final String? cardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collection = ref.watch(userCardCollectionProvider);
    final cardState = ref.watch(cardProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: collection.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _NftShell(
                children: [
                  _NftHeader(
                    nftCount: 0,
                    onBack: () => context.go('/profile'),
                    onCollection: () => context.go('/collection'),
                  ),
                  const SizedBox(height: 18),
                  _EmptyPanel(message: 'NFT collection failed to load: $error'),
                ],
              ),
              data: (items) {
                final nfts = items.where((item) => item.isNft).toList();
                final selected = _selectedNft(nfts);
                final selectedCard = _selectedCard(cardState.cards, selected);
                final shippable = nfts
                    .where((item) => item.canRequestPhysicalShipping)
                    .toList();
                return _NftShell(
                  children: [
                    _NftHeader(
                      nftCount: nfts.length,
                      onBack: () => context.go('/profile'),
                      onCollection: () => context.go('/collection'),
                    ),
                    const SizedBox(height: 18),
                    _NftFulfillmentPanel(
                      eligibleCount: shippable.length,
                      onRequestAll: shippable.isEmpty
                          ? null
                          : () => _showShippingRequestDialog(
                              context, ref, shippable),
                    ),
                    const SizedBox(height: 18),
                    if (nfts.isEmpty)
                      const _EmptyPanel(
                        message:
                            'NFT-only purchases will appear here after checkout. Physical shipping can be requested from this page later.',
                      )
                    else
                      _NftGrid(
                        items: nfts,
                        selectedId: selected?.id ?? '',
                        cards: cardState.cards,
                        onRequestShipping: (item) =>
                            _showShippingRequestDialog(context, ref, [item]),
                      ),
                    if (selected != null) ...[
                      const SizedBox(height: 18),
                      _NftDetailPanel(item: selected, card: selectedCard),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  UserCardCollectionItem? _selectedNft(List<UserCardCollectionItem> items) {
    final id = cardId?.trim();
    if (id == null || id.isEmpty) return items.isEmpty ? null : items.first;
    for (final item in items) {
      if (item.cardId == id || item.id == id) return item;
    }
    return items.isEmpty ? null : items.first;
  }

  PokemonCard? _selectedCard(
    List<PokemonCard> cards,
    UserCardCollectionItem? item,
  ) {
    if (item == null) return null;
    for (final card in cards) {
      if (card.id == item.cardId) return card;
    }
    return null;
  }

  void _showShippingRequestDialog(
    BuildContext context,
    WidgetRef ref,
    List<UserCardCollectionItem> items,
  ) {
    final name = TextEditingController();
    final line1 = TextEditingController();
    final line2 = TextEditingController();
    final city = TextEditingController();
    final region = TextEditingController();
    final postalCode = TextEditingController();
    final country = TextEditingController();
    final phone = TextEditingController();
    final notes = TextEditingController();
    var busy = false;

    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: const Color(0xF20B1020),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      items.length == 1
                          ? 'Request physical card'
                          : 'Request all physical cards',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'This creates a pending ops request only. It does not charge PKN or trigger an external shipment.',
                      style: TextStyle(color: Color(0xFFB8C4E6), height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    _NftTextField(controller: name, label: 'Full name'),
                    _NftTextField(controller: line1, label: 'Address line 1'),
                    _NftTextField(controller: line2, label: 'Address line 2'),
                    Row(
                      children: [
                        Expanded(
                          child: _NftTextField(controller: city, label: 'City'),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _NftTextField(
                              controller: region, label: 'Region'),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _NftTextField(
                            controller: postalCode,
                            label: 'Postal code',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _NftTextField(
                            controller: country,
                            label: 'Country',
                          ),
                        ),
                      ],
                    ),
                    _NftTextField(controller: phone, label: 'Phone optional'),
                    _NftTextField(
                      controller: notes,
                      label: 'Notes optional',
                      maxLines: 3,
                    ),
                    if (busy) const LinearProgressIndicator(minHeight: 3),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 10,
                      alignment: WrapAlignment.end,
                      children: [
                        TextButton(
                          onPressed: busy ? null : () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        FilledButton.icon(
                          onPressed: busy
                              ? null
                              : () async {
                                  setState(() => busy = true);
                                  try {
                                    final address = {
                                      'name': name.text,
                                      'line1': line1.text,
                                      'line2': line2.text,
                                      'city': city.text,
                                      'region': region.text,
                                      'postalCode': postalCode.text,
                                      'country': country.text,
                                      'phone': phone.text,
                                    };
                                    if (items.length == 1) {
                                      await ref
                                          .read(
                                              marketplaceAccountServiceProvider)
                                          .requestNftPhysicalShipping(
                                            collectionItemId: items.first.id,
                                            shippingAddress: address,
                                            notes: notes.text,
                                          );
                                    } else {
                                      await ref
                                          .read(
                                              marketplaceAccountServiceProvider)
                                          .requestAllNftPhysicalShipping(
                                            collectionItemIds: items
                                                .map((item) => item.id)
                                                .toList(),
                                            shippingAddress: address,
                                            notes: notes.text,
                                          );
                                    }
                                    ref.invalidate(userCardCollectionProvider);
                                    if (context.mounted) {
                                      Navigator.pop(context);
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Physical shipping request saved for ops review.',
                                          ),
                                          backgroundColor: Color(0xFFFACC15),
                                        ),
                                      );
                                    }
                                  } catch (error) {
                                    setState(() => busy = false);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text('$error'),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  }
                                },
                          icon: const Icon(Icons.local_shipping_outlined),
                          label: const Text('Save request'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      name.dispose();
      line1.dispose();
      line2.dispose();
      city.dispose();
      region.dispose();
      postalCode.dispose();
      country.dispose();
      phone.dispose();
      notes.dispose();
    });
  }
}

class _NftShell extends StatelessWidget {
  const _NftShell({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(22), children: children);
  }
}

class _NftHeader extends StatelessWidget {
  const _NftHeader({
    required this.nftCount,
    required this.onBack,
    required this.onCollection,
  });

  final int nftCount;
  final VoidCallback onBack;
  final VoidCallback onCollection;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'My NFT cards',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                '$nftCount owned NFT card${nftCount == 1 ? '' : 's'} with optional physical shipping requests.',
                style: const TextStyle(color: Color(0xFF93A4C8)),
              ),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: onCollection,
          icon: const Icon(Icons.collections_bookmark_outlined),
          label: const Text('Collection'),
        ),
      ],
    );
  }
}

class _NftFulfillmentPanel extends StatelessWidget {
  const _NftFulfillmentPanel({
    required this.eligibleCount,
    required this.onRequestAll,
  });

  final int eligibleCount;
  final VoidCallback? onRequestAll;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Wrap(
        spacing: 14,
        runSpacing: 14,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const SizedBox(
            width: 620,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NFT custody first, shipping later',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'NFT-only checkout skips shipping. When you want the real cards, submit a pending request for ops review from here.',
                  style: TextStyle(color: Color(0xFFB8C4E6), height: 1.45),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: onRequestAll,
            icon: const Icon(Icons.local_shipping_outlined),
            label: Text('Request all eligible ($eligibleCount)'),
          ),
        ],
      ),
    );
  }
}

class _NftGrid extends StatelessWidget {
  const _NftGrid({
    required this.items,
    required this.selectedId,
    required this.cards,
    required this.onRequestShipping,
  });

  final List<UserCardCollectionItem> items;
  final String selectedId;
  final List<PokemonCard> cards;
  final ValueChanged<UserCardCollectionItem> onRequestShipping;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 1000
            ? 4
            : constraints.maxWidth > 720
                ? 3
                : constraints.maxWidth > 460
                    ? 2
                    : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            mainAxisExtent: 360,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            final card = _cardForItem(cards, item);
            return _NftCard(
              item: item,
              card: card,
              selected: item.id == selectedId,
              onRequestShipping: item.canRequestPhysicalShipping
                  ? () => onRequestShipping(item)
                  : null,
            );
          },
        );
      },
    );
  }

  PokemonCard? _cardForItem(
      List<PokemonCard> cards, UserCardCollectionItem item) {
    for (final card in cards) {
      if (card.id == item.cardId) return card;
    }
    return null;
  }
}

class _NftCard extends StatelessWidget {
  const _NftCard({
    required this.item,
    required this.card,
    required this.selected,
    required this.onRequestShipping,
  });

  final UserCardCollectionItem item;
  final PokemonCard? card;
  final bool selected;
  final VoidCallback? onRequestShipping;

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.cardImageUrl.trim().isNotEmpty
        ? item.cardImageUrl.trim()
        : card?.previewImageUrl ?? '';
    return InkWell(
      onTap: card == null
          ? null
          : () => navigateToCanonicalCardDetail(
                context,
                card!,
                source: 'nft_collection_card',
              ),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xDD0B1020),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected
                ? const Color(0xFFFACC15).withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _NftImage(imageUrl: imageUrl)),
            const SizedBox(height: 10),
            Text(
              item.cardName.isEmpty ? item.cardId : item.cardName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${item.setName} ${item.collectorNumber}'.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF93A4C8), fontSize: 12),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                const _Badge(text: 'NFT'),
                _Badge(text: _shippingStatusLabel(item.physicalShippingStatus)),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onRequestShipping,
              icon: const Icon(Icons.local_shipping_outlined, size: 17),
              label: const Text('Request shipping'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NftDetailPanel extends StatelessWidget {
  const _NftDetailPanel({required this.item, required this.card});

  final UserCardCollectionItem item;
  final PokemonCard? card;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Wrap(
        spacing: 18,
        runSpacing: 18,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 150,
            height: 200,
            child: _NftImage(imageUrl: item.cardImageUrl),
          ),
          SizedBox(
            width: 680,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.cardName.isEmpty ? 'Owned NFT card' : item.cardName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${item.setName} ${item.collectorNumber}'.trim(),
                  style: const TextStyle(color: Color(0xFFB8C4E6)),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _Metric(
                      label: 'NFT status',
                      value: item.nftStatus.isEmpty ? 'Owned' : item.nftStatus,
                    ),
                    _Metric(
                      label: 'Shipping',
                      value: _shippingStatusLabel(item.physicalShippingStatus),
                    ),
                    _Metric(
                      label: 'Order',
                      value:
                          item.sourceOrderId.isEmpty ? '-' : item.sourceOrderId,
                    ),
                  ],
                ),
                if (card != null) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => navigateToCanonicalCardDetail(
                      context,
                      card!,
                      source: 'nft_detail_button',
                    ),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Open card detail'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NftImage extends StatelessWidget {
  const _NftImage({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final resolved = imageUrl.trim();
    if (resolved.isEmpty) {
      return const Icon(Icons.hexagon_outlined,
          color: Color(0xFFFACC15), size: 54);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.network(
        resolved,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.style, color: Color(0xFFFACC15), size: 48),
      ),
    );
  }
}

class _NftTextField extends StatelessWidget {
  const _NftTextField({
    required this.controller,
    required this.label,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Color(0xFF93A4C8)),
          filled: true,
          fillColor: const Color(0xFF111936),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFFACC15)),
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF93A4C8), fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0x1AFACC15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x44FACC15)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFFFDE68A),
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xDD0B1020),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: child,
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFFB8C4E6), height: 1.45),
      ),
    );
  }
}

String _shippingStatusLabel(String value) {
  final clean = value.trim();
  if (clean.isEmpty || clean == 'not_requested') return 'Not shipped';
  return clean.replaceAll('_', ' ');
}
