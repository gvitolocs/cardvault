import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';

class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final profileState = ref.watch(userProfileProvider);
    final isAdmin = ref.watch(isAdminProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      appBar: AppBar(
        backgroundColor: const Color(0xE60A1026),
        title: const Text('Pokoin Admin'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: ListView(
            padding: const EdgeInsets.all(22),
            children: [
              _AdminHero(
                signedIn: user != null,
                isAdmin: isAdmin,
                loading: profileState.isLoading,
              ),
              const SizedBox(height: 18),
              if (user == null)
                _AdminMessage(
                  title: 'Sign in required',
                  body: 'Log in with an admin account to open admin tools.',
                  actionLabel: 'Sign in',
                  onAction: () => context.go('/auth'),
                )
              else if (profileState.isLoading)
                const Center(child: CircularProgressIndicator())
              else if (!isAdmin)
                const _AdminMessage(
                  title: 'Admin access required',
                  body:
                      'This account is signed in, but it does not have the admin role.',
                )
              else
                const _AdminToolGrid(),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminHero extends StatelessWidget {
  const _AdminHero({
    required this.signedIn,
    required this.isAdmin,
    required this.loading,
  });

  final bool signedIn;
  final bool isAdmin;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final status = loading
        ? 'Checking role'
        : isAdmin
            ? 'Admin access active'
            : signedIn
                ? 'Signed in without admin role'
                : 'Signed out';
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xCC0B1024),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Admin Panel',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            status,
            style: const TextStyle(color: Color(0xFF93A4C8)),
          ),
        ],
      ),
    );
  }
}

class _AdminToolGrid extends StatelessWidget {
  const _AdminToolGrid();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: [
        _AdminToolCard(
          title: 'Marketplace Logo Editor',
          body: 'Match expansion names to persistent logo URLs.',
          icon: Icons.image_search_outlined,
          actionLabel: 'Edit',
          onTap: () => context.go('/marketplace/admin/edit'),
        ),
        _AdminToolCard(
          title: 'Marketplace',
          body: 'Open the public marketplace home.',
          icon: Icons.storefront_outlined,
          actionLabel: 'Open',
          onTap: () => context.go('/marketplace'),
        ),
      ],
    );
  }
}

class _AdminToolCard extends StatelessWidget {
  const _AdminToolCard({
    required this.title,
    required this.body,
    required this.icon,
    required this.actionLabel,
    required this.onTap,
  });

  final String title;
  final String body;
  final IconData icon;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xCC0B1024),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: const Color(0xFFFACC15), size: 34),
              const SizedBox(height: 14),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                style: const TextStyle(color: Color(0xFF93A4C8), height: 1.35),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onTap,
                child: Text(actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminMessage extends StatelessWidget {
  const _AdminMessage({
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xCC0B1024),
        borderRadius: BorderRadius.circular(22),
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
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(color: Color(0xFF93A4C8))),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
