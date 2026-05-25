import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/project_links.dart';
import '../widgets/site_footer.dart';

class ContactScreen extends StatelessWidget {
  const ContactScreen({super.key});

  static const _contactEmail = 'contact@pokoin.com';

  static Future<void> _openEmail() async {
    await launchUrl(
      Uri.parse('mailto:$_contactEmail?subject=Pokoin%20support%20request'),
      mode: LaunchMode.externalApplication,
    );
  }

  static Future<void> _openUrl(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      appBar: const _ContactTopBar(),
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
                  const _ContactHero(onEmail: _openEmail),
                  const SizedBox(height: 20),
                  const _ContactGuidanceCard(),
                  const SizedBox(height: 14),
                  const _ContactMethodCard(
                    title: 'General Contact',
                    body:
                        'For account, marketplace, listing, wallet, documentation, advertising, or partnership questions, email $_contactEmail. Include the page URL, screenshots, transaction hash, order reference, or listing details when relevant.',
                    buttonLabel: 'Email Pokoin',
                    onTap: _openEmail,
                  ),
                  const SizedBox(height: 14),
                  _ContactMethodCard(
                    title: 'Network And Reserve Links',
                    body:
                        'For public network checks, use Pokoin Scan, the RPC endpoint, reserve proof, and wPKN contract links. These references help users verify public data without sharing private keys or seed phrases.',
                    buttonLabel: 'Open Pokoin Scan',
                    onTap: () => context.go('/scan'),
                  ),
                  const SizedBox(height: 14),
                  _ContactMethodCard(
                    title: 'External Ecosystem References',
                    body:
                        'wPKN liquidity, token metadata, and BNB ecosystem references are available through the official external links below. Always verify URLs before connecting a wallet.',
                    buttonLabel: 'Open PancakeSwap',
                    onTap: () => _openUrl(ProjectLinks.pancakeSwap),
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
}

class _ContactTopBar extends StatelessWidget implements PreferredSizeWidget {
  const _ContactTopBar();

  @override
  Size get preferredSize => const Size.fromHeight(68);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: const Color(0xF2050816),
      elevation: 0,
      titleSpacing: 18,
      title: Row(
        children: [
          Image.network(
            ProjectLinks.logo,
            width: 34,
            height: 34,
            filterQuality: FilterQuality.none,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.currency_bitcoin,
              color: Color(0xFFFACC15),
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'Contact Us',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => context.go('/'),
          child: const Text('Home'),
        ),
        const SizedBox(width: 10),
      ],
    );
  }
}

class _ContactHero extends StatelessWidget {
  const _ContactHero({required this.onEmail});

  final VoidCallback onEmail;

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
              'Support And Transparency',
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
            'Contact Pokoin',
            style: TextStyle(
              color: Colors.white,
              fontSize: 42,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.4,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 14),
          const SelectableText(
            'Reach the Pokoin team at contact@pokoin.com for product questions, marketplace support, wallet account issues, documentation feedback, and partnership inquiries.',
            style: TextStyle(
              color: Color(0xFFCBD5E1),
              fontSize: 16,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onEmail,
            icon: const Icon(Icons.mail_outline),
            label: const Text('contact@pokoin.com'),
          ),
        ],
      ),
    );
  }
}

class _ContactGuidanceCard extends StatelessWidget {
  const _ContactGuidanceCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xCC0B1020),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Before You Send',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 10),
          SelectableText(
            'Never send seed phrases, private keys, passwords, API keys, or full payment card details. Pokoin support can review public transaction hashes and account-safe screenshots, but we will never ask for wallet recovery secrets.',
            style: TextStyle(
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

class _ContactMethodCard extends StatelessWidget {
  const _ContactMethodCard({
    required this.title,
    required this.body,
    required this.buttonLabel,
    required this.onTap,
  });

  final String title;
  final String body;
  final String buttonLabel;
  final VoidCallback onTap;

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
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          SelectableText(
            body,
            style: const TextStyle(
              color: Color(0xFFCBD5E1),
              height: 1.6,
              fontSize: 14.5,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: onTap,
            child: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
}
