import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';

import '../constants/project_links.dart';
import '../providers/auth_provider.dart';
import '../providers/marketplace_account_provider.dart';
import '../utils/price_format.dart';
import '../wallet/wallet_bridge_stub.dart';
import '../widgets/site_footer.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late final bridge = createWalletBridge();
  bool _walletListenerAttached = false;
  bool _switchingWalletAccount = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attachWalletAccountListener();
  }

  void _attachWalletAccountListener() {
    if (_walletListenerAttached || !bridge.hasProvider) {
      return;
    }
    _walletListenerAttached = true;
    bridge.onAccountsChanged((address) {
      if (!mounted) {
        return;
      }
      _switchToWalletAccount(address);
    });
  }

  Future<void> _switchToWalletAccount(String? address) async {
    final normalized = address?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      await ref.read(authServiceProvider).signOut();
      ref.invalidate(userProfileProvider);
      ref.invalidate(pknBalanceProvider);
      ref.invalidate(linkedWalletBalanceProvider);
      ref.invalidate(userOrdersProvider);
      ref.invalidate(withdrawRequestsProvider);
      if (mounted) {
        context.go('/wallet');
      }
      return;
    }
    if (_switchingWalletAccount) {
      return;
    }

    final currentProfile = ref.read(userProfileProvider).valueOrNull;
    if (currentProfile?.walletAddress?.trim().toLowerCase() == normalized) {
      ref.invalidate(linkedWalletBalanceProvider);
      return;
    }

    setState(() => _switchingWalletAccount = true);
    try {
      await _signInWithWalletAddress(normalized);
      ref.invalidate(userProfileProvider);
      ref.invalidate(pknBalanceProvider);
      ref.invalidate(linkedWalletBalanceProvider);
      ref.invalidate(userOrdersProvider);
      ref.invalidate(withdrawRequestsProvider);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Wallet account switch failed: $error'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _switchingWalletAccount = false);
      }
    }
  }

  Future<void> _signInWithWalletAddress(String address) async {
    final auth = ref.read(authServiceProvider);
    final nonce = await auth.requestWalletNonce(address);
    final message = nonce['message'] as String? ?? '';
    if (message.isEmpty) {
      throw StateError('Wallet sign-in nonce was empty.');
    }
    final signature =
        await bridge.signMessage(address: address, message: message);
    final result = await auth.verifyWalletSignature(
      address: address,
      signature: signature,
    );
    final token = result['customToken'] as String? ?? '';
    if (token.isEmpty) {
      throw StateError('Wallet sign-in token was empty.');
    }
    await auth.signInWithCustomToken(token);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final profile = ref.watch(userProfileProvider);
    final balanceState = ref.watch(pknBalanceProvider);
    final walletBalanceState = ref.watch(linkedWalletBalanceProvider);
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
                      username: profile?.username ?? '',
                      photoUrl: profile?.photoUrl ?? user?.photoURL,
                      walletAddress: profile?.walletAddress,
                      balance: balance,
                      walletBalance: walletBalanceState.valueOrNull,
                      walletBalanceLoading: walletBalanceState.isLoading,
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
                      onConnectWallet: user == null
                          ? null
                          : () => _connectMetaMaskWallet(
                                context,
                                ref,
                              ),
                      switchingWalletAccount: _switchingWalletAccount,
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

  Future<void> _connectMetaMaskWallet(
      BuildContext context, WidgetRef ref) async {
    final bridge = createWalletBridge();
    if (!bridge.hasProvider) {
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
        await _signInWithWalletAddress(account.trim().toLowerCase());
        ref.invalidate(userProfileProvider);
        ref.invalidate(pknBalanceProvider);
        ref.invalidate(linkedWalletBalanceProvider);
        ref.invalidate(userOrdersProvider);
        ref.invalidate(withdrawRequestsProvider);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Switched to the selected MetaMask account.'),
              backgroundColor: Color(0xFFFACC15),
            ),
          );
        }
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
      final result = await ref.read(authServiceProvider).linkSignedWallet(
            address: account,
            signature: signature,
          );
      ref.invalidate(userProfileProvider);
      ref.invalidate(pknBalanceProvider);
      ref.invalidate(linkedWalletBalanceProvider);
      final converted = _readInt(result['convertedPkn']);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              converted > 0
                  ? 'Wallet connected. $converted PKN queued for payout to your wallet.'
                  : 'Wallet connected. Your profile now shows on-chain wallet balance.',
            ),
            backgroundColor: const Color(0xFFFACC15),
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

  static int _readInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
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
    showDialog<void>(
      context: context,
      builder: (context) => _ProfilePictureDialog(
        currentPhotoUrl: currentPhotoUrl,
        onRemove: () async {
          await ref.read(authServiceProvider).removeProfilePicture();
        },
        onSave: (bytes) async {
          await ref.read(authServiceProvider).uploadProfilePicture(
                imageBytes: bytes,
              );
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
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
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
  final String username;
  final String? photoUrl;
  final String? walletAddress;
  final int balance;
  final String? walletBalance;
  final bool walletBalanceLoading;
  final int ordersCount;
  final int pendingWithdraws;
  final VoidCallback? onEditName;
  final VoidCallback? onEditPhoto;
  final VoidCallback? onConnectWallet;
  final bool switchingWalletAccount;

  const _UserHeader({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.username,
    required this.photoUrl,
    required this.walletAddress,
    required this.balance,
    required this.walletBalance,
    required this.walletBalanceLoading,
    required this.ordersCount,
    required this.pendingWithdraws,
    required this.onEditName,
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
                    if (username.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '@$username',
                        style: const TextStyle(
                          color: Color(0xFFFACC15),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                    if (uid != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'User ID ${_short(uid!)}',
                        style: const TextStyle(
                            color: Color(0xFF64748B), fontSize: 12),
                      ),
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
                label:
                    hasLinkedWallet ? 'Wallet balance' : 'Marketplace balance',
                value: hasLinkedWallet
                    ? walletBalanceLoading
                        ? 'Loading...'
                        : '${walletBalance ?? '0.00'} PKN'
                    : formatPkn(balance, decimals: 0),
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
              _MetricChip(
                label: 'Withdraw requests',
                value: '$pendingWithdraws pending',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            hasLinkedWallet
                ? 'Wallet connected. Your visible PKN balance is the on-chain balance of this wallet; any remaining site credit is only pending treasury payout.'
                : 'Your site balance is a marketplace credit. Connect MetaMask to move that credit to your wallet and use the wallet balance as your main PKN balance.',
            style: const TextStyle(color: Color(0xFFB8C4E6), height: 1.5),
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
          title: 'Manual payout request',
          subtitle:
              'Use only if you need to move remaining site credit manually.',
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
    return _ProfileDialog(
      title: 'Profile picture',
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_imageBytes == null) ...[
            _ProfileAvatar(
                photoUrl: widget.currentPhotoUrl, onTap: null, size: 86),
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
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: SizedBox(
                height: 320,
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
