import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../constants/project_links.dart';
import '../providers/auth_provider.dart';
import '../widgets/site_footer.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isLogin = true;
  bool _isLoading = false;
  bool _isGoogleLoading = false;

  String get _returnPath {
    final from = GoRouterState.of(context).uri.queryParameters['from'];
    if (from == null || from.isEmpty || !from.startsWith('/')) {
      return '/profile';
    }
    return from;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _redirectIfAlreadyLoggedIn();
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _redirectIfAlreadyLoggedIn() {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user != null && mounted) {
      context.go(_returnPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authStateProvider, (previous, next) {
      final user = next.valueOrNull;
      if (user != null && mounted) {
        context.go(_returnPath);
      }
    });

    final compact = MediaQuery.sizeOf(context).width < 860;
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
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Column(
                  children: [
                    Flex(
                      direction: compact ? Axis.vertical : Axis.horizontal,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          flex: compact ? 0 : 1,
                          child: const _AuthStoryPanel(),
                        ),
                        SizedBox(width: compact ? 0 : 28, height: compact ? 24 : 0),
                        Expanded(
                          flex: compact ? 0 : 1,
                          child: _AuthFormPanel(
                            formKey: _formKey,
                            emailController: _emailController,
                            passwordController: _passwordController,
                            nameController: _nameController,
                            isLogin: _isLogin,
                            isLoading: _isLoading,
                            isGoogleLoading: _isGoogleLoading,
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
                      ],
                    ),
                    const SiteFooter(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
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
          displayName: _nameController.text,
        );
      }
      
      if (mounted) {
        context.go(_returnPath);
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
    setState(() {
      _isGoogleLoading = true;
    });

    try {
      await ref.read(authServiceProvider).signInWithGoogle();
      if (mounted) {
        context.go(_returnPath);
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

  void _handleCryptoWallet() {
    context.go('/wallet');
  }
}

class _AuthStoryPanel extends StatelessWidget {
  const _AuthStoryPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: const Color(0xCC0B1020),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: const Color(0xFF111936),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: const Icon(Icons.style, color: Color(0xFFFACC15), size: 30),
              ),
              const SizedBox(width: 14),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CardVault',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    'Collector account + PKN wallet',
                    style: TextStyle(color: Color(0xFF93A4C8), fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 28),
          Center(
            child: Container(
              width: 210,
              height: 210,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF111936),
                borderRadius: BorderRadius.circular(42),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                boxShadow: const [
                  BoxShadow(color: Color(0x66000000), blurRadius: 30, offset: Offset(0, 18)),
                ],
              ),
              child: Image.network(
                ProjectLinks.logoLarge,
                filterQuality: FilterQuality.none,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(height: 28),
          const Text(
            'Sign in once. Keep your Pokoin profile, wallet and marketplace activity connected.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              height: 1.05,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Your account unlocks CardVault marketplace features, persistent wallet access, PKN withdraw requests and PokoinScan activity from the same session.',
            style: TextStyle(color: Color(0xFFB8C4E6), fontSize: 15, height: 1.55),
          ),
          const SizedBox(height: 22),
          const Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _TrustPill(icon: Icons.lock_outline, label: 'Persistent login'),
              _TrustPill(icon: Icons.account_balance_wallet_outlined, label: 'PKN wallet'),
              _TrustPill(icon: Icons.query_stats, label: 'PokoinScan'),
            ],
          ),
        ],
      ),
    );
  }
}

class _AuthFormPanel extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController nameController;
  final bool isLogin;
  final bool isLoading;
  final bool isGoogleLoading;
  final VoidCallback onSubmit;
  final VoidCallback onGoogle;
  final VoidCallback onCryptoWallet;
  final VoidCallback onToggleMode;

  const _AuthFormPanel({
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.nameController,
    required this.isLogin,
    required this.isLoading,
    required this.isGoogleLoading,
    required this.onSubmit,
    required this.onGoogle,
    required this.onCryptoWallet,
    required this.onToggleMode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: const Color(0xEE0B1020),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), blurRadius: 34, offset: Offset(0, 20)),
        ],
      ),
      child: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isLogin ? 'Access your account' : 'Create your account',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isLogin
                  ? 'Continue to your wallet, profile and marketplace dashboard.'
                  : 'Create a profile for marketplace balance, wallet links and future seller tools.',
              style: const TextStyle(color: Color(0xFF93A4C8), height: 1.45),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: isGoogleLoading ? null : onGoogle,
              icon: const Icon(Icons.g_mobiledata, size: 28),
              label: Text(isGoogleLoading ? 'Opening Google...' : 'Continue with Google'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFACC15),
                foregroundColor: const Color(0xFF111827),
                padding: const EdgeInsets.symmetric(vertical: 15),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onCryptoWallet,
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: const Text('Continue with crypto wallet'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFACC15),
                side: const BorderSide(color: Color(0x66FACC15)),
                padding: const EdgeInsets.symmetric(vertical: 15),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 18),
            const Row(
              children: [
                Expanded(child: Divider(color: Color(0xFF1E293B))),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('or use email', style: TextStyle(color: Color(0xFF64748B))),
                ),
                Expanded(child: Divider(color: Color(0xFF1E293B))),
              ],
            ),
            const SizedBox(height: 18),
            if (!isLogin) ...[
              _DarkTextField(
                controller: nameController,
                label: 'Full name',
                icon: Icons.person_outline,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter your name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
            ],
            _DarkTextField(
              controller: emailController,
              label: 'Email',
              icon: Icons.mail_outline,
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter your email';
                }
                if (!value.contains('@')) {
                  return 'Please enter a valid email';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            _DarkTextField(
              controller: passwordController,
              label: 'Password',
              icon: Icons.lock_outline,
              obscureText: true,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your password';
                }
                if (value.length < 6) {
                  return 'Password must be at least 6 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: isLoading ? null : onSubmit,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(isLogin ? 'Sign in' : 'Create account'),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  isLogin ? "Don't have an account?" : 'Already have an account?',
                  style: const TextStyle(color: Color(0xFF93A4C8)),
                ),
                TextButton(
                  onPressed: onToggleMode,
                  child: Text(isLogin ? 'Sign up' : 'Sign in'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DarkTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _DarkTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
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
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
      ),
      validator: validator,
    );
  }
}

class _TrustPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _TrustPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFFFACC15)),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFE2E8F0),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
