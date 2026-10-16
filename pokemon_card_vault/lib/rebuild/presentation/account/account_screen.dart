import 'package:flutter/material.dart';
import '../../controller/account_controller.dart';
import '../../model/account.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen(
      {super.key,
      required this.controller,
      this.onAuthenticated,
      this.onGuest});
  final AccountController controller;
  final VoidCallback? onAuthenticated, onGuest;
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _email = TextEditingController(), _password = TextEditingController();
  bool _obscure = true, _completed = false;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sessionChanged);
  }

  void _sessionChanged() {
    if (_completed ||
        widget.controller.session.user == null ||
        widget.onAuthenticated == null) {
      return;
    }
    _completed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onAuthenticated!();
    });
  }

  @override
  void didUpdateWidget(AccountScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_sessionChanged);
      widget.controller.addListener(_sessionChanged);
      _completed = false;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sessionChanged);
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: widget.onAuthenticated == null
            ? null
            : AppBar(title: const Text('Account Pokoin')),
        body: SafeArea(
            child: Center(
                child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: ListenableBuilder(
                  listenable: widget.controller,
                  builder: (context, _) {
                    final account = widget.controller;
                    final restoring =
                        account.session.status == AccountStatus.restoring;
                    final enabled = !account.busy && !restoring;
                    return AutofillGroup(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                          Image.asset('assets/brand/pokoin-96.png',
                              width: 64, height: 64),
                          const SizedBox(height: 20),
                          Text('Accedi a Pokoin',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineLarge),
                          const SizedBox(height: 8),
                          const Text(
                              'La tua collezione, il tuo Cardex e il tuo Wallet.',
                              textAlign: TextAlign.center),
                          const SizedBox(height: 28),
                          if (restoring) ...[
                            const LinearProgressIndicator(),
                            const SizedBox(height: 12),
                            const Text('Ripristino della sessione…',
                                textAlign: TextAlign.center),
                          ] else ...[
                            FilledButton.tonal(
                              onPressed:
                                  enabled ? account.signInWithGoogle : null,
                              child: const Text('Continua con Google'),
                            ),
                            const SizedBox(height: 14),
                            const Text('oppure usa email e password',
                                textAlign: TextAlign.center),
                            const SizedBox(height: 14),
                            TextField(
                                controller: _email,
                                enabled: !account.busy,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.username],
                                autocorrect: false,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                    labelText: 'Email',
                                    prefixIcon: Icon(Icons.mail_outline))),
                            const SizedBox(height: 14),
                            TextField(
                                controller: _password,
                                enabled: !account.busy,
                                obscureText: _obscure,
                                autofillHints: const [AutofillHints.password],
                                autocorrect: false,
                                enableSuggestions: false,
                                textInputAction: TextInputAction.done,
                                onSubmitted: enabled
                                    ? (_) => account.signIn(
                                        _email.text, _password.text)
                                    : null,
                                decoration: InputDecoration(
                                    labelText: 'Password',
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    suffixIcon: IconButton(
                                        tooltip: _obscure
                                            ? 'Mostra password'
                                            : 'Nascondi password',
                                        onPressed: () => setState(
                                            () => _obscure = !_obscure),
                                        icon: Icon(_obscure
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined)))),
                            const SizedBox(height: 16),
                            FilledButton(
                                onPressed: enabled
                                    ? () => account.signIn(
                                        _email.text, _password.text)
                                    : null,
                                child:
                                    Text(account.busy ? 'Attendi…' : 'Accedi')),
                            TextButton(
                                onPressed: enabled
                                    ? () => account.resetPassword(_email.text)
                                    : null,
                                child: const Text('Password dimenticata?')),
                            if (account.session.status ==
                                AccountStatus.unavailable)
                              TextButton(
                                  onPressed: account.busy
                                      ? null
                                      : account.retryInitialization,
                                  child: const Text('Riprova collegamento')),
                          ],
                          if (account.error != null)
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                child: Text(account.error!,
                                    semanticsLabel: account.error,
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error))),
                          if (account.message != null)
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                child: Text(account.message!)),
                          const SizedBox(height: 20),
                          OutlinedButton.icon(
                              onPressed: account.busy
                                  ? null
                                  : () async {
                                      final success =
                                          await account.continueAsGuest();
                                      if (success && mounted) {
                                        widget.onGuest?.call();
                                      }
                                    },
                              icon: const Icon(Icons.person_outline),
                              label: const Text('Continua come ospite')),
                          const SizedBox(height: 8),
                          const Text(
                              'Puoi esplorare e testare l’app senza account. Potrai accedere dal Profilo.',
                              textAlign: TextAlign.center),
                        ]));
                  })),
        ))),
      );
}
