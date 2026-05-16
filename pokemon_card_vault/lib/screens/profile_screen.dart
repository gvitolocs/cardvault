import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/project_links.dart';
import '../providers/auth_provider.dart';
import '../providers/marketplace_account_provider.dart';
import '../utils/price_format.dart';
import '../widgets/site_footer.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final profile = ref.watch(userProfileProvider);
    final balanceState = ref.watch(pknBalanceProvider);
    final ordersState = ref.watch(userOrdersProvider);
    final withdrawState = ref.watch(withdrawRequestsProvider);
    final balance = balanceState.valueOrNull ?? 0;
    final orders = ordersState.valueOrNull ?? const <Map<String, dynamic>>[];
    final withdraws =
        withdrawState.valueOrNull ?? const <Map<String, dynamic>>[];

    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      appBar: _ProfileTopBar(
        onLogout: () async {
          await ref.read(authServiceProvider).signOut();
          if (context.mounted) {
            context.go('/');
          }
        },
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 1.25,
            colors: [Color(0x2638BDF8), Color(0x00050816)],
          ),
        ),
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.all(22),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  profile.when(
                    data: (profile) => _UserHeader(
                      uid: user?.uid,
                      email: user?.email ?? profile?.email ?? '',
                      displayName: profile?.displayName ??
                          user?.displayName ??
                          'Pokoin user',
                      photoUrl: profile?.photoUrl ?? user?.photoURL,
                      walletAddress: profile?.walletAddress,
                      balance: balance,
                      ordersCount: orders.length,
                      pendingWithdraws: withdraws
                          .where((item) => item['status'] == 'pending')
                          .length,
                      onEditName: user == null
                          ? null
                          : () => _showDisplayNameDialog(
                                context,
                                ref,
                                user.uid,
                                profile?.displayName ??
                                    user.displayName ??
                                    'Pokoin user',
                              ),
                      onEditPhoto: user == null
                          ? null
                          : () => _showPhotoDialog(
                                context,
                                ref,
                                user.uid,
                                profile?.photoUrl ?? user.photoURL,
                              ),
                      onEditWallet: user == null
                          ? null
                          : () => _showWalletDialog(
                                context,
                                ref,
                                user.uid,
                                profile?.walletAddress,
                              ),
                    ),
                    loading: () => const _LoadingPanel(),
                    error: (error, _) => _ErrorPanel(message: error.toString()),
                  ),
                  const SizedBox(height: 22),
                  _QuickActions(
                    onWallet: () => context.go('/wallet'),
                    onWithdraw: user == null
                        ? null
                        : () => _showWithdrawDialog(context, ref, user.uid),
                  ),
                  const SizedBox(height: 22),
                  _ResponsiveColumns(
                    left: _OrdersPanel(state: ordersState),
                    right: _WithdrawPanel(state: withdrawState),
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

  void _showWithdrawDialog(BuildContext context, WidgetRef ref, String uid) {
    final addressController = TextEditingController();
    final amountController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => _ProfileDialog(
        title: 'Request PKN withdraw',
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Create a pending withdraw request. An operator process finalizes the on-chain payout.',
              style: TextStyle(color: Color(0xFFB8C4E6), height: 1.45),
            ),
            const SizedBox(height: 16),
            _ProfileTextField(
              controller: addressController,
              label: '0x payout address',
              icon: Icons.account_balance_wallet_outlined,
            ),
            const SizedBox(height: 12),
            _ProfileTextField(
              controller: amountController,
              label: 'Amount PKN',
              icon: Icons.toll_outlined,
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                final amount = int.tryParse(amountController.text.trim());
                if (amount == null) {
                  throw ArgumentError('Enter a whole PKN amount.');
                }
                await ref.read(authServiceProvider).requestWithdraw(
                      uid: uid,
                      toAddress: addressController.text,
                      amountPkn: amount,
                    );
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Withdraw request created.'),
                      backgroundColor: Color(0xFFFACC15),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(e.toString()),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Request'),
          ),
        ],
      ),
    ).whenComplete(() {
      addressController.dispose();
      amountController.dispose();
    });
  }

  void _showWalletDialog(
    BuildContext context,
    WidgetRef ref,
    String uid,
    String? currentAddress,
  ) {
    final controller = TextEditingController(text: currentAddress ?? '');
    showDialog<void>(
      context: context,
      builder: (context) => _ProfileDialog(
        title: 'Linked payout wallet',
        body: _ProfileTextField(
          controller: controller,
          label: '0x wallet address',
          helperText: 'Leave empty to unlink the wallet.',
          icon: Icons.account_balance_wallet_outlined,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await ref.read(authServiceProvider).updateWalletAddress(
                      uid: uid,
                      walletAddress: controller.text,
                    );
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Wallet updated.')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(e.toString()),
                        backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  void _showDisplayNameDialog(
    BuildContext context,
    WidgetRef ref,
    String uid,
    String currentName,
  ) {
    final controller = TextEditingController(text: currentName);
    showDialog<void>(
      context: context,
      builder: (context) => _ProfileDialog(
        title: 'Edit display name',
        body: _ProfileTextField(
          controller: controller,
          label: 'Display name',
          icon: Icons.person_outline,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await ref.read(authServiceProvider).updateDisplayName(
                      uid: uid,
                      displayName: controller.text,
                    );
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Profile updated.')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(e.toString()),
                        backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  void _showPhotoDialog(
    BuildContext context,
    WidgetRef ref,
    String uid,
    String? currentPhotoUrl,
  ) {
    final controller = TextEditingController(text: currentPhotoUrl ?? '');
    showDialog<void>(
      context: context,
      builder: (context) => _ProfileDialog(
        title: 'Profile picture',
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ProfileAvatar(photoUrl: currentPhotoUrl, onTap: null, size: 72),
            const SizedBox(height: 16),
            _ProfileTextField(
              controller: controller,
              label: 'Image URL',
              helperText: 'Paste an https image URL. Leave empty to remove it.',
              icon: Icons.image_outlined,
              keyboardType: TextInputType.url,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await ref.read(authServiceProvider).updatePhotoUrl(
                      uid: uid,
                      photoUrl: '',
                    );
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Profile picture removed.')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(e.toString()),
                        backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Remove'),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await ref.read(authServiceProvider).updatePhotoUrl(
                      uid: uid,
                      photoUrl: controller.text,
                    );
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Profile picture updated.')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(e.toString()),
                        backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }
}

class _ProfileDialog extends StatelessWidget {
  const _ProfileDialog({
    required this.title,
    required this.body,
    required this.actions,
  });

  final String title;
  final Widget body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(22),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xF20B1020),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 34,
                offset: Offset(0, 20),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 18),
              body,
              const SizedBox(height: 22),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.end,
                children: actions,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileTextField extends StatelessWidget {
  const _ProfileTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.helperText,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String? helperText;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        labelStyle: const TextStyle(color: Color(0xFF93A4C8)),
        helperStyle: const TextStyle(color: Color(0xFF64748B)),
        prefixIcon: Icon(icon, color: const Color(0xFFFACC15)),
        filled: true,
        fillColor: const Color(0xFF111936),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFFACC15)),
        ),
      ),
    );
  }
}

class _ProfileTopBar extends StatelessWidget implements PreferredSizeWidget {
  const _ProfileTopBar({required this.onLogout});

  final VoidCallback onLogout;

  @override
  Size get preferredSize => const Size.fromHeight(76);

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 820;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xF2050816),
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        boxShadow: const [
          BoxShadow(
              color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 10)),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: SizedBox(
                height: 68,
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => context.go('/'),
                      borderRadius: BorderRadius.circular(20),
                      child: const _ProfileBrand(),
                    ),
                    const Spacer(),
                    if (!compact) ...[
                      const _ProfileNavPill(),
                      const SizedBox(width: 12),
                    ],
                    _TopBarButton(
                      label: 'Logout',
                      icon: Icons.logout,
                      primary: false,
                      onPressed: onLogout,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileBrand extends StatelessWidget {
  const _ProfileBrand();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFF111936),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Image.network(
              ProjectLinks.logo,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.none,
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pokoin Account',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.2,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'Profile, wallet and marketplace',
              style: TextStyle(
                color: Color(0xFF93A4C8),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProfileNavPill extends StatelessWidget {
  const _ProfileNavPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xCC0B1020),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ProfileNavAction(
              label: 'Marketplace',
              path: '/marketplace',
              icon: Icons.storefront),
          _ProfileNavAction(
              label: 'Wallet',
              path: '/wallet',
              icon: Icons.account_balance_wallet_outlined),
          _ProfileNavAction(
              label: 'Scan', path: '/scan', icon: Icons.query_stats),
          _ProfileNavAction(
              label: 'Health',
              path: '/health',
              icon: Icons.health_and_safety_outlined),
        ],
      ),
    );
  }
}

