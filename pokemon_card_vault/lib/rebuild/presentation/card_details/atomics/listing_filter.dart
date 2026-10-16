import 'package:flutter/material.dart';

class ListingFilter<T> extends StatelessWidget {
  const ListingFilter(
      {super.key,
      required this.label,
      required this.value,
      required this.choices,
      required this.onChanged});
  final String label;
  final T value;
  final Map<T, String> choices;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: choices.entries
          .map((entry) => DropdownMenuItem<T>(
              value: entry.key,
              child: Text(entry.value,
                  maxLines: 1, overflow: TextOverflow.ellipsis)))
          .toList(),
      onChanged: (next) => onChanged(next as T));
}
