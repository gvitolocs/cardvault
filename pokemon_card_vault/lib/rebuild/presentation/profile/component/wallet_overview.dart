import 'package:flutter/material.dart';
import '../../../controller/profile_controller.dart';
import '../../shared/price_format.dart';

class WalletOverview extends StatelessWidget {
  const WalletOverview(
      {super.key, required this.controller, required this.onLogin});
  final ProfileController controller;
  final VoidCallback onLogin;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: Listenable.merge([controller, controller.account]),
      builder: (context, _) {
        final signedIn = controller.account.session.user != null;
        final balance = controller.balance;
        return ListView(padding: const EdgeInsets.all(24), children: [
          Text('Wallet', style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 20),
          if (!signedIn) ...[
            const Text(
                'Accedi al tuo account Pokoin per consultare il saldo e il wallet collegato.'),
            const SizedBox(height: 16),
            FilledButton(
                onPressed: onLogin, child: const Text('Accedi al tuo account')),
          ] else ...[
            if (controller.errors.contains('balance')) ...[
              const Text('Saldo non disponibile.'),
              TextButton(
                  onPressed: controller.retry, child: const Text('Riprova')),
            ] else if (balance == null)
              const LinearProgressIndicator()
            else
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Saldo disponibile'),
                            Text(pknPrice(balance.available),
                                style:
                                    Theme.of(context).textTheme.headlineMedium),
                            const SizedBox(height: 12),
                            Text('Riservati: ${pknPrice(balance.locked)}'),
                          ]))),
            const SizedBox(height: 24),
            const Text('Wallet collegato',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (controller.errors.contains('profile'))
              const Text('Indirizzo non disponibile.')
            else if (controller.profile == null)
              const LinearProgressIndicator()
            else
              SelectableText(controller.profile!.walletAddress.isEmpty
                  ? 'Nessun wallet collegato.'
                  : controller.profile!.walletAddress),
          ],
        ]);
      });
}
