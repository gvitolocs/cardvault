import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:math' as math;
import 'dart:typed_data';

import '../constants/project_links.dart';
import '../providers/auth_provider.dart';
import '../providers/marketplace_account_provider.dart';
import '../utils/price_format.dart';
import '../utils/public_home.dart';
import '../wallet/wallet_bridge_stub.dart';
import '../widgets/site_footer.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late final bridge = createWalletBridge();
  final bool _switchingWalletAccount = false;

  @override
  Widget build(BuildContext context) {
    ref.listen(authStateProvider, (previous, next) {
      if (!next.isLoading && next.valueOrNull == null && mounted) {
        context.go('/auth?from=/profile');
      }
    });

    final authState = ref.watch(authStateProvider);
    final user = authState.valueOrNull;
    if (authState.isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF050816),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.go('/auth?from=/profile');
        }
      });
      return const Scaffold(
        backgroundColor: Color(0xFF050816),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final profile = ref.watch(userProfileProvider);
    final balanceState = ref.watch(pknBalanceProvider);
    final walletBalanceState = ref.watch(linkedWalletBalanceProvider);
    final ordersState = ref.watch(userOrdersProvider);
    final cachedBalance = ref.watch(cachedPknBalanceProvider).valueOrNull;
    final balance = balanceState.valueOrNull ?? cachedBalance ?? 0;
    final orders = ordersState.valueOrNull ?? const <Map<String, dynamic>>[];

    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      appBar: _ProfileTopBar(
        onLogout: () async {
          await ref.read(authServiceProvider).signOut();
          ref.invalidate(authStateProvider);
          ref.invalidate(userProfileProvider);
          ref.invalidate(pknBalanceProvider);
          ref.invalidate(linkedWalletBalanceProvider);
          ref.invalidate(userOrdersProvider);
          ref.invalidate(withdrawRequestsProvider);
          if (context.mounted) {
            context.go('/auth?from=/profile');
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
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 860;
                      final content = Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          profile.when(
                            data: (profile) => _UserHeader(
                              username: profile?.username ?? '',
                              photoUrl: profile?.photoUrl,
                              walletAddress: profile?.walletAddress,
                              hasSilverAccess: profile?.hasSilverAccess == true,
                              silverUntil: profile?.silverUntil,
                              balance: balance,
                              walletBalance: walletBalanceState.valueOrNull,
                              walletBalanceLoading:
                                  walletBalanceState.isLoading,
                              ordersCount: orders.length,
                              onEditUsername: () => _showUsernameDialog(
                                context,
                                ref,
                                profile?.username ?? '',
                              ),
                              onEditPhoto: () => _showPhotoDialog(
                                context,
                                ref,
                                user.uid,
                                profile?.photoUrl,
                              ),
                              onConnectWallet: () => _connectMetaMaskWallet(
                                context,
                                ref,
                              ),
                              switchingWalletAccount: _switchingWalletAccount,
                            ),
                            loading: () => const _LoadingPanel(),
                            error: (error, _) =>
                                _ErrorPanel(message: error.toString()),
                          ),
                          const SizedBox(height: 22),
                          _MarketplaceInventoryPanel(
                            ordersCount: orders.length,
                            onInventory: () => context.go('/orders'),
                            onFavorites: () => context.go('/favorites'),
                            onSell: () => context.go('/marketplace/connect'),
                          ),
                          const SizedBox(height: 22),
                          _WalletPreferencesPanel(
                            balance: balance,
                            walletAddress: profile.valueOrNull?.walletAddress,
                            walletBalance: walletBalanceState.valueOrNull,
                            walletBalanceLoading: walletBalanceState.isLoading,
                            onWallet: () => context.go('/wallet'),
                            onConnectWallet: () =>
                                _connectMetaMaskWallet(context, ref),
                            onWithdraw: () => _showWithdrawDialog(
                              context,
                              ref,
                              profile.valueOrNull?.walletAddress,
                            ),
                          ),
                          const SizedBox(height: 22),
                          const _ForumActivityPanel(),
                          const SizedBox(height: 22),
                          _QuickActions(
                            onWallet: () => context.go('/wallet'),
                            onWithdraw: () => _showWithdrawDialog(
                              context,
                              ref,
                              profile.valueOrNull?.walletAddress,
                            ),
                          ),
                          const SizedBox(height: 22),
                          _OrdersPanel(state: ordersState),
                          const SizedBox(height: 22),
                          _AccountSecurityPanel(
                            providerIds: ref
                                .read(authServiceProvider)
                                .currentProviderIds,
                            email:
                                user.email ?? profile.valueOrNull?.email ?? '',
                            walletAddress: profile.valueOrNull?.walletAddress,
                            onConnectGoogle: () => _connectGoogleAccount(
                              context,
                              ref,
                            ),
                            onSetPassword: () => _showPasswordDialog(
                              context,
                              ref,
                              user.email ?? profile.valueOrNull?.email ?? '',
                            ),
                          ),
                        ],
                      );
                      if (compact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const _ProfileSideMenu(compact: true),
                            const SizedBox(height: 18),
                            content,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(
                            width: 260,
                            child: _ProfileSideMenu(),
                          ),
                          const SizedBox(width: 22),
                          Expanded(child: content),
                        ],
                      );
                    },
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

  void _showWithdrawDialog(
    BuildContext context,
    WidgetRef ref,
    String? linkedWalletAddress,
  ) {
    final linkedAddress = linkedWalletAddress?.trim() ?? '';
    if (linkedAddress.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Link a wallet before withdrawing account balance.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final amountController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => _ProfileDialog(
        title: 'Request PKN withdraw',
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Withdraw account balance to your linked wallet.',
              style: TextStyle(color: Color(0xFFB8C4E6), height: 1.45),
            ),
            const SizedBox(height: 10),
            SelectableText(
              linkedAddress,
              style: const TextStyle(
                color: Color(0xFFCBD5E1),
                fontFamily: 'monospace',
              ),
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
                final result =
                    await ref.read(authServiceProvider).requestWithdraw(
                          toAddress: linkedAddress,
                          amountPkn: amount,
                        );
                ref.invalidate(pknBalanceProvider);
                ref.invalidate(withdrawRequestsProvider);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        (result['payoutTxHash'] as String? ?? '').isNotEmpty
                            ? 'Withdraw sent from the bank wallet.'
                            : result['warning'] as String? ??
                                'Withdraw request created for manual bank payout.',
                      ),
                      backgroundColor: const Color(0xFFFACC15),
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
      amountController.dispose();
    });
  }

  Future<void> _connectMetaMaskWallet(
      BuildContext context, WidgetRef ref) async {
    final bridge = createWalletBridge();
    if (!bridge.hasProvider) {
      if (bridge.isMobile) {
        try {
          final session = await ref
              .read(authServiceProvider)
              .createWalletLinkSession(returnPath: '/profile');
          final sessionId = session['sessionId'] as String? ?? '';
          if (sessionId.isEmpty) {
            throw StateError('Wallet link session was empty.');
          }
          final url = Uri(
            path: '/auth',
            queryParameters: {
              'walletLinkSession': sessionId,
              'from': '/profile',
            },
          ).toString();
          if (bridge.openMetaMaskDappUrl(url)) {
            if (!context.mounted) {
              return;
            }
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Opening MetaMask to link this wallet...'),
                backgroundColor: Color(0xFFFACC15),
              ),
            );
            return;
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(e.toString()), backgroundColor: Colors.red),
            );
          }
          return;
        }
      }
      if (bridge.openMetaMaskDapp()) {
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Opening this page in MetaMask...'),
            backgroundColor: Color(0xFFFACC15),
          ),
        );
        return;
      }
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Install MetaMask or another EVM browser wallet first.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final account = await bridge.requestAccount();
      if (account == null) {
        throw StateError('No wallet account selected.');
      }
      final currentProfile = ref.read(userProfileProvider).valueOrNull;
      final linked = currentProfile?.walletAddress?.trim().toLowerCase();
      if (linked != null &&
          linked.isNotEmpty &&
          linked != account.trim().toLowerCase()) {
        throw StateError(
          'This account already has a different linked wallet.',
        );
      }
      if (!context.mounted) {
        return;
      }
      final shouldLink = await _confirmWalletLink(context, account);
      if (!shouldLink) {
        return;
      }
      final nonce =
          await ref.read(authServiceProvider).requestWalletNonce(account);
      final message = nonce['message'] as String? ?? '';
      if (message.isEmpty) {
        throw StateError('Wallet sign-in nonce was empty.');
      }
      final signature =
          await bridge.signMessage(address: account, message: message);
      await ref.read(authServiceProvider).linkSignedWallet(
            address: account,
            signature: signature,
          );
      ref.invalidate(userProfileProvider);
      ref.invalidate(pknBalanceProvider);
      ref.invalidate(linkedWalletBalanceProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Wallet connected. Top up and withdraw are now available.'),
            backgroundColor: Color(0xFFFACC15),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<bool> _confirmWalletLink(BuildContext context, String account) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF111827),
        title: const Text(
          'Link this wallet?',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'This will link $account to the current Pokoin account. A Google/email account can have only one linked wallet.',
          style: const TextStyle(color: Color(0xFFB8C4E6), height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Link wallet'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _connectGoogleAccount(
    BuildContext context,
    WidgetRef ref,
  ) async {
    try {
      await ref.read(authServiceProvider).linkGoogleToCurrentUser();
      ref.invalidate(authStateProvider);
      ref.invalidate(userProfileProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Google account connected.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showPasswordDialog(
    BuildContext context,
    WidgetRef ref,
    String currentEmail,
  ) {
    final emailController = TextEditingController(text: currentEmail);
    final passwordController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (context) => _ProfileDialog(
        title: 'Email and password',
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Add or update an email/password login for this same Pokoin account.',
              style: TextStyle(color: Color(0xFFB8C4E6), height: 1.45),
            ),
            const SizedBox(height: 16),
            _ProfileTextField(
              controller: emailController,
              label: 'Email',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            _ProfileTextField(
              controller: passwordController,
              label: 'New password',
              icon: Icons.lock_outline,
              obscureText: true,
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
                await ref.read(authServiceProvider).setEmailPassword(
                      email: emailController.text,
                      password: passwordController.text,
                    );
                ref.invalidate(authStateProvider);
                ref.invalidate(userProfileProvider);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Email/password updated.')),
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
            child: const Text('Save'),
          ),
        ],
      ),
    ).whenComplete(() {
      emailController.dispose();
      passwordController.dispose();
    });
  }

  void _showUsernameDialog(
    BuildContext context,
    WidgetRef ref,
    String currentUsername,
  ) {
    final controller = TextEditingController(text: currentUsername);
    showDialog<void>(
      context: context,
      builder: (context) => _ProfileDialog(
        title: 'Edit username',
        body: _ProfileTextField(
          controller: controller,
          label: 'Username',
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
                await ref.read(authServiceProvider).updateUsername(
                      username: controller.text,
                    );
                ref.invalidate(userProfileProvider);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Username updated.')),
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
    showDialog<void>(
      context: context,
      builder: (context) => _ProfilePictureDialog(
        currentPhotoUrl: currentPhotoUrl,
        onRemove: () async {
          await ref.read(authServiceProvider).removeProfilePicture();
          ref.invalidate(userProfileProvider);
        },
        onSave: (bytes) async {
          await ref.read(authServiceProvider).uploadProfilePicture(
                imageBytes: bytes,
              );
          ref.invalidate(userProfileProvider);
        },
      ),
    );
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
    this.keyboardType,
    this.obscureText = false,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Color(0xFF93A4C8)),
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
      decoration: const BoxDecoration(
        color: Color(0xF2050816),
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
                      onTap: () => goPublicHome(context),
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
              label: 'Forum', path: '/forum', icon: Icons.forum_outlined),
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
  final String username;
  final String? photoUrl;
  final String? walletAddress;
  final bool hasSilverAccess;
  final DateTime? silverUntil;
  final int balance;
  final String? walletBalance;
  final bool walletBalanceLoading;
  final int ordersCount;
  final VoidCallback? onEditUsername;
  final VoidCallback? onEditPhoto;
  final VoidCallback? onConnectWallet;
  final bool switchingWalletAccount;

  const _UserHeader({
    required this.username,
    required this.photoUrl,
    required this.walletAddress,
    required this.hasSilverAccess,
    required this.silverUntil,
    required this.balance,
    required this.walletBalance,
    required this.walletBalanceLoading,
    required this.ordersCount,
    required this.onEditUsername,
    required this.onEditPhoto,
    required this.onConnectWallet,
    required this.switchingWalletAccount,
  });

  @override
  Widget build(BuildContext context) {
    final linkedWalletAddress = walletAddress?.trim();
    final hasLinkedWallet =
        linkedWalletAddress != null && linkedWalletAddress.isNotEmpty;

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
                            username.isEmpty ? 'Pokoin user' : username,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        if (onEditUsername != null) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Edit username',
                            onPressed: onEditUsername,
                            icon: const Icon(Icons.edit_outlined,
                                color: Color(0xFF93A4C8)),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      username.isEmpty
                          ? 'Username not assigned yet'
                          : '@$username',
                      style: const TextStyle(
                        color: Color(0xFFFACC15),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (hasSilverAccess) ...[
                      const SizedBox(height: 10),
                      _SilverProfileBadge(silverUntil: silverUntil),
                    ],
                    if (switchingWalletAccount) ...[
                      const SizedBox(height: 8),
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Switching to selected MetaMask wallet...',
                            style: TextStyle(color: Color(0xFFB8C4E6)),
                          ),
                        ],
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
                label: 'Account balance',
                value: formatPkn(balance, decimals: 0),
              ),
              if (hasLinkedWallet)
                _MetricChip(
                  label: 'Connected wallet balance',
                  value: walletBalanceLoading
                      ? 'Loading...'
                      : walletBalance == null
                          ? 'Unavailable'
                          : '$walletBalance PKN',
                ),
              _MetricChip(
                label: 'Linked wallet',
                value: hasLinkedWallet ? linkedWalletAddress : 'Not linked yet',
                actionLabel: hasLinkedWallet ? 'Reconnect' : 'Connect MetaMask',
                onTap: onConnectWallet,
              ),
              _MetricChip(
                label: 'Orders',
                value: '$ordersCount recent',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SilverProfileBadge extends StatelessWidget {
  const _SilverProfileBadge({required this.silverUntil});

  final DateTime? silverUntil;

  @override
  Widget build(BuildContext context) {
    final expiry = silverUntil;
    final subtitle = expiry == null
        ? 'Silver member'
        : 'Silver until ${expiry.year}-${expiry.month.toString().padLeft(2, '0')}-${expiry.day.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE5E7EB), Color(0xFF94A3B8)],
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.workspace_premium,
              color: Color(0xFF111827), size: 16),
          const SizedBox(width: 6),
          Text(
            subtitle,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.photoUrl,
    required this.onTap,
    this.size = 50,
  });

  final String? photoUrl;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.32);
    final cleanPhotoUrl = photoUrl?.trim();
    final avatar = Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF111936),
        borderRadius: radius,
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: cleanPhotoUrl != null && cleanPhotoUrl.isNotEmpty
          ? Image.network(
              cleanPhotoUrl,
              key: ValueKey(cleanPhotoUrl),
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

class _ProfileSideMenu extends StatelessWidget {
  const _ProfileSideMenu({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final items = [
      _ProfileMenuItem(
        icon: Icons.savings_outlined,
        title: 'Earn PKN',
        subtitle: 'Shard cards into marketplace balance',
        onTap: () => context.go('/earn'),
      ),
      _ProfileMenuItem(
        icon: Icons.inventory_2_outlined,
        title: 'Market inventory',
        subtitle: 'Listings, orders, saved cards',
        onTap: () => context.go('/inventory'),
      ),
      _ProfileMenuItem(
        icon: Icons.collections_bookmark_outlined,
        title: 'My collection',
        subtitle: 'Owned cards, expansions, NFT and trade shortcuts',
        onTap: () => context.go('/collection'),
      ),
      _ProfileMenuItem(
        icon: Icons.hexagon_outlined,
        title: 'My NFTs',
        subtitle: 'Owned NFT cards and physical shipping requests',
        onTap: () => context.go('/nft'),
      ),
      _ProfileMenuItem(
        icon: Icons.account_balance_wallet_outlined,
        title: 'Wallet preferences',
        subtitle: 'PKN, withdrawals, linked wallet',
        onTap: () => context.go('/wallet'),
      ),
      _ProfileMenuItem(
        icon: Icons.forum_outlined,
        title: 'Forum recent activities',
        subtitle: 'Topics, replies and community',
        onTap: () => context.go('/forum'),
      ),
      _ProfileMenuItem(
        icon: Icons.favorite_border,
        title: 'Watchlist',
        subtitle: 'Favorite cards and products',
        onTap: () => context.go('/favorites'),
      ),
      _ProfileMenuItem(
        icon: Icons.security_outlined,
        title: 'Login and security',
        subtitle: 'Google, password, wallet login',
        onTap: () {},
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xDD0B1020),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: compact
          ? Wrap(spacing: 10, runSpacing: 10, children: items)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Account menu',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                ...items,
              ],
            ),
    );
  }
}

class _ProfileMenuItem extends StatelessWidget {
  const _ProfileMenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 228,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: const Color(0x99111936),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFFFACC15), size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF93A4C8),
                      fontSize: 11,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarketplaceInventoryPanel extends StatelessWidget {
  const _MarketplaceInventoryPanel({
    required this.ordersCount,
    required this.onInventory,
    required this.onFavorites,
    required this.onSell,
  });

  final int ordersCount;
  final VoidCallback onInventory;
  final VoidCallback onFavorites;
  final VoidCallback onSell;

  @override
  Widget build(BuildContext context) {
    return _SectionPanel(
      title: 'Market inventory',
      icon: Icons.inventory_2_outlined,
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _ProfileAction(
            icon: Icons.receipt_long_outlined,
            title: 'Orders and purchases',
            subtitle: '$ordersCount recent marketplace orders.',
            onTap: onInventory,
          ),
          _ProfileAction(
            icon: Icons.inventory_2_outlined,
            title: 'Seller inventory',
            subtitle: 'Manage listings, stock, and seller order flow.',
            onTap: () => context.go('/inventory'),
          ),
          _ProfileAction(
            icon: Icons.favorite_border,
            title: 'Watchlist',
            subtitle: 'Review favorite singles, products, and saved items.',
            onTap: onFavorites,
          ),
          _ProfileAction(
            icon: Icons.hexagon_outlined,
            title: 'My NFTs',
            subtitle: 'Review NFT-only purchases and request physical cards.',
            onTap: () => context.go('/nft'),
          ),
          _ProfileAction(
            icon: Icons.collections_bookmark_outlined,
            title: 'My collection',
            subtitle: 'Browse expansions with owned cards shown in color.',
            onTap: () => context.go('/collection'),
          ),
          _ProfileAction(
            icon: Icons.add_business_outlined,
            title: 'Seller sync',
            subtitle: 'Connect CardTrader and open seller marketplace tools.',
            onTap: onSell,
          ),
        ],
      ),
    );
  }
}

class _WalletPreferencesPanel extends StatelessWidget {
  const _WalletPreferencesPanel({
    required this.balance,
    required this.walletAddress,
    required this.walletBalance,
    required this.walletBalanceLoading,
    required this.onWallet,
    required this.onConnectWallet,
    required this.onWithdraw,
  });

  final int balance;
  final String? walletAddress;
  final String? walletBalance;
  final bool walletBalanceLoading;
  final VoidCallback onWallet;
  final VoidCallback onConnectWallet;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    final hasWallet = (walletAddress ?? '').trim().isNotEmpty;
    return _SectionPanel(
      title: 'Wallet preferences',
      icon: Icons.account_balance_wallet_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                value: hasWallet ? walletAddress!.trim() : 'Not linked yet',
                actionLabel: hasWallet ? 'Reconnect' : 'Connect',
                onTap: onConnectWallet,
              ),
              if (hasWallet)
                _MetricChip(
                  label: 'On-chain wallet',
                  value: walletBalanceLoading
                      ? 'Loading...'
                      : walletBalance == null
                          ? 'Unavailable'
                          : '$walletBalance PKN',
                ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: onWallet,
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open wallet'),
              ),
              OutlinedButton.icon(
                onPressed: onWithdraw,
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Withdraw PKN'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ForumActivityPanel extends StatelessWidget {
  const _ForumActivityPanel();

  @override
  Widget build(BuildContext context) {
    return _SectionPanel(
      title: 'Forum recent activities',
      icon: Icons.forum_outlined,
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _ProfileAction(
            icon: Icons.auto_awesome,
            title: 'Latest discussions',
            subtitle:
                'Browse market talk, trading strategy, and Pokoin updates.',
            onTap: () => context.go('/forum'),
          ),
          _ProfileAction(
            icon: Icons.edit_note_outlined,
            title: 'Start a topic',
            subtitle: 'Ask the community or share a marketplace signal.',
            onTap: () => context.go('/forum'),
          ),
          _ProfileAction(
            icon: Icons.groups_outlined,
            title: 'Community categories',
            subtitle: 'Jump into products, singles, DeFi, or support threads.',
            onTap: () => context.go('/forum'),
          ),
        ],
      ),
    );
  }
}

