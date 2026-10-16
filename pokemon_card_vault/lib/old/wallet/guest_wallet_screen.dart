import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../widgets/marketplace_navigation_bar.dart';

/// Public Wallet overview. Guest zeros are placeholders, not account data.
/// Account actions enter the existing login flow before any wallet operation.
class GuestWalletScreen extends StatelessWidget {
  const GuestWalletScreen({super.key, required this.onConnectWallet});

  final VoidCallback onConnectWallet;
  static const _gold = Color(0xFFFACC15);
  static const _muted = Color(0xFF94A3B8);
  static const _panel = Color(0xFF14131B);

  void _signIn(BuildContext context, {String from = '/wallet'}) {
    context.go('/auth?from=${Uri.encodeComponent(from)}');
  }

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    const actions = <(String, IconData)>[
      ('Send', Icons.send_outlined),
      ('Receive', Icons.call_received_rounded),
      ('Withdraw', Icons.download_rounded),
      ('Top up', Icons.upload_rounded),
      ('Exchange', Icons.swap_horiz_rounded),
    ];
    return Scaffold(
      backgroundColor: Colors.black,
      bottomNavigationBar: const MarketplaceNavigationBar(selectedIndex: 2),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1020),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _card(
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Wallet',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 30,
                                  fontWeight: FontWeight.w700)),
                          SizedBox(height: 20),
                          Text.rich(TextSpan(children: [
                            TextSpan(
                                text: '0',
                                style: TextStyle(
                                    fontSize: 48,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700)),
                            TextSpan(
                                text: '.00',
                                style: TextStyle(
                                    fontSize: 26,
                                    color: _muted,
                                    fontWeight: FontWeight.w700)),
                            TextSpan(
                                text: ' PKN',
                                style: TextStyle(
                                    fontSize: 18,
                                    color: _gold,
                                    fontWeight: FontWeight.w700)),
                          ])),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 12,
                      children: [
                        for (final (label, icon) in actions)
                          SizedBox(
                            width: 84,
                            child: Column(
                              children: [
                                IconButton.filledTonal(
                                  tooltip: label,
                                  style: IconButton.styleFrom(
                                    backgroundColor: _panel,
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(56, 56),
                                  ),
                                  onPressed: () => _signIn(context,
                                      from: label == 'Exchange'
                                          ? '/swap'
                                          : '/wallet'),
                                  icon: Icon(icon),
                                ),
                                const SizedBox(height: 6),
                                Text(label,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: _muted)),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 26),
                    _card(
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Activity',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700)),
                          SizedBox(height: 36),
                          Center(
                              child: Icon(Icons.monitor_heart_outlined,
                                  color: _gold, size: 36)),
                          SizedBox(height: 14),
                          Center(
                              child: Text('No activity yet',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600))),
                          SizedBox(height: 28),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Your wallets',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 18),
                          const ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.account_balance_wallet_outlined,
                                color: _gold),
                            title: Text('Pokoin balance',
                                style: TextStyle(color: Colors.white)),
                            subtitle: Text('Not signed in',
                                style: TextStyle(color: _muted)),
                          ),
                          Wrap(
                            alignment: WrapAlignment.end,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 16,
                            children: [
                              const Text('0 PKN',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700)),
                              TextButton(
                                  onPressed: () => _signIn(context),
                                  child: const Text('Sign in')),
                            ],
                          ),
                          const Divider(color: Color(0xFF282732)),
                          const ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.link_rounded, color: _muted),
                            title: Text('PokoinPoS',
                                style: TextStyle(color: Colors.white)),
                            subtitle: Text('Not connected',
                                style: TextStyle(color: _muted)),
                          ),
                          OutlinedButton(
                            onPressed: onConnectWallet,
                            style: OutlinedButton.styleFrom(
                                foregroundColor: _gold),
                            child: const Text('Connect wallet'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
