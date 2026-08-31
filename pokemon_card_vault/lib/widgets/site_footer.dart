import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/project_links.dart';
import '../utils/public_home.dart';

class SiteFooter extends StatelessWidget {
  const SiteFooter({super.key});

  static Future<void> _openExternal(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 760;
    final stacked = width < 980;
    final wide = width >= 1180;
    final compactColumnWidth = width < 460 ? width - 36 : (width - 72) / 2;
    final year = DateTime.now().year;

    return Container(
      margin: const EdgeInsets.only(top: 28),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 18 : 34,
        vertical: compact ? 24 : 34,
      ),
      decoration: BoxDecoration(
        color: const Color(0xE60A1026),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 30,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (stacked) ...[
            const _FooterBrand(),
            const SizedBox(height: 22),
            Wrap(
              spacing: 18,
              runSpacing: 22,
              crossAxisAlignment: WrapCrossAlignment.start,
              children: [
                SizedBox(
                  width: compactColumnWidth,
                  child: _buildExploreColumn(context),
                ),
                SizedBox(
                  width: compactColumnWidth,
                  child: _buildNetworkColumn(context),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const _FooterSignal(),
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Expanded(
                  flex: 3,
                  child: _FooterBrand(),
                ),
                SizedBox(width: wide ? 42 : 30),
                Expanded(
                  flex: 2,
                  child: _buildExploreColumn(context),
                ),
                SizedBox(width: wide ? 34 : 24),
                Expanded(
                  flex: 2,
                  child: _buildNetworkColumn(context),
                ),
                SizedBox(width: wide ? 34 : 24),
                const SizedBox(
                  width: 282,
                  child: _FooterSignal(),
                ),
              ],
            ),
          const SizedBox(height: 22),
          const Divider(color: Color(0x1AFFFFFF)),
          const SizedBox(height: 16),
          Flex(
            direction: stacked ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment:
                stacked ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (stacked)
                Text(
                  '© $year Pokoin. Card Reserve, PokoinPoS and wPKN are part of the Pokoin ecosystem.',
                  style: const TextStyle(
                    color: Color(0xFF93A4C8),
                    fontSize: 12,
                    height: 1.45,
                  ),
                )
              else
                Flexible(
                  child: Text(
                    '© $year Pokoin. Card Reserve, PokoinPoS and wPKN are part of the Pokoin ecosystem.',
                    style: const TextStyle(
                      color: Color(0xFF93A4C8),
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ),
              if (!stacked) const SizedBox(width: 24),
              Padding(
                padding: EdgeInsets.only(top: stacked ? 10 : 0),
                child: const Text(
                  'Transparent collectible commerce. On-chain settlement.',
                  style: TextStyle(
                    color: Color(0xFFFDE68A),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.45,
                  ),
                ),
              ),
              if (!stacked) const SizedBox(width: 24),
              Padding(
                padding: EdgeInsets.only(top: stacked ? 8 : 0),
                child: TextButton.icon(
                  onPressed: () => _openExternal('mailto:contact@pokoin.com'),
                  icon: const Icon(Icons.mail_outline, size: 16),
                  label: const Text('contact@pokoin.com'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFB8C4E6),
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static _FooterColumn _buildExploreColumn(BuildContext context) {
    return _FooterColumn(
      title: 'Explore',
      links: [
        _FooterLink('Home', () => goPublicHome(context)),
        _FooterLink('About Us', () => context.go('/about')),
        _FooterLink('Earn PKN', () => context.go('/earn')),
        _FooterLink('Whitepaper', () => context.go('/whitepaper')),
        _FooterLink('Documentation', () => context.go('/docs')),
        _FooterLink('Contact Us', () => context.go('/contact')),
        _FooterLink('Privacy Policy', () => context.go('/privacy')),
        _FooterLink('PokoinScan', () => context.go('/scan')),
        _FooterLink('Card scan', () => context.go('/cardscan')),
        _FooterLink('Network health', () => context.go('/health')),
      ],
    );
  }

  static _FooterColumn _buildNetworkColumn(BuildContext context) {
    return _FooterColumn(
      title: 'Account & Network',
      links: [
        _FooterLink('My Account', () => context.go('/profile')),
        _FooterLink('Buy PKN', () => context.go('/buy')),
        _FooterLink('RPC endpoint', () => _openExternal(ProjectLinks.rpc)),
        _FooterLink('Reserve proof', () => _openExternal(ProjectLinks.reserve)),
        _FooterLink(
            'wPKN contract', () => _openExternal(ProjectLinks.bscContract)),
        _FooterLink(
            'PancakeSwap', () => _openExternal(ProjectLinks.pancakeSwap)),
        _FooterLink(
            'CoinMarketCap', () => _openExternal(ProjectLinks.coinMarketCap)),
      ],
    );
  }
}

class _FooterBrand extends StatelessWidget {
  const _FooterBrand();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xFF111936),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  ProjectLinks.logo,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.none,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.currency_bitcoin,
                    color: Color(0xFFFACC15),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pokoin',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                    ),
                  ),
                  Text(
                    'Permissioned PoS + collector rails',
                    style: TextStyle(color: Color(0xFF93A4C8), fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const Text(
          'A production-oriented ecosystem for native PKN settlement, wrapped liquidity and premium card marketplace infrastructure.',
          style: TextStyle(color: Color(0xFFCBD5E1), height: 1.5),
        ),
      ],
    );
  }
}

class _FooterColumn extends StatelessWidget {
  const _FooterColumn({required this.title, required this.links});

  final String title;
  final List<_FooterLink> links;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 10),
            for (final link in links)
              TextButton(
                onPressed: link.onTap,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFB8C4E6),
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  minimumSize: const Size(0, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  alignment: Alignment.centerLeft,
                ),
                child: Text(
                  link.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FooterSignal extends StatelessWidget {
  const _FooterSignal();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0x3314B8A6), Color(0x26FACC15)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x33FACC15)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_outlined, color: Color(0xFFFACC15)),
          SizedBox(height: 12),
          Text(
            'Public by design',
            style: TextStyle(
                color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 8),
          Text(
            'Explorer data, RPC status, reserve proof and wPKN contract references stay one click away.',
            style: TextStyle(color: Color(0xFFCBD5E1), height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _FooterLink {
  const _FooterLink(this.label, this.onTap);

  final String label;
  final VoidCallback onTap;
}