class _AccountSecurityPanel extends StatelessWidget {
  const _AccountSecurityPanel({
    required this.providerIds,
    required this.email,
    required this.walletAddress,
    required this.onConnectGoogle,
    required this.onSetPassword,
  });

  final Set<String> providerIds;
  final String email;
  final String? walletAddress;
  final VoidCallback onConnectGoogle;
  final VoidCallback onSetPassword;

  @override
  Widget build(BuildContext context) {
    final hasGoogle = providerIds.contains('google.com');
    final hasPassword = providerIds.contains('password');
    final hasWallet = (walletAddress ?? '').trim().isNotEmpty;
    final isWalletOnly = hasWallet &&
        (providerIds.isEmpty ||
            providerIds.every((provider) => provider == 'firebase'));

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Login methods',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isWalletOnly
                ? 'This account is currently wallet-only. Add Google or email/password so you can recover and sign in another way.'
                : 'Manage the sign-in methods connected to this Pokoin account.',
            style: const TextStyle(color: Color(0xFFB8C4E6), height: 1.45),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _LoginMethodChip(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Wallet',
                status: hasWallet ? 'Connected' : 'Not connected',
                connected: hasWallet,
              ),
              _LoginMethodChip(
                icon: Icons.g_mobiledata,
                label: 'Google',
                status: hasGoogle ? 'Connected' : 'Not connected',
                connected: hasGoogle,
                actionLabel: hasGoogle ? null : 'Connect Google',
                onTap: hasGoogle ? null : onConnectGoogle,
              ),
              _LoginMethodChip(
                icon: Icons.lock_outline,
                label: 'Email/password',
                status: hasPassword
                    ? 'Password enabled'
                    : email.trim().isEmpty
                        ? 'Not configured'
                        : email,
                connected: hasPassword,
                actionLabel:
                    hasPassword ? 'Update password' : 'Create password',
                onTap: onSetPassword,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LoginMethodChip extends StatelessWidget {
  const _LoginMethodChip({
    required this.icon,
    required this.label,
    required this.status,
    required this.connected,
    this.actionLabel,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String status;
  final bool connected;
  final String? actionLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 240),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: connected
            ? const Color(0x2238D39F)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: connected
              ? const Color(0x6638D39F)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color:
                connected ? const Color(0xFF38D39F) : const Color(0xFFFACC15),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFB8C4E6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (actionLabel != null && onTap != null) ...[
            const SizedBox(width: 10),
            TextButton(
              onPressed: onTap,
              child: Text(actionLabel!),
            ),
          ],
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
          title: 'Withdraw to wallet',
          subtitle: 'Move account balance to your linked wallet.',
          onTap: onWithdraw ?? () {},
          disabled: onWithdraw == null,
        ),
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

class _ProfilePictureDialog extends StatefulWidget {
  const _ProfilePictureDialog({
    required this.currentPhotoUrl,
    required this.onRemove,
    required this.onSave,
  });

  final String? currentPhotoUrl;
  final Future<void> Function() onRemove;
  final Future<void> Function(Uint8List bytes) onSave;

  @override
  State<_ProfilePictureDialog> createState() => _ProfilePictureDialogState();
}

class _PlainProfileActionButton extends StatelessWidget {
  const _PlainProfileActionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final foreground =
        enabled ? const Color(0xFF8B5CF6) : const Color(0xFF64748B);
    return Center(
      child: GestureDetector(
        onTap: onPressed,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: foreground.withValues(alpha: 0.75)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: foreground, size: 22),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfilePictureDialogState extends State<_ProfilePictureDialog> {
  final _cropController = CropController();
  Uint8List? _imageBytes;
  bool _busy = false;

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2400,
      imageQuality: 92,
    );
    if (picked == null) {
      return;
    }
    final bytes = await picked.readAsBytes();
    if (!mounted) {
      return;
    }
    setState(() => _imageBytes = bytes);
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    try {
      await widget.onRemove();
      if (!mounted) {
        return;
      }
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile picture removed.')),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _save() {
    if (_imageBytes == null || _busy) {
      return;
    }
    setState(() => _busy = true);
    _cropController.crop();
  }

  Future<void> _handleCropped(CropResult result) async {
    switch (result) {
      case CropSuccess(:final croppedImage):
        try {
          await widget.onSave(croppedImage);
          if (!mounted) {
            return;
          }
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile picture updated.')),
          );
        } catch (e) {
          if (mounted) {
            setState(() => _busy = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(e.toString()), backgroundColor: Colors.red),
            );
          }
        }
      case CropFailure(:final cause):
        if (mounted) {
          setState(() => _busy = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(cause.toString()), backgroundColor: Colors.red),
          );
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cropSide = math.min(MediaQuery.sizeOf(context).width - 92, 360.0);
    return _ProfileDialog(
      title: 'Profile picture',
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_imageBytes == null) ...[
            _ProfileAvatar(
              photoUrl: widget.currentPhotoUrl,
              onTap: null,
              size: 86,
            ),
            const SizedBox(height: 16),
            const Text(
              'Upload a photo, crop it to a square, and we will save it as a clean 256 x 256 avatar.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFFB8C4E6), height: 1.45),
            ),
            const SizedBox(height: 18),
            _PlainProfileActionButton(
              onPressed: _busy ? null : _pickImage,
              icon: Icons.upload_file_outlined,
              label: 'Choose image',
            ),
          ] else ...[
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: SizedBox.square(
                  dimension: cropSide.clamp(220.0, 360.0),
                  child: Crop(
                    image: _imageBytes!,
                    controller: _cropController,
                    aspectRatio: 1,
                    withCircleUi: true,
                    interactive: true,
                    baseColor: const Color(0xFF0B1020),
                    maskColor: Colors.black.withValues(alpha: 0.55),
                    radius: 22,
                    onCropped: _handleCropped,
                    progressIndicator: const Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Drag and zoom to frame your avatar. The server stores the final image at 256 x 256.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF93A4C8), height: 1.4),
            ),
          ],
          if (_busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(minHeight: 3),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _busy ? null : _remove,
          child: const Text('Remove'),
        ),
        if (_imageBytes == null)
          FilledButton(
            onPressed: _busy ? null : _pickImage,
            child: const Text('Upload'),
          )
        else
          FilledButton(
            onPressed: _busy ? null : _save,
            child: const Text('Save'),
          ),
      ],
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
