import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/project_links.dart';
import '../providers/auth_provider.dart';
import '../services/pokoin_api_client.dart';
import '../utils/price_format.dart';
import '../widgets/site_footer.dart';

class BuyPknScreen extends ConsumerStatefulWidget {
  const BuyPknScreen({super.key});

  @override
  ConsumerState<BuyPknScreen> createState() => _BuyPknScreenState();
}

class _BuyPknScreenState extends ConsumerState<BuyPknScreen> {
  static const _pknUsdtReferencePrice = 0.005;
  static const _packages = [
    _BuyPackage(
      label: 'Starter',
      fiatCents: 500,
      lookupKey: 'pkn_starter_1000_pkn_500_eur',
    ),
    _BuyPackage(
      label: 'Collector',
      fiatCents: 2500,
      lookupKey: 'pkn_collector_5000_pkn_2500_eur',
    ),
    _BuyPackage(
      label: 'Validator',
      fiatCents: 10000,
      lookupKey: 'pkn_validator_20000_pkn_10000_eur',
    ),
  ];

  _BuyPackage _selected = _packages[1];
  bool _loading = false;
  bool _verifyingPayment = false;
  String? _paymentMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _verifyReturnPayment());
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final cachedBalance = ref.watch(cachedPknBalanceProvider).valueOrNull;
    final balance =
        ref.watch(pknBalanceProvider).valueOrNull ?? cachedBalance ?? 0;
    final wallet = profile?.walletAddress;

    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      appBar: const _BuyTopBar(),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 1.35,
            colors: [Color(0x2638BDF8), Color(0x00050816)],
          ),
        ),
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.all(22),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1080),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _BuyHero(
                    signedIn: user != null,
                    walletAddress: wallet,
                    siteBalance: balance,
                    pknUsdtReferencePrice: _pknUsdtReferencePrice,
                    paymentMessage: _paymentMessage,
                    verifyingPayment: _verifyingPayment,
                  ),
                  const SizedBox(height: 22),
                  _BuyPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Choose amount',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Dynamic PKN pricing is fixed at 1 PKN = ${_formatUsdt(_pknUsdtReferencePrice)} USDT.',
                          style: const TextStyle(
                            color: Color(0xFFB8C4E6),
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 14,
                          runSpacing: 14,
                          children: [
                            for (final item in _packages)
                              _PackageCard(
                                item: item,
                                selected: item == _selected,
                                onTap: () => setState(() => _selected = item),
                              ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        _FulfillmentNotice(walletAddress: wallet),
                        const SizedBox(height: 22),
                        FilledButton.icon(
                          onPressed: _loading
                              ? null
                              : user == null
                                  ? () => context.go('/auth?from=/buy')
                                  : () => _startCheckout(user),
                          icon: _loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.payment_outlined),
                          label: Text(user == null
                              ? 'Login to buy PKN'
                              : 'Pay securely with card'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFACC15),
                            foregroundColor: const Color(0xFF111827),
                            padding: const EdgeInsets.symmetric(vertical: 18),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SiteFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _startCheckout(User user) async {
    setState(() => _loading = true);
    try {
      final apiClient = PokoinApiClient(
        auth: ref.read(pokoinApiAuthServiceProvider),
      );
      final uri = Uri.base.resolve('/api/create-pkn-checkout-session');
      final response = await apiClient.postJson(
        uri,
        body: {
          'pknAmount': _selected.pknAmount,
          'fiatCents': _selected.fiatCents,
          'lookupKey': _selected.lookupKey,
        },
      );

      final data = _decodeCheckoutResponse(response.body);
      if (response.statusCode != 200) {
        throw StateError(data['error'] as String? ?? 'Checkout failed.');
      }

      final url = data['url'] as String?;
      if (url == null || url.isEmpty) {
        throw StateError('Stripe did not return a checkout URL.');
      }
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(error.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _verifyReturnPayment() async {
    final user = ref.read(authStateProvider).valueOrNull;
    final params = Uri.base.queryParameters;
    final sessionId = params['session_id'];
    if (user == null || sessionId == null || sessionId.isEmpty) {
      return;
    }

    setState(() {
      _verifyingPayment = true;
      _paymentMessage = 'Confirming Stripe payment...';
    });
    try {
      final apiClient = PokoinApiClient(
        auth: ref.read(pokoinApiAuthServiceProvider),
      );
      final response = await apiClient.postJson(
        Uri.base.resolve('/api/create-pkn-checkout-session'),
        body: {'checkoutSessionId': sessionId},
      );
      final data = _decodeCheckoutResponse(response.body);
      if (response.statusCode != 200) {
        throw StateError(
            data['error'] as String? ?? 'Payment confirmation failed.');
      }
      final amount = data['amountPkn']?.toString() ?? 'PKN';
      setState(() {
        _paymentMessage =
            'Payment confirmed. $amount PKN added to your account balance.';
      });
      ref.invalidate(pknBalanceProvider);
      ref.invalidate(userProfileProvider);
    } catch (error) {
      if (mounted) {
        setState(() => _paymentMessage = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _verifyingPayment = false);
      }
    }
  }

  static String _formatUsdt(double value) {
    return value
        .toStringAsFixed(6)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  static Map<String, dynamic> _decodeCheckoutResponse(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } on FormatException {
      // Vercel can return plain text when a function fails before our handler.
    }
    return const {
      'error':
          'Checkout service is temporarily unavailable. Please try again shortly.',
    };
  }
}

class _BuyPackage {
  const _BuyPackage({
    required this.label,
    required this.fiatCents,
    required this.lookupKey,
  });

  final String label;
  final int fiatCents;
  final String lookupKey;
  int get pknAmount =>
      (fiatCents / 100 / _BuyPknScreenState._pknUsdtReferencePrice).round();

  String get fiatLabel => '€${(fiatCents / 100).toStringAsFixed(2)}';
  String get rateLabel =>
      '1 PKN = ${_BuyPknScreenState._formatUsdt(_BuyPknScreenState._pknUsdtReferencePrice)} USDT';
}

class _PaymentStatusBanner extends StatelessWidget {
  const _PaymentStatusBanner({required this.message, required this.loading});

  final String message;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111936),
        borderRadius: BorderRadius.circular(18),
        border:
            Border.all(color: const Color(0xFFFACC15).withValues(alpha: 0.32)),
      ),
      child: Row(
        children: [
          if (loading)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            const Icon(Icons.verified_outlined, color: Color(0xFFFACC15)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFFE2E8F0), height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _BuyHero extends StatelessWidget {
  const _BuyHero({
    required this.signedIn,
    required this.walletAddress,
    required this.siteBalance,
    required this.pknUsdtReferencePrice,
    required this.paymentMessage,
    required this.verifyingPayment,
  });

  final bool signedIn;
  final String? walletAddress;
  final int siteBalance;
  final double pknUsdtReferencePrice;
  final String? paymentMessage;
  final bool verifyingPayment;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF111B3F), Color(0xFF0B1020)]),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Wrap(
        spacing: 24,
        runSpacing: 22,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (paymentMessage != null) ...[
            _PaymentStatusBanner(
              message: paymentMessage!,
              loading: verifyingPayment,
            ),
            const SizedBox(height: 18),
          ],
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Buy PKN',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Pay securely with Stripe Checkout. PKN is credited to your account balance after payment.',
                  style: TextStyle(color: Color(0xFFB8C4E6), height: 1.5),
                ),
                const SizedBox(height: 12),
                _RatePill(
                  label:
                      'Fixed rate: 1 PKN = ${_BuyPknScreenState._formatUsdt(pknUsdtReferencePrice)} USDT',
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _StatusTile(
                label: 'Account',
                value: signedIn ? 'Logged in' : 'Login required',
                icon: signedIn ? Icons.verified_user_outlined : Icons.login,
              ),
              const _StatusTile(
                label: 'Fulfillment',
                value: 'Account balance',
                icon: Icons.account_balance_wallet_outlined,
              ),
              _StatusTile(
                label: 'Site balance',
                value: formatPkn(siteBalance, decimals: 0),
                icon: Icons.savings_outlined,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RatePill extends StatelessWidget {
  const _RatePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFACC15).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border:
            Border.all(color: const Color(0xFFFACC15).withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFFDE68A),
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _PackageCard extends StatelessWidget {
  const _PackageCard(
      {required this.item, required this.selected, required this.onTap});

  final _BuyPackage item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: 250,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFFACC15).withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected
                ? const Color(0xFFFACC15)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.label,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            Text(
              '${item.pknAmount} PKN',
              style: const TextStyle(
                color: Color(0xFFFDE68A),
                fontSize: 28,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.fiatLabel,
              style: const TextStyle(
                  color: Color(0xFFB8C4E6), fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              item.rateLabel,
              style: const TextStyle(
                color: Color(0xFF93A4C8),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FulfillmentNotice extends StatelessWidget {
  const _FulfillmentNotice({required this.walletAddress});

  final String? walletAddress;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111936),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline,
            color: Color(0xFFFACC15),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              walletAddress == null || walletAddress!.isEmpty
                  ? 'After payment, PKN is added to your account balance. Use Withdraw when you want to send it to a wallet.'
                  : 'After payment, PKN is added to your account balance, not sent automatically to $walletAddress. Use Withdraw when you want an on-chain payout.',
              style: const TextStyle(color: Color(0xFFB8C4E6), height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile(
      {required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFFFACC15)),
          const SizedBox(height: 10),
          Text(label,
              style: const TextStyle(color: Color(0xFF93A4C8), fontSize: 12)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _BuyPanel extends StatelessWidget {
  const _BuyPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xE60B1020),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: child,
    );
  }
}

class _BuyTopBar extends StatelessWidget implements PreferredSizeWidget {
  const _BuyTopBar();

  @override
  Size get preferredSize => const Size.fromHeight(76);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: Color(0xF2050816)),
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Row(
                children: [
                  Image.network(
                    ProjectLinks.logo,
                    width: 42,
                    height: 42,
                    filterQuality: FilterQuality.none,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.toll, color: Color(0xFFFACC15)),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Buy PKN',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  TextButton(
                      onPressed: () => context.go('/'),
                      child: const Text('Home')),
                  TextButton(
                      onPressed: () => context.go('/forum'),
                      child: const Text('Forum')),
                  FilledButton(
                    onPressed: () => context.go('/wallet'),
                    child: const Text('Wallet'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
