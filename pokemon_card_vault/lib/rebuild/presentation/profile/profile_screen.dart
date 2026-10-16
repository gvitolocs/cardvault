import 'package:flutter/material.dart';
import '../../controller/profile_controller.dart';
import '../shared/price_format.dart';
import 'component/account_activity.dart';
import 'component/account_settings.dart';
import 'component/wallet_overview.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen(
      {super.key,
      required this.controller,
      required this.onLogin,
      required this.onPortfolio,
      required this.onCardex,
      required this.onOpenCard});
  final ProfileController controller;
  final VoidCallback onLogin, onPortfolio, onCardex;
  final ValueChanged<String> onOpenCard;

  void _open(BuildContext context, String title, Widget body) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) =>
              Scaffold(appBar: AppBar(title: Text(title)), body: body)));

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: Listenable.merge([controller, controller.account]),
      builder: (context, _) {
        final account = controller.account;
        final user = account.session.user;
        final name = controller.profile?.displayName;
        return ListView(padding: const EdgeInsets.all(20), children: [
          Text('Profilo', style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 16),
          ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(user == null
                  ? 'Modalità Ospite'
                  : name?.isNotEmpty == true
                      ? name!
                      : user.displayName.isNotEmpty
                          ? user.displayName
                          : 'Account Pokoin'),
              subtitle:
                  Text(user?.email ?? 'Esplora e testa Pokoin senza account.')),
          if (user == null)
            FilledButton(
                onPressed: onLogin, child: const Text('Accedi al tuo account')),
          const SizedBox(height: 16),
          Card(
              child: ListTile(
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: const Text('Wallet'),
                  subtitle: Text(user == null
                      ? 'Accedi per vedere il tuo saldo'
                      : controller.errors.contains('balance')
                          ? 'Saldo non disponibile'
                          : controller.balance == null
                              ? 'Caricamento saldo…'
                              : pknPrice(controller.balance!.available)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(
                      context,
                      'Wallet',
                      WalletOverview(
                          controller: controller, onLogin: onLogin)))),
          ListTile(
              leading: const Icon(Icons.collections_bookmark_outlined),
              title: const Text('La mia collezione'),
              trailing: const Icon(Icons.chevron_right),
              onTap: onPortfolio),
          ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('Il mio Cardex'),
              trailing: const Icon(Icons.chevron_right),
              onTap: onCardex),
          if (user != null) ...[
            ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('I miei ordini'),
                onTap: () => _open(
                    context,
                    'I miei ordini',
                    AccountActivity(
                        controller: controller,
                        favorites: false,
                        onOpenCard: onOpenCard))),
            ListTile(
                leading: const Icon(Icons.favorite_outline),
                title: const Text('Preferiti'),
                onTap: () => _open(
                    context,
                    'Preferiti',
                    AccountActivity(
                        controller: controller,
                        favorites: true,
                        onOpenCard: onOpenCard))),
            ListTile(
                leading: const Icon(Icons.manage_accounts_outlined),
                title: const Text('Impostazioni account'),
                onTap: () => _open(context, 'Impostazioni account',
                    AccountSettings(controller: controller))),
            const Divider(),
            OutlinedButton.icon(
                onPressed: account.busy ? null : account.signOut,
                icon: const Icon(Icons.logout),
                label: const Text('Esci dall’account')),
          ],
          if (controller.errors.contains('profile'))
            TextButton(
                onPressed: controller.retry,
                child: const Text('Riprova profilo')),
          if (account.error != null) Text(account.error!),
        ]);
      });
}
