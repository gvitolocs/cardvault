import 'package:flutter/material.dart';
import '../../../controller/profile_controller.dart';
import '../../shared/price_format.dart';

class AccountActivity extends StatelessWidget {
  const AccountActivity(
      {super.key,
      required this.controller,
      required this.favorites,
      required this.onOpenCard});
  final ProfileController controller;
  final bool favorites;
  final ValueChanged<String> onOpenCard;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final key = favorites ? 'favorites' : 'orders';
        final ids = controller.favorites;
        final orders = controller.orders;
        if (controller.account.session.user == null) {
          return const Center(
              child: Text('Accedi per consultare questa sezione.'));
        }
        if (controller.errors.contains(key)) {
          return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Dati non disponibili.'),
            TextButton(
                onPressed: controller.retry, child: const Text('Riprova')),
          ]));
        }
        if (favorites ? ids == null : orders == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final count = favorites ? ids!.length : orders!.length;
        if (count == 0) {
          return Center(
              child: Text(favorites
                  ? 'Nessuna carta nei preferiti.'
                  : 'Non hai ancora ordini.'));
        }
        return ListView.builder(
            itemCount: count,
            itemBuilder: (context, index) {
              if (favorites) {
                final id = ids![index];
                return ListTile(
                    leading: const Icon(Icons.favorite_outline),
                    title: Text('Carta #$id'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => onOpenCard(id));
              }
              final order = orders![index];
              return ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: Text('Ordine ${order.id}'),
                  subtitle: Text(order.status),
                  trailing: Text(pknPrice(order.total)));
            });
      });
}
