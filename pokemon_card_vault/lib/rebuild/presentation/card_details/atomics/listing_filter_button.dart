import 'package:flutter/material.dart';

/// Selettore mobile: apre solo la presentazione delle scelte ricevute.
class ListingFilterButton extends StatelessWidget {
  const ListingFilterButton(
      {super.key,
      required this.label,
      required this.value,
      required this.choices,
      required this.onChanged,
      required this.icon});
  final String label;
  final String? value;
  final Map<String?, String> choices;
  final ValueChanged<String?> onChanged;
  final IconData icon;

  void _showChoices(BuildContext context) {
    showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .75),
        builder: (sheetContext) => SafeArea(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                      child: Text(label,
                          style: Theme.of(sheetContext).textTheme.titleLarge)),
                  Flexible(
                      child: ListView(shrinkWrap: true, children: [
                    for (final entry in choices.entries)
                      ListTile(
                          title: Text(entry.value),
                          selected: value == entry.key,
                          trailing: value == entry.key
                              ? const Icon(Icons.check)
                              : null,
                          onTap: () {
                            onChanged(entry.key);
                            Navigator.of(sheetContext).pop();
                          }),
                  ])),
                ])));
  }

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
      onPressed: () => _showChoices(context),
      icon: Icon(icon),
      label:
          Text('$label: ${value == null ? 'tutte' : choices[value] ?? value}'));
}