class _ProfileNavAction extends StatelessWidget {
  const _ProfileNavAction({
    required this.label,
    required this.path,
    required this.icon,
  });

  final String label;
  final String path;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => context.go(path),
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFFE2E8F0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: const Color(0xFFFACC15)),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _TopBarButton extends StatelessWidget {
  const _TopBarButton({
    required this.label,
    required this.icon,
    required this.primary,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool primary;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor:
            primary ? const Color(0xFFFACC15) : const Color(0xFF111936),
        foregroundColor: primary ? const Color(0xFF111827) : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    );
  }
}

class _UserHeader extends StatelessWidget {
  final String? uid;
  final String email;
  final String displayName;
  final String? photoUrl;
  final String? walletAddress;
  final int balance;
  final int ordersCount;
  final int pendingWithdraws;
  final VoidCallback? onEditName;
  final VoidCallback? onEditPhoto;
  final VoidCallback? onEditWallet;

  const _UserHeader({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.photoUrl,
    required this.walletAddress,
    required this.balance,
    required this.ordersCount,
    required this.pendingWithdraws,
    required this.onEditName,
    required this.onEditPhoto,
    required this.onEditWallet,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF111B3F), Color(0xFF0B1020)],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 16,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _ProfileAvatar(photoUrl: photoUrl, onTap: onEditPhoto),
              SizedBox(
                width: 520,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (onEditName != null) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Edit display name',
                            onPressed: onEditName,
                            icon: const Icon(Icons.edit_outlined,
                                color: Color(0xFF93A4C8)),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      email.isEmpty ? 'Signed in account' : email,
                      style: const TextStyle(color: Color(0xFFB8C4E6)),
                    ),
                    if (uid != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'User ID ${_short(uid!)}',
                        style: const TextStyle(
                            color: Color(0xFF64748B), fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MetricChip(
                label: 'Marketplace balance',
                value: formatPkn(balance, decimals: 0),
              ),
              _MetricChip(
                label: 'Linked wallet',
                value:
                    walletAddress == null ? 'Not linked yet' : walletAddress!,
                actionLabel: walletAddress == null ? 'Link wallet' : 'Edit',
                onTap: onEditWallet,
              ),
              _MetricChip(
                label: 'Orders',
                value: '$ordersCount recent',
              ),
              _MetricChip(
                label: 'Withdraw requests',
                value: '$pendingWithdraws pending',
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'Your site balance is a marketplace credit. The wallet remains optional and can be used for on-chain PKN withdrawals later.',
            style: TextStyle(color: Color(0xFFB8C4E6), height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar(
      {required this.photoUrl, required this.onTap, this.size = 50});

  final String? photoUrl;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.32);
    final avatar = Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF111936),
        borderRadius: radius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: photoUrl != null && photoUrl!.isNotEmpty
          ? Image.network(
              photoUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _DefaultProfileLogo(size: size),
            )
          : _DefaultProfileLogo(size: size),
    );

    if (onTap == null) {
      return avatar;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: radius,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            right: -4,
            bottom: -4,
            child: Container(
              width: size * 0.38,
              height: size * 0.38,
              decoration: BoxDecoration(
                color: const Color(0xFFFACC15),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFF0B1020), width: 2),
              ),
              child: Icon(
                Icons.edit,
                color: const Color(0xFF111827),
                size: size * 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DefaultProfileLogo extends StatelessWidget {
  const _DefaultProfileLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      ProjectLinks.logo,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.none,
      errorBuilder: (_, __, ___) => Icon(
        Icons.person_outline,
        color: const Color(0xFFFACC15),
        size: size * 0.52,
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  final String label;
  final String value;
  final String? actionLabel;
  final VoidCallback? onTap;

  const _MetricChip({
    required this.label,
    required this.value,
    this.actionLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 220),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF93A4C8), fontSize: 12),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (actionLabel != null && onTap != null) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: onTap,
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  final VoidCallback onWallet;
  final VoidCallback? onWithdraw;

  const _QuickActions({
    required this.onWallet,
    required this.onWithdraw,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: [
        _ProfileAction(
          icon: Icons.account_balance_wallet_outlined,
          title: 'Open Pokoin wallet',
          subtitle: 'View on-chain PKN balance and activity.',
          onTap: onWallet,
        ),
        _ProfileAction(
          icon: Icons.payments_outlined,
          title: 'Request withdraw',
          subtitle: 'Move marketplace PKN credit to your 0x wallet.',
          onTap: onWithdraw ?? () {},
          disabled: onWithdraw == null,
        ),
      ],
    );
  }
}

class _ResponsiveColumns extends StatelessWidget {
  final Widget left;
  final Widget right;

  const _ResponsiveColumns({required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    if (!wide) {
      return Column(children: [left, const SizedBox(height: 18), right]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 18),
        Expanded(child: right),
      ],
    );
  }
}

class _OrdersPanel extends StatelessWidget {
  final AsyncValue<List<Map<String, dynamic>>> state;

  const _OrdersPanel({required this.state});

  @override
  Widget build(BuildContext context) {
    return _SectionPanel(
      title: 'Recent orders',
      icon: Icons.shopping_bag_outlined,
      child: state.when(
        data: (orders) {
          if (orders.isEmpty) {
            return const _EmptyState(
              title: 'No orders yet',
              body: 'Your marketplace purchases will appear here.',
            );
          }
          return Column(
            children: [
              for (final order in orders.take(5))
                _ActivityRow(
                  leading: 'Order',
                  title: '#${order['id']}',
                  subtitle: _formatDate(order['createdAt']),
                  trailing: formatPkn(
                      _readNum(order['totalPkn'] ?? order['total']),
                      decimals: 0),
                  status: '${order['status'] ?? 'pending'}',
                ),
            ],
          );
        },
        loading: () => const _PanelLoading(),
        error: (error, _) => _InlineError(message: error.toString()),
      ),
    );
  }
}

class _WithdrawPanel extends StatelessWidget {
  final AsyncValue<List<Map<String, dynamic>>> state;

  const _WithdrawPanel({required this.state});

  @override
  Widget build(BuildContext context) {
    return _SectionPanel(
      title: 'Withdraw history',
      icon: Icons.outbound_outlined,
      child: state.when(
        data: (requests) {
          if (requests.isEmpty) {
            return const _EmptyState(
              title: 'No withdrawals',
              body: 'Requests to move PKN on-chain will be tracked here.',
            );
          }
          return Column(
            children: [
              for (final request in requests.take(5))
                _ActivityRow(
                  leading: 'PKN',
                  title: formatPkn(_readNum(request['amountPkn']), decimals: 0),
                  subtitle: _short('${request['toAddress'] ?? ''}',
                      head: 10, tail: 8),
                  trailing: _formatDate(request['createdAt']),
                  status: '${request['status'] ?? 'pending'}',
                ),
            ],
          );
        },
        loading: () => const _PanelLoading(),
        error: (error, _) => _InlineError(message: error.toString()),
      ),
    );
  }
}

class _SectionPanel extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionPanel({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xDD0B1020),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFFFACC15)),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final String leading;
  final String title;
  final String subtitle;
  final String trailing;
  final String status;

  const _ActivityRow({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF172554),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              leading,
              style: const TextStyle(
                color: Color(0xFFFACC15),
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      const TextStyle(color: Color(0xFF93A4C8), fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                trailing,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                status.toUpperCase(),
                style: const TextStyle(
                  color: Color(0xFFFACC15),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String body;

  const _EmptyState({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(body, style: const TextStyle(color: Color(0xFF93A4C8))),
        ],
      ),
    );
  }
}

class _PanelLoading extends StatelessWidget {
  const _PanelLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(12),
      child: LinearProgressIndicator(),
    );
  }
}

class _InlineError extends StatelessWidget {
  final String message;

