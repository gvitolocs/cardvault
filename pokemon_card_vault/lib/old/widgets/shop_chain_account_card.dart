import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../constants/app_colors.dart';
import '../constants/project_links.dart';
import 'pokoin_logo.dart';

class ShopChainAccountCard extends StatelessWidget {
  final bool compact;
  final bool dark;

  const ShopChainAccountCard({super.key, this.compact = false, this.dark = false});

  @override
  Widget build(BuildContext context) {
    const address = ProjectLinks.nativeTreasury;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 14 : 16),
      decoration: BoxDecoration(
        color: dark
            ? const Color(0xCC111936)
            : compact
                ? AppColors.primary.withValues(alpha: 0.08)
                : Colors.white,
        borderRadius: BorderRadius.circular(dark ? 24 : 12),
        border: Border.all(
          color: dark
              ? Colors.white.withValues(alpha: 0.08)
              : AppColors.primary.withValues(alpha: 0.22),
        ),
        boxShadow: compact
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? 0.22 : 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const PokoinLogo(size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Shop chain account',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: dark ? Colors.white : AppColors.textPrimary),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Connected to PokoinPoS for PKN settlement',
                      style: TextStyle(
                        color: dark ? const Color(0xFF93A4C8) : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SelectableText(
            address,
            style: TextStyle(
              color: dark ? const Color(0xFFCBD5E1) : AppColors.textPrimary,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Badge(
                  icon: Icons.verified_outlined,
                  label: 'PKN address linked',
                  dark: dark),
              _Badge(
                  icon: Icons.public,
                  label: 'Public on-chain reference',
                  dark: dark),
              _Badge(
                  icon: Icons.currency_bitcoin,
                  label: 'Native settlement wallet',
                  dark: dark),
            ],
          ),
          if (!compact) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => context.go('/wallet'),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open Pokoin Wallet'),
              style: OutlinedButton.styleFrom(
                foregroundColor: dark ? const Color(0xFFFACC15) : null,
                side: BorderSide(
                  color: dark
                      ? const Color(0x66FACC15)
                      : AppColors.primary.withValues(alpha: 0.42),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool dark;

  const _Badge({required this.icon, required this.label, this.dark = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: dark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(999),
        border: dark
            ? Border.all(color: AppColors.primary.withValues(alpha: 0.22))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: dark ? const Color(0xFFFDE68A) : AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
