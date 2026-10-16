import 'package:flutter/material.dart';
import '../../../style/card_details_style.dart';
import '../atomics/card_details_panel.dart';

class CardBestDeal extends StatefulWidget {
  const CardBestDeal({super.key});

  @override
  State<CardBestDeal> createState() => _CardBestDealState();
}

class _CardBestDealState extends State<CardBestDeal> {
  String _condition = 'MP', _language = 'IT';

  @override
  Widget build(BuildContext context) => CardDetailsPanel(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Migliore offerta',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          const Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                Icon(Icons.lock_outline,
                    size: 20, color: CardDetailsStyle.yellow),
                Text('SILVER · 100 PKN',
                    style: TextStyle(
                        color: CardDetailsStyle.yellow,
                        fontWeight: FontWeight.w700)),
              ]),
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('—',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 40, color: CardDetailsStyle.muted))),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final condition in const ['PO', 'PL', 'MP', 'SP', 'NM'])
              ChoiceChip(
                  label: Text(condition),
                  selected: _condition == condition,
                  onSelected: (_) => setState(() => _condition = condition)),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final language in const ['EN', 'IT', 'FR', 'DE', 'ES', 'PT'])
              ChoiceChip(
                  avatar: const Icon(Icons.language, size: 18),
                  showCheckmark: false,
                  label: Text(language),
                  selected: _language == language,
                  onSelected: (_) => setState(() => _language = language)),
          ]),
          const SizedBox(height: 24),
          const OutlinedButton(onPressed: null, child: Text('Non disponibile')),
          const SizedBox(height: 8),
          const Text('Prezzi reali non ancora collegati',
              textAlign: TextAlign.center,
              style: TextStyle(color: CardDetailsStyle.muted)),
        ]),
      );
}
