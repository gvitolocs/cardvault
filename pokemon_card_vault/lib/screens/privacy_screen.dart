import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../constants/project_links.dart';
import '../widgets/site_footer.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static const _sections = [
    _PrivacySection(
      title: 'Information we collect',
      body:
          'Pokoin may collect account details such as your email address, display name, username, wallet address, profile image, marketplace activity, forum posts, support messages, and settings you choose to save. When you buy, sell, top up, withdraw, or connect a wallet, we process the information needed to complete that action.',
    ),
    _PrivacySection(
      title: 'Payments and wallet activity',
      body:
          'Payment processing is handled by third-party payment providers such as Stripe. Pokoin does not store full card numbers. Public blockchain transactions, wallet addresses, balances, validator activity, and reserve information may be visible on-chain or through PokoinScan because blockchains are public by design.',
    ),
    _PrivacySection(
      title: 'How we use information',
      body:
          'We use information to provide accounts, wallet linking, marketplace listings, checkout, PKN balance features, withdrawals, fraud prevention, customer support, network status, security monitoring, and product improvements. We may also use contact information to send account, verification, transaction, or security messages.',
    ),
    _PrivacySection(
      title: 'Service providers',
      body:
          'Pokoin relies on service providers for hosting, authentication, storage, email delivery, payments, analytics, marketplace operations, and blockchain infrastructure. These providers may process information only as needed to deliver their services to Pokoin and its users.',
    ),
    _PrivacySection(
      title: 'Cookies and local storage',
      body:
          'The site may use cookies, browser storage, wallet provider state, Firebase session data, and similar technologies to keep you signed in, secure your account, remember preferences, and operate the app. You can control some storage through your browser settings, but disabling it may break account or wallet features.',
    ),
    _PrivacySection(
      title: 'Sharing and disclosures',
      body:
          'We do not sell personal information. We may disclose information when required by law, to protect users and the network, to prevent fraud or abuse, to complete marketplace transactions, or as part of a business transfer involving the Pokoin ecosystem.',
    ),
    _PrivacySection(
      title: 'Retention and security',
      body:
          'We keep information for as long as needed to provide the service, meet legal and accounting requirements, resolve disputes, prevent abuse, and maintain network integrity. We use technical and organizational safeguards, but no online service can guarantee perfect security.',
    ),
    _PrivacySection(
      title: 'Your choices',
      body:
          'You can update account profile information in the app, disconnect wallets where supported, and contact us about access, correction, deletion, or other privacy requests. Some records, including public blockchain data and transaction records required for compliance, may not be removable.',
    ),
    _PrivacySection(
      title: 'Children',
      body:
          'Pokoin is not intended for children under 13. If you believe a child has provided personal information to us, contact us so we can review and take appropriate action.',
    ),
    _PrivacySection(
      title: 'Changes to this policy',
      body:
          'We may update this Privacy Policy as Pokoin, Card Reserve, PokoinPoS, PKN, wPKN, and marketplace features evolve. The updated version will be posted on this page with a new effective date.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      appBar: const _PrivacyTopBar(),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topLeft,
            radius: 1.25,
            colors: [Color(0x2638BDF8), Color(0x00050816)],
          ),
        ),
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 26, 18, 44),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _PrivacyHero(),
                  const SizedBox(height: 20),
                  for (final section in _sections) ...[
                    _PrivacyCard(section: section),
                    const SizedBox(height: 14),
                  ],
                  const _ContactCard(),
                  const SiteFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PrivacySection {
  const _PrivacySection({required this.title, required this.body});

  final String title;
  final String body;
}

class _PrivacyHero extends StatelessWidget {
  const _PrivacyHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: const Color(0xE60B1020),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 34,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0x1AFACC15),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0x55FACC15)),
            ),
            child: const Text(
              'Effective May 20, 2026',
              style: TextStyle(
                color: Color(0xFFFDE68A),
                fontWeight: FontWeight.w900,
                fontSize: 12,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Privacy Policy',
            style: TextStyle(
              color: Colors.white,
              fontSize: 42,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.4,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'This policy explains how Pokoin handles information across pokoin.com, Card Reserve marketplace features, Pokoin accounts, wallet tools, PokoinScan, PKN, wPKN, and related ecosystem services.',
            style: TextStyle(
              color: Color(0xFFCBD5E1),
              fontSize: 16,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard({required this.section});

  final _PrivacySection section;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xCC0B1020),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            section.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 10),
          SelectableText(
            section.body,
            style: const TextStyle(
              color: Color(0xFFCBD5E1),
              height: 1.6,
              fontSize: 14.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xE6111936),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x55FACC15)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Contact',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 10),
          SelectableText(
            'For privacy questions or requests, contact Pokoin at contact@pokoin.com.',
            style: TextStyle(
              color: Color(0xFFFDE68A),
              height: 1.6,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyTopBar extends StatelessWidget implements PreferredSizeWidget {
  const _PrivacyTopBar();

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
            constraints: const BoxConstraints(maxWidth: 980),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Row(
                children: [
                  Image.network(
                    ProjectLinks.logo,
                    width: 42,
                    height: 42,
                    filterQuality: FilterQuality.none,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.privacy_tip_outlined,
                      color: Color(0xFFFACC15),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Pokoin Privacy',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.go('/'),
                    child: const Text('Home'),
                  ),
                  TextButton(
                    onPressed: () => context.go('/docs'),
                    child: const Text('Docs'),
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
