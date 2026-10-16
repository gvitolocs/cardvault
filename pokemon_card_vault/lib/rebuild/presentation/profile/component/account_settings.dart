import 'package:flutter/material.dart';
import '../../../controller/profile_controller.dart';

class AccountSettings extends StatefulWidget {
  const AccountSettings({super.key, required this.controller});
  final ProfileController controller;
  @override
  State<AccountSettings> createState() => _AccountSettingsState();
}

class _AccountSettingsState extends State<AccountSettings> {
  late final _name = TextEditingController(
      text: widget.controller.profile?.displayName ??
          widget.controller.account.session.user?.displayName ??
          '');
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable:
          Listenable.merge([widget.controller, widget.controller.account]),
      builder: (context, _) {
        final profile = widget.controller, account = profile.account;
        final user = account.session.user;
        return ListView(padding: const EdgeInsets.all(24), children: [
          if (user != null) ...[
            Text(user.email),
            const SizedBox(height: 20),
            TextField(
                controller: _name,
                maxLength: 60,
                decoration:
                    const InputDecoration(labelText: 'Nome visualizzato')),
            FilledButton(
                onPressed:
                    profile.saving ? null : () => profile.saveName(_name.text),
                child: Text(profile.saving ? 'Salvataggio…' : 'Salva nome')),
            if (profile.feedback != null) Text(profile.feedback!),
            const SizedBox(height: 24),
            OutlinedButton(
                onPressed: account.busy || user.email.isEmpty
                    ? null
                    : () => account.resetPassword(user.email),
                child: const Text('Reimposta password')),
            if (account.message != null) Text(account.message!),
            if (account.error != null) Text(account.error!),
          ] else
            const Text('Accedi per modificare il tuo account.'),
        ]);
      });
}