  const _InlineError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: const TextStyle(color: Colors.redAccent),
    );
  }
}

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  final String message;

  const _ErrorPanel({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        message,
        style: const TextStyle(color: Colors.white),
      ),
    );
  }
}

class _ProfileAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool disabled;

  const _ProfileAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = disabled ? const Color(0xFF64748B) : Colors.white;
    return SizedBox(
      width: 300,
      child: InkWell(
        onTap: disabled ? null : onTap,
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
              Icon(icon,
                  color: disabled
                      ? const Color(0xFF64748B)
                      : const Color(0xFFFACC15)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                          color: foreground, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      disabled ? 'Sign in to use this action.' : subtitle,
                      style: const TextStyle(
                        color: Color(0xFF93A4C8),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
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

String _short(String value, {int head = 6, int tail = 4}) {
  if (value.length <= head + tail + 3) {
    return value;
  }
  return '${value.substring(0, head)}...${value.substring(value.length - tail)}';
}

num _readNum(Object? value) {
  if (value is num) {
    return value;
  }
  return num.tryParse('$value') ?? 0;
}

String _formatDate(Object? value) {
  DateTime? date;
  if (value is Timestamp) {
    date = value.toDate();
  } else if (value is DateTime) {
    date = value;
  } else if (value is String) {
    date = DateTime.tryParse(value);
  }
  if (date == null) {
    return 'Pending';
  }
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}
