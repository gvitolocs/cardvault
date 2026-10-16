import 'package:flutter/material.dart';
import '../../../model/cardex.dart';

class CollectionNotice extends StatelessWidget {
  const CollectionNotice(
      {super.key, required this.status, required this.onRetry});
  final CollectionStatus status;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (status == CollectionStatus.ready) return const SizedBox.shrink();
    final message = switch (status) {
      CollectionStatus.loading => 'Caricamento della tua collezione…',
      CollectionStatus.guest =>
        'Accedi al tuo account Pokoin per vedere le carte possedute e quelle mancanti. Il catalogo è consultabile anche senza accesso.',
      CollectionStatus.unavailable =>
        'La collezione non è disponibile. Lo stato delle carte resta da verificare.',
      CollectionStatus.ready => '',
    };
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(message),
          if (status == CollectionStatus.unavailable)
            TextButton(
                onPressed: onRetry, child: const Text('Riprova collezione')),
        ]));
  }
}
