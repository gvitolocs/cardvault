import 'package:flutter/material.dart';

class AccountLoginCard extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final TextEditingController usernameController;
  final bool isLogin;
  final bool isLoading;
  final bool isGoogleLoading;
  final bool isWalletLoading;
  final bool hasConnectedMetaMask;
  final VoidCallback onSubmit;
  final VoidCallback onGoogle;
  final VoidCallback onCryptoWallet;
  final VoidCallback onToggleMode;

  const AccountLoginCard({
    super.key,
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.usernameController,
    required this.isLogin,
    required this.isLoading,
    required this.isGoogleLoading,
    required this.isWalletLoading,
    required this.hasConnectedMetaMask,
    required this.onSubmit,
    required this.onGoogle,
    required this.onCryptoWallet,
    required this.onToggleMode,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 20 : 28),
      decoration: BoxDecoration(
        color: const Color(0xEE0B1020),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x66000000), blurRadius: 34, offset: Offset(0, 20)),
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
              onPressed:
                  isGoogleLoading || hasConnectedMetaMask ? null : onGoogle,
              icon: const Icon(Icons.g_mobiledata, size: 28),
              label: Text(isGoogleLoading
                  ? 'Opening Google...'
                  : hasConnectedMetaMask
                      ? 'Google disabled while MetaMask is connected'
                      : 'Continue with Google'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFACC15),
                foregroundColor: const Color(0xFF111827),
                padding: const EdgeInsets.symmetric(vertical: 15),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: isWalletLoading ? null : onCryptoWallet,
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: Text(
                isWalletLoading
                    ? 'Opening MetaMask...'
                    : 'Continue with MetaMask or EVM wallet',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFACC15),
                side: const BorderSide(color: Color(0x66FACC15)),
                padding: const EdgeInsets.symmetric(vertical: 15),
                textStyle: const TextStyle(fontWeight: FontWeight.w900),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
            const SizedBox(height: 18),
            const Row(
              children: [
                Expanded(child: Divider(color: Color(0xFF1E293B))),
                Flexible(
                  flex: 3,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('or use email',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF64748B))),
                  ),
                ),
                Expanded(child: Divider(color: Color(0xFF1E293B))),
              ],
            ),
            const SizedBox(height: 18),
            if (!isLogin) ...[
              _DarkTextField(
                controller: usernameController,
                label: 'Username',
                icon: Icons.person_outline,
                validator: (value) {
                  final clean = value?.trim().toLowerCase() ?? '';
                  if (clean.isEmpty) {
                    return 'Please choose a username';
                  }
                  if (!RegExp(r'^[a-z0-9]{3,32}$').hasMatch(clean)) {
                    return 'Use 3-32 lowercase letters or numbers';
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
            if (!isLogin) ...[
              const SizedBox(height: 14),
              _DarkTextField(
                controller: confirmPasswordController,
                label: 'Retype password',
                icon: Icons.lock_reset_outlined,
                obscureText: true,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please retype your password';
                  }
                  if (value != passwordController.text) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
              ),
            ],
            const SizedBox(height: 22),
            FilledButton(
              onPressed: isLoading ? null : onSubmit,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                textStyle:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(isLogin ? 'Sign in' : 'Create account'),
            ),
            const SizedBox(height: 18),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  isLogin
                      ? "Don't have an account?"
                      : 'Already have an account?',
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
        errorMaxLines: 3,
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
