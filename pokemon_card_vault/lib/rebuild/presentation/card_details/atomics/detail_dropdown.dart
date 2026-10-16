import 'package:flutter/material.dart';

class DetailDropdown extends StatelessWidget {
  const DetailDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });
  final String label, value;
  final List<String> values;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: values
          .map((value) => DropdownMenuItem(
              value: value,
              child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis)))
          .toList(),
      onChanged: (value) {
        if (value != null) onChanged(value);
      });
}
