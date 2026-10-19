import 'package:flutter/material.dart';
import '../../../constants/scanner_constants.dart';
import '../../../model/scanner.dart';
import '../../shared/atomics/marketplace_thumbnail.dart';

class ScannedCardEditor extends StatefulWidget {
  const ScannedCardEditor(
      {super.key,
      required this.card,
      required this.enabled,
      required this.requirePrice,
      required this.onChanged,
      this.onCandidate,
      this.canRemove = false,
      required this.onRemove});
  final ScannedCard card;
  final bool enabled, requirePrice;
  final bool canRemove;
  final ValueChanged<ScannedCard> onChanged;
  final ValueChanged<ScannerCandidate>? onCandidate;
  final VoidCallback onRemove;
  @override
  State<ScannedCardEditor> createState() => _ScannedCardEditorState();
}

class _ScannedCardEditorState extends State<ScannedCardEditor> {
  late final _price = TextEditingController(text: widget.card.price);
  @override
  void didUpdateWidget(ScannedCardEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_price.text != widget.card.price) _price.text = widget.card.price;
  }

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    Widget dropdown(String label, String value, Map<String, String> values,
            ValueChanged<String> onChanged) =>
        DropdownButtonFormField<String>(
            // The key makes a server reload update the FormField's internal value.
            key: ValueKey('${card.id}:$label:$value'),
            initialValue: value,
            isExpanded: true,
            decoration: InputDecoration(labelText: label, isDense: true),
            items: {if (!values.containsKey(value)) value: value, ...values}
                .entries
                .map((e) => DropdownMenuItem(
                    value: e.key,
                    child: Text(e.value, overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: widget.enabled
                ? (value) {
                    if (value != null) onChanged(value);
                  }
                : null);
    return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(children: [
              Row(children: [
                MarketplaceThumbnail(
                    imageUrl: card.imageUrl, width: 48, height: 68),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(card.name,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(
                          [card.number, card.setName]
                              .where((s) => s.isNotEmpty)
                              .join(' · '),
                          style: Theme.of(context).textTheme.bodySmall),
                    ])),
                IconButton(
                    tooltip: 'Rimuovi ${card.name}',
                    onPressed: widget.enabled || widget.canRemove
                        ? widget.onRemove
                        : null,
                    icon: const Icon(Icons.close)),
              ]),
              const SizedBox(height: 12),
              if (card.alternatives.isNotEmpty)
                ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                        'Risultati · scegli tra i primi ${card.alternatives.length}'),
                    children: [
                      for (final candidate in card.alternatives)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(candidate.cardId == card.cardId
                              ? Icons.check_circle
                              : Icons.circle_outlined),
                          title: Text(candidate.name),
                          subtitle: Text(
                              '${candidate.number} · ${candidate.setName}'),
                          trailing: Text('${(candidate.score * 100).round()}%'),
                          onTap: widget.enabled && widget.onCandidate != null
                              ? () => widget.onCandidate!(candidate)
                              : null,
                        )
                    ]),
              LayoutBuilder(builder: (context, constraints) {
                final fields = [
                  dropdown('Condizione', card.condition, scannerConditions,
                      (value) => widget.onChanged(card.edit(condition: value))),
                  dropdown('Lingua', card.language, scannerLanguages,
                      (value) => widget.onChanged(card.edit(language: value))),
                ];
                if (constraints.maxWidth < 330 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.3) {
                  return Column(children: [
                    fields[0],
                    const SizedBox(height: 12),
                    fields[1]
                  ]);
                }
                return Row(children: [
                  Expanded(child: fields[0]),
                  const SizedBox(width: 10),
                  Expanded(child: fields[1])
                ]);
              }),
              const SizedBox(height: 12),
              dropdown(
                  'Finitura',
                  card.foilState,
                  const {
                    'standard': 'Standard',
                    'holo': 'Holo',
                    'reverse': 'Reverse',
                    'stamped': 'Stamped',
                    'promo': 'Promo',
                    'other': 'Altra'
                  },
                  (value) => widget.onChanged(card.edit(foilState: value))),
              const SizedBox(height: 12),
              Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                        width: 150,
                        child: TextField(
                            controller: _price,
                            enabled: widget.enabled,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: InputDecoration(
                                labelText: 'Prezzo PK',
                                hintText:
                                    card.suggestedPrice?.toStringAsFixed(2),
                                helperText: card.priceSuggested
                                    ? 'Suggerito dal mercato'
                                    : widget.requirePrice
                                        ? 'Obbligatorio'
                                        : 'Facoltativo',
                                errorText:
                                    (card.price.isNotEmpty && !card.validPrice)
                                        ? 'Prezzo non valido'
                                        : null),
                            onChanged: (value) =>
                                widget.onChanged(card.edit(price: value)))),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                          tooltip: 'Diminuisci quantità',
                          onPressed: widget.enabled && card.quantity > 1
                              ? () => widget.onChanged(
                                  card.edit(quantity: card.quantity - 1))
                              : null,
                          icon: const Icon(Icons.remove_circle_outline)),
                      Semantics(
                          label: 'Quantità ${card.quantity}',
                          child: Text('×${card.quantity}')),
                      IconButton(
                          tooltip: 'Aumenta quantità',
                          onPressed: widget.enabled && card.quantity < 99
                              ? () => widget.onChanged(
                                  card.edit(quantity: card.quantity + 1))
                              : null,
                          icon: const Icon(Icons.add_circle_outline)),
                    ]),
                  ]),
              if (card.suggestedPrice != null && !card.priceSuggested)
                TextButton.icon(
                    onPressed: widget.enabled
                        ? () => widget.onChanged(card.edit(
                            price: card.suggestedPrice!.toStringAsFixed(2)))
                        : null,
                    icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                    label: Text(
                        'Usa prezzo indicativo: ${card.suggestedPrice!.toStringAsFixed(2)} PK')),
            ])));
  }
}
