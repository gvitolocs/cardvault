import 'package:flutter/material.dart';
import '../../../style/card_details_style.dart';
import '../atomics/card_details_panel.dart';
import '../atomics/detail_fields.dart';
import '../atomics/detail_dropdown.dart';

/// Solo bozza locale: nessuna pubblicazione e nessuna operazione sul carrello.
class CardListingComposer extends StatefulWidget {
  const CardListingComposer({super.key, required this.onPreview});
  final VoidCallback onPreview;

  @override
  State<CardListingComposer> createState() => _CardListingComposerState();
}

class _CardListingComposerState extends State<CardListingComposer> {
  final _form = GlobalKey<FormState>();
  bool _expanded = true;
  String _currency = 'PKN',
      _condition = 'NM',
      _language = 'IT',
      _finish = 'Standard',
      _location = 'Nessuna';
  final _attributes = <String>{'Spedizione'};

  void _toggle() {
    if (_expanded) FocusScope.of(context).unfocus();
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) => CardDetailsPanel(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Semantics(
            button: true,
            expanded: _expanded,
            child: Tooltip(
              message: _expanded
                  ? 'Richiudi modulo di vendita'
                  : 'Apri modulo di vendita',
              child: InkWell(
                onTap: _toggle,
                borderRadius: BorderRadius.circular(12),
                child: Row(children: [
                  Expanded(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Vendi la tua carta',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      const Text('Bozza dimostrativa',
                          style: TextStyle(color: CardDetailsStyle.muted)),
                    ],
                  )),
                  SizedBox(
                      width: 48,
                      height: 48,
                      child: AnimatedRotation(
                          turns: _expanded ? .5 : 0,
                          duration: const Duration(milliseconds: 220),
                          child: const Icon(Icons.expand_more,
                              color: CardDetailsStyle.yellow))),
                ]),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            alignment: Alignment.topCenter,
            child: Visibility(
              visible: _expanded,
              maintainState: true,
              child: Form(
                key: _form,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 16),
                      DetailFields(children: [
                        TextFormField(
                            initialValue: '190',
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration:
                                const InputDecoration(labelText: 'Prezzo'),
                            validator: (value) {
                              final price = double.tryParse(
                                  (value ?? '').replaceAll(',', '.'));
                              return price == null ||
                                      !price.isFinite ||
                                      price <= 0
                                  ? 'Inserisci un prezzo valido'
                                  : null;
                            }),
                        DetailDropdown(
                            label: 'Valuta',
                            value: _currency,
                            values: const ['PKN', 'EUR'],
                            onChanged: (value) =>
                                setState(() => _currency = value)),
                        TextFormField(
                            initialValue: '1',
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(labelText: 'Quantità'),
                            validator: (value) =>
                                (int.tryParse(value ?? '') ?? 0) < 1
                                    ? 'Minimo 1'
                                    : null),
                      ]),
                      const SizedBox(height: 12),
                      const Wrap(spacing: 8, runSpacing: 8, children: [
                        Chip(
                            label: Text('Pokoin'),
                            avatar: Icon(Icons.check, size: 18)),
                        Tooltip(
                            message:
                                'Collegamento CardTrader non ancora disponibile',
                            child: Chip(
                                label: Text('CardTrader'),
                                avatar: Icon(Icons.link_off, size: 18))),
                      ]),
                      const SizedBox(height: 12),
                      DetailFields(children: [
                        DetailDropdown(
                            label: 'Condizione',
                            value: _condition,
                            values: const ['PO', 'PL', 'MP', 'SP', 'NM'],
                            onChanged: (value) =>
                                setState(() => _condition = value)),
                        DetailDropdown(
                            label: 'Lingua',
                            value: _language,
                            values: const ['IT', 'EN', 'FR', 'DE', 'ES', 'PT'],
                            onChanged: (value) =>
                                setState(() => _language = value)),
                        DetailDropdown(
                            label: 'Versione',
                            value: _finish,
                            values: const ['Standard', 'Holo', 'Reverse'],
                            onChanged: (value) =>
                                setState(() => _finish = value)),
                      ]),
                      const SizedBox(height: 12),
                      Wrap(spacing: 8, runSpacing: 6, children: [
                        for (final attribute in const [
                          '1ª ed.',
                          'Sigillata',
                          'Gradata',
                          'Spedizione'
                        ])
                          FilterChip(
                              label: Text(attribute),
                              selected: _attributes.contains(attribute),
                              onSelected: (selected) => setState(() {
                                    selected
                                        ? _attributes.add(attribute)
                                        : _attributes.remove(attribute);
                                  })),
                        IconButton.outlined(
                            tooltip: 'Aggiungi foto',
                            onPressed: () => ScaffoldMessenger.of(context)
                                .showSnackBar(const SnackBar(
                                    content: Text(
                                        'Le foto saranno disponibili con la pubblicazione degli annunci.'))),
                            icon: const Icon(Icons.camera_alt_outlined)),
                      ]),
                      const SizedBox(height: 16),
                      DetailDropdown(
                          label: 'Posizione',
                          value: _location,
                          values: const ['Nessuna', 'Italia'],
                          onChanged: (value) =>
                              setState(() => _location = value)),
                      const SizedBox(height: 12),
                      TextFormField(
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                              labelText: 'Commento del venditore')),
                      const SizedBox(height: 16),
                      FilledButton(
                          onPressed: () {
                            if (_form.currentState!.validate()) {
                              widget.onPreview();
                            }
                          },
                          child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Text('Anteprima annuncio',
                                  textAlign: TextAlign.center))),
                    ]),
              ),
            ),
          ),
        ]),
      );
}
