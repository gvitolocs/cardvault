import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../constants/app_colors.dart';
import '../widgets/pokoin_logo.dart';
import '../widgets/shop_chain_account_card.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      appBar: AppBar(
        title: const Text('Shop Account'),
        backgroundColor: const Color(0xE60A1026),
        foregroundColor: Colors.white,
        actions: [
          TextButton(
              onPressed: () => context.go('/marketplace'),
              child: const Text('Marketplace')),
          TextButton(
              onPressed: () => context.go('/scan'), child: const Text('Scan')),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(26),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF111B3F), Color(0xFF0B1020)]),
                    borderRadius: BorderRadius.circular(28),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PokoinLogo(size: 50),
                      SizedBox(height: 16),
                      Text(
                        'CardVault shop profile',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w900),
                      ),
                      SizedBox(height: 10),
                      Text(
                        'This account represents the marketplace operator. It is linked to the public PokoinPoS settlement address used for PKN payments and reserve references.',
                        style: TextStyle(color: Color(0xFFB8C4E6), height: 1.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                const ShopChainAccountCard(),
                const SizedBox(height: 22),
                Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    _ProfileAction(
                      icon: Icons.account_balance_wallet_outlined,
                      title: 'Open wallet',
                      subtitle: 'Use the Pokoin wallet connected to PKN.',
                      onTap: () => context.go('/wallet'),
                    ),
                    _ProfileAction(
                      icon: Icons.health_and_safety_outlined,
                      title: 'Network health',
                      subtitle: 'Check RPC, peer, and reserve status.',
                      onTap: () => context.go('/health'),
                    ),
                    _ProfileAction(
                      icon: Icons.travel_explore_outlined,
                      title: 'Pokoin scan',
                      subtitle: 'Review chain, wPKN, and public metadata.',
                      onTap: () => context.go('/scan'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ProfileAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xCC111936),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFFFACC15)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                        style: const TextStyle(
                            color: Color(0xFF93A4C8),
                            fontSize: 12,
                            height: 1.35)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: Color(0xFF93A4C8)),
            ],
          ),
        ),
      ),
    );
  }
}
