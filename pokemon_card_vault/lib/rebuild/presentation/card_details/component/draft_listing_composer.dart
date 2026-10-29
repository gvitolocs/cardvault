import 'dart:async';
import 'package:flutter/material.dart';
import '../../../constants/scanner_constants.dart';
import '../../../constants/seller_country_constants.dart';
import '../../../controller/scan_clipboard_controller.dart';
import '../../../model/listing_draft.dart';
import '../atomics/card_details_panel.dart';
import '../atomics/detail_fields.dart';

/// Every field edits the local draft; only the explicit Publish button writes remotely.
class DraftListingComposer extends StatefulWidget {
  const DraftListingComposer(
      {super.key,
      required this.controller,
      required this.draftId,
      required this.onLogin,
      this.sellerName = 'Pokoin seller'});
  final ScanClipboardController controller;
  final String draftId, sellerName;
  final VoidCallback onLogin;
  @override
  State<DraftListingComposer> createState() => _DraftListingComposerState();
}

class _DraftListingComposerState extends State<DraftListingComposer> {
  bool _publishing = false;
  int? _countryScope;
  void _edit(ListingDraft Function(ListingDraft) change) =>
      unawaited(widget.controller.edit(widget.draftId, change));
  Future<void> _publish() async {
    if (_publishing) return;
    FocusScope.of(context).unfocus();
    setState(() => _publishing = true);
    try {
      await widget.controller
          .publish(widget.draftId, sellerName: widget.sellerName);
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final draft = widget.controller.find(widget.draftId);
        if (draft == null) {
          return const CardDetailsPanel(
              child: Text('Bozza non disponibile in questa Clipboard.'));
        }
        if (widget.controller.authenticated &&
            _countryScope != widget.controller.scopeRevision) {
          _countryScope = widget.controller.scopeRevision;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              unawaited(widget.controller.loadSellerCountry(widget.draftId));
            }
          });
        }
        final card = draft.card;
        final enabled = draft.editable && !_publishing;
        Widget text(String label, String value, ValueChanged<String> onChanged,
                {bool numeric = false}) =>
            TextFormField(
                key: ValueKey('${draft.id}:$label'),
                initialValue: value,
                enabled: enabled,
                keyboardType: numeric
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : TextInputType.text,
                decoration: InputDecoration(labelText: label),
                onChanged: onChanged);
        Widget dropdown(String label, String value, Map<String, String> values,
                ValueChanged<String> onChanged) =>
            DropdownButtonFormField<String>(
                key: ValueKey('${draft.id}:$label:$value'),
                initialValue: value,
                isExpanded: true,
                decoration: InputDecoration(labelText: label),
                items: {if (!values.containsKey(value)) value: value, ...values}
                    .entries
                    .map((e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value, overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: enabled
                    ? (value) {
                        if (value != null) onChanged(value);
                      }
                    : null);
        return CardDetailsPanel(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              Text('Prezzo e listing',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(switch (draft.status) {
                DraftStatus.published => 'Annuncio pubblicato su Pokoin.',
                DraftStatus.publishing => 'Pubblicazione in corso…',
                DraftStatus.uncertain =>
                  'Pubblicazione da verificare; la bozza è conservata.',
                _ =>
                  'Bozza in Clipboard · le modifiche vengono salvate sul dispositivo.',
              }),
              const SizedBox(height: 16),
              DetailFields(children: [
                text(
                    'Prezzo PK',
                    card.price,
                    (value) =>
                        _edit((d) => d.edit(card: d.card.edit(price: value))),
                    numeric: true),
                dropdown(
                    'Quantità',
                    '${card.quantity}',
                    {for (var i = 1; i <= 99; i++) '$i': '$i'},
                    (value) => _edit((d) =>
                        d.edit(card: d.card.edit(quantity: int.parse(value))))),
              ]),
              const SizedBox(height: 12),
              DetailFields(children: [
                dropdown(
                    'Condizione',
                    card.condition,
                    scannerConditions,
                    (value) => _edit(
                        (d) => d.edit(card: d.card.edit(condition: value)))),
                dropdown(
                    'Lingua',
                    card.language,
                    scannerLanguages,
                    (value) => _edit(
                        (d) => d.edit(card: d.card.edit(language: value)))),
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
                    (value) => _edit(
                        (d) => d.edit(card: d.card.edit(foilState: value)))),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 6, children: [
                FilterChip(
                    label: const Text('1ª ed.'),
                    selected: draft.firstEdition,
                    onSelected: enabled
                        ? (v) => _edit((d) => d.edit(firstEdition: v))
                        : null),
                FilterChip(
                    label: const Text('Sigillata'),
                    selected: draft.sealed,
                    onSelected: enabled
                        ? (v) => _edit((d) => d.edit(sealed: v))
                        : null),
                FilterChip(
                    label: const Text('Gradata'),
                    selected: draft.graded,
                    onSelected: enabled
                        ? (v) => _edit((d) => d.edit(graded: v))
                        : null),
                FilterChip(
                    label: const Text('Spedizione'),
                    selected: draft.shipping,
                    onSelected: enabled
                        ? (v) => _edit((d) => d.edit(shipping: v))
                        : null),
              ]),
              if (draft.shipping) ...[
                const SizedBox(height: 12),
                dropdown(
                    'Paese di spedizione',
                    draft.shipFromCountry,
                    sellerShipFromCountries,
                    (value) => _edit((d) => d.edit(
                        shipFromCountry: value, shipFromCountryManual: true))),
                const SizedBox(height: 6),
                const Text(
                    'Paese iniziale dall’indirizzo predefinito del Profilo. Puoi cambiarlo qui; viene salvato anche nel profilo venditore quando pubblichi.'),
              ],
              if (draft.graded) ...[
                const SizedBox(height: 12),
                DetailFields(children: [
                  text('Società grading', draft.gradingCompany,
                      (v) => _edit((d) => d.edit(gradingCompany: v))),
                  text('Voto', draft.grade,
                      (v) => _edit((d) => d.edit(grade: v))),
                  text('Certificazione', draft.certificationId,
                      (v) => _edit((d) => d.edit(certificationId: v))),
                ]),
              ],
              const SizedBox(height: 12),
              text('Posizione', draft.location,
                  (v) => _edit((d) => d.edit(location: v))),
              const SizedBox(height: 12),
              text('Commento del venditore', draft.comment,
                  (v) => _edit((d) => d.edit(comment: v))),
              const SizedBox(height: 16),
              if (widget.controller.error != null)
                Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(widget.controller.error!)),
              if (widget.controller.message != null)
                Text(widget.controller.message!),
              if (!widget.controller.authenticated)
                FilledButton(
                    onPressed: widget.onLogin,
                    child: const Text('Accedi per pubblicare'))
              else if (draft.status == DraftStatus.uncertain ||
                  draft.status == DraftStatus.publishing)
                OutlinedButton(
                    onPressed: _publishing
                        ? null
                        : () => widget.controller.reconcile(draft.id),
                    child: const Text('Verifica pubblicazione'))
              else
                FilledButton.icon(
                    onPressed: enabled ? _publish : null,
                    icon: const Icon(Icons.sell_outlined),
                    label: Text(draft.status == DraftStatus.published
                        ? 'Pubblicata'
                        : 'Pubblica su Pokoin')),
            ]));
      });
}
