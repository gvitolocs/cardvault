import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../utils/auth_window_bridge_stub.dart';
import '../wallet/wallet_bridge_stub.dart';
import '../widgets/account_login_card.dart';
import '../widgets/marketplace_navigation_bar.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _wallet = createWalletBridge();
  bool _isLogin = true;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _isWalletLoading = false;
  bool _hasConnectedMetaMask = false;
  bool _autoWalletSignInStarted = false;
  bool _isVerifyingSignup = false;
  bool _isCompletingWalletLink = false;
  bool _closeOnAuthHandled = false;

  String get _returnPath {
    final from = GoRouterState.of(context).uri.queryParameters['from'];
    if (from == null || from.isEmpty || !from.startsWith('/')) {
      return '/profile';
    }
    return from;
  }

  bool get _shouldCloseOnAuth {
    final query = GoRouterState.of(context).uri.queryParameters;
    final closeOnAuth = query['closeOnAuth']?.toLowerCase();
    final extension = query['extension']?.toLowerCase();
    final from = query['from']?.toLowerCase();
    return closeOnAuth == '1' ||
        closeOnAuth == 'true' ||
        extension == '1' ||
        extension == 'true' ||
        from == 'extension';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_hasSignupVerificationToken) {
        _handleSignupVerificationLink();
        return;
      }
      if (_walletLinkSessionId != null) {
        _completeWalletLinkSession();
        return;
      }
      _redirectIfAlreadyLoggedIn();
      _refreshConnectedMetaMask();
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  void _redirectIfAlreadyLoggedIn() {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user != null && mounted) {
      if (_shouldCloseOnAuth) {
        _handleCloseOnAuth();
        return;
      }
      context.go(_returnPath);
    }
  }

  void _handleAuthenticated() {
    if (_shouldCloseOnAuth) {
      _handleCloseOnAuth();
      return;
    }
    context.go(_returnPath);
  }

  void _handleCloseOnAuth() {
    if (_closeOnAuthHandled || !mounted) {
      return;
    }
    _closeOnAuthHandled = true;
    notifyAuthWindowAuthenticated();
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      closeAuthWindow();
    });
  }

  bool get _hasSignupVerificationToken {
    final signupToken =
        GoRouterState.of(context).uri.queryParameters['signupToken'];
    return signupToken != null && signupToken.isNotEmpty;
  }

  String? get _walletLinkSessionId {
    final sessionId =
        GoRouterState.of(context).uri.queryParameters['walletLinkSession'];
    if (sessionId == null || sessionId.isEmpty) {
      return null;
    }
    return sessionId;
  }

  Future<void> _handleSignupVerificationLink() async {
    final signupToken =
        GoRouterState.of(context).uri.queryParameters['signupToken'];
    if (signupToken == null || signupToken.isEmpty || _isVerifyingSignup) {
      return;
    }
    setState(() => _isVerifyingSignup = true);
    try {
      final redirectPath = await ref
          .read(authServiceProvider)
          .verifyEmailSignupToken(signupToken);
      ref.invalidate(authStateProvider);
      ref.invalidate(userProfileProvider);
      ref.invalidate(pknBalanceProvider);
      if (mounted) {
        context.go(_safeReturnPath(redirectPath, fallback: _returnPath));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Email verification failed: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isVerifyingSignup = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authStateProvider, (previous, next) {
      if (_isVerifyingSignup || _hasSignupVerificationToken) {
        return;
      }
      final user = next.valueOrNull;
      if (user != null && mounted) {
        _handleAuthenticated();
      } else if (user == null && mounted) {
        _startAutoWalletSignIn();
      }
    });

    if (_isVerifyingSignup || _isCompletingWalletLink) {
      return const Scaffold(
        backgroundColor: Color(0xFF050816),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_closeOnAuthHandled) {
      return const _ExtensionAuthSuccessScreen();
    }
    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 1.2,
            colors: [Color(0x3338BDF8), Color(0x00050816)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: AccountLoginCard(
                  formKey: _formKey,
                  emailController: _emailController,
                  passwordController: _passwordController,
                  confirmPasswordController: _confirmPasswordController,
                  usernameController: _usernameController,
                  isLogin: _isLogin,
                  isLoading: _isLoading,
                  isGoogleLoading: _isGoogleLoading,
                  isWalletLoading: _isWalletLoading,
                  hasConnectedMetaMask: _hasConnectedMetaMask,
                  onSubmit: _handleSubmit,
                  onGoogle: _handleGoogleSignIn,
                  onCryptoWallet: _handleCryptoWallet,
                  onToggleMode: () {
                    setState(() {
                      _isLogin = !_isLogin;
                    });
                  },
                ),
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: const MarketplaceNavigationBar(selectedIndex: 4),
    );
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final authService = ref.read(authServiceProvider);
      if (_isLogin) {
        await authService.signInWithEmail(
          email: _emailController.text,
          password: _passwordController.text,
        );
      } else {
        await authService.registerWithEmail(
          email: _emailController.text,
          password: _passwordController.text,
          username: _usernameController.text,
          redirectPath: _returnPath,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(kIsWeb
                  ? 'Check your email to verify your account.'
                  : 'Check your email to verify your account, then return '
                      'to the app and sign in.'),
            ),
          );
        }
        return;
      }

      if (mounted) {
        _handleAuthenticated();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleGoogleSignIn() async {
    if (await _connectedMetaMaskAccount() != null) {
      if (mounted) {
        setState(() => _hasConnectedMetaMask = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Disconnect MetaMask or switch to the wallet account flow before using Google.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() {
      _isGoogleLoading = true;
    });

    try {
      await ref.read(authServiceProvider).signInWithGoogle();
      if (mounted) {
        _handleAuthenticated();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Google sign-in failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGoogleLoading = false;
        });
      }
    }
  }

  Future<void> _handleCryptoWallet() async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user != null && !_wallet.hasProvider && _wallet.isMobile) {
      await _openMetaMaskWalletLink();
      return;
    }
    await _signInWithWallet(requestAccount: true);
  }

  Future<void> _openMetaMaskWalletLink() async {
    setState(() => _isWalletLoading = true);
    try {
      final auth = ref.read(authServiceProvider);
      final session =
          await auth.createWalletLinkSession(returnPath: _returnPath);
      final sessionId = session['sessionId'] as String? ?? '';
      if (sessionId.isEmpty) {
        throw StateError('Wallet link session was empty.');
      }
      final url = Uri(
        path: '/auth',
        queryParameters: {
          'walletLinkSession': sessionId,
          'from': _returnPath,
        },
      ).toString();
      if (!_wallet.openMetaMaskDappUrl(url)) {
        throw StateError('Open this page in MetaMask to connect your wallet.');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Opening MetaMask to link this wallet...'),
            backgroundColor: Color(0xFFFACC15),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Wallet link failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isWalletLoading = false);
      }
    }
  }

  Future<void> _completeWalletLinkSession() async {
    final sessionId = _walletLinkSessionId;
    if (sessionId == null || _isCompletingWalletLink) {
      return;
    }
    if (!_wallet.hasProvider) {
      _wallet.openMetaMaskDapp();
      return;
    }
    setState(() => _isCompletingWalletLink = true);
    try {
      await WalletSignInCoordinator.run(() async {
        final account = await _wallet.requestAccount();
        final address = account?.trim().toLowerCase();
        if (address == null || address.isEmpty) {
          throw StateError('No wallet account selected.');
        }
        final auth = ref.read(authServiceProvider);
        final nonce = await auth.requestWalletNonce(address);
        final message = nonce['message'] as String? ?? '';
        if (message.isEmpty) {
          throw StateError('Wallet sign-in nonce was empty.');
        }
        final signature = await _wallet.signMessage(
          address: address,
          message: message,
        );
        final result = await auth.completeWalletLinkSession(
          sessionId: sessionId,
          address: address,
          signature: signature,
        );
        final token = result['customToken'] as String? ?? '';
        if (token.isEmpty) {
          throw StateError('Wallet link token was empty.');
        }
        await auth.signInWithCustomToken(token);
        ref.invalidate(authStateProvider);
        ref.invalidate(userProfileProvider);
        ref.invalidate(pknBalanceProvider);
        final returnPath = _safeReturnPath(
          result['returnPath'] as String?,
          fallback: _returnPath,
        );
        if (mounted) {
          if (_shouldCloseOnAuth) {
            _handleCloseOnAuth();
          } else {
            context.go(returnPath);
          }
        }
      });
    } catch (e) {
      if (mounted) {
        _autoWalletSignInStarted = true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Wallet link failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
        context.go('/auth?from=${Uri.encodeComponent(_returnPath)}');
      }
    } finally {
      if (mounted) {
        setState(() => _isCompletingWalletLink = false);
      }
    }
  }

  Future<void> _signInWithWallet({required bool requestAccount}) async {
    if (!_wallet.hasProvider) {
      if (_wallet.openMetaMaskDapp()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Opening this page in MetaMask...'),
            backgroundColor: Color(0xFFFACC15),
          ),
        );
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

    setState(() {
      _isWalletLoading = true;
    });

    try {
      await WalletSignInCoordinator.run(() async {
        final account = requestAccount
            ? await _wallet.requestAccount()
            : await _wallet.currentAccount();
        final address = account?.trim().toLowerCase();
        if (address == null || address.isEmpty) {
          throw StateError('No wallet account selected.');
        }
        if (mounted) {
          setState(() => _hasConnectedMetaMask = true);
        }

        final auth = ref.read(authServiceProvider);
        final nonce = await auth.requestWalletNonce(address);
        final message = nonce['message'] as String? ?? '';
        if (message.isEmpty) {
          throw StateError('Wallet sign-in nonce was empty.');
        }
        final signature = await _wallet.signMessage(
          address: address,
          message: message,
        );
        final result = await auth.verifyWalletSignature(
          address: address,
          signature: signature,
        );
        final token = result['customToken'] as String? ?? '';
        if (token.isEmpty) {
          throw StateError('Wallet sign-in token was empty.');
        }
        await auth.signInWithCustomToken(token);
        ref.invalidate(authStateProvider);
        ref.invalidate(userProfileProvider);
        ref.invalidate(pknBalanceProvider);
        if (mounted) {
          _handleAuthenticated();
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasConnectedMetaMask = false;
          _autoWalletSignInStarted = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Wallet sign-in failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isWalletLoading = false;
        });
      }
    }
  }

  Future<void> _refreshConnectedMetaMask() async {
    final account = await _connectedMetaMaskAccount();
    if (mounted) {
      setState(() => _hasConnectedMetaMask = account != null);
    }
    if (account != null) {
      await _startAutoWalletSignIn(account);
    }
  }

  Future<void> _startAutoWalletSignIn([String? connectedAccount]) async {
    if (_autoWalletSignInStarted ||
        _isWalletLoading ||
        WalletSignInCoordinator.isSigning ||
        ref.read(authStateProvider).valueOrNull != null) {
      return;
    }
    final account = connectedAccount ?? await _connectedMetaMaskAccount();
    if (account == null) {
      return;
    }
    _autoWalletSignInStarted = true;
    await _signInWithWallet(requestAccount: false);
  }

  Future<String?> _connectedMetaMaskAccount() async {
    if (!_wallet.hasProvider) {
      return null;
    }
    final account = await _wallet.currentAccount();
    final normalized = account?.trim().toLowerCase();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  String _safeReturnPath(String? path, {String fallback = '/profile'}) {
    final clean = path?.trim();
    if (clean == null ||
        clean.isEmpty ||
        !clean.startsWith('/') ||
        clean.startsWith('//') ||
        clean.startsWith('/auth')) {
      return fallback;
    }
    return clean;
  }
}

class _ExtensionAuthSuccessScreen extends StatelessWidget {
  const _ExtensionAuthSuccessScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      body: Center(
        child: Container(
          width: 420,
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF0B1020),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle,
                color: Color(0xFF22C55E),
                size: 34,
              ),
              SizedBox(height: 14),
              Text(
                'Pokoin Extension Authenticated',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'You are signed in. If this page stays open, you can close it and return to the extension.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF93A4C8)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
