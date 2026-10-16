import 'package:flutter/material.dart';

class SearchFilters extends StatelessWidget {
  const SearchFilters(
      {super.key,
      required this.productType,
      required this.printLanguage,
      required this.onChanged});
  final String productType;
  final String printLanguage;
  final void Function(String productType, String printLanguage) onChanged;

  @override
  Widget build(BuildContext context) => ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('Filtri'),
        leading: const Icon(Icons.tune_rounded),
        children: [
          DropdownButtonFormField<String>(
            initialValue: productType,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Tipo di articolo'),
            items: const [
              DropdownMenuItem(value: '', child: Text('Tutti gli articoli')),
              DropdownMenuItem(value: 'card', child: Text('Carte')),
              DropdownMenuItem(value: 'booster_pack', child: Text('Buste')),
              DropdownMenuItem(value: 'booster_box', child: Text('Box')),
            ],
            onChanged: (value) => onChanged(value ?? '', printLanguage),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: printLanguage,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Lingua della stampa'),
            items: const [
              DropdownMenuItem(value: 'all', child: Text('Tutte le lingue')),
              DropdownMenuItem(value: 'western', child: Text('Occidentale')),
              DropdownMenuItem(
                  value: 'japanese', child: Text('Giapponese / Coreana')),
              DropdownMenuItem(value: 'chinese', child: Text('Cinese')),
            ],
            onChanged: (value) => onChanged(productType, value ?? 'all'),
          ),
          if (productType.isNotEmpty || printLanguage != 'all')
            Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                    onPressed: () => onChanged('', 'all'),
                    icon: const Icon(Icons.filter_alt_off_outlined),
                    label: const Text('Azzera filtri'))),
          const SizedBox(height: 12),
        ],
      );
}
