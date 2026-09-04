import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../utils/auth_window_bridge_stub.dart';

class ExtensionAuthBridgeScreen extends ConsumerStatefulWidget {
  const ExtensionAuthBridgeScreen({super.key});

  @override
  ConsumerState<ExtensionAuthBridgeScreen> createState() =>
      _ExtensionAuthBridgeScreenState();
}

class _ExtensionAuthBridgeScreenState
    extends ConsumerState<ExtensionAuthBridgeScreen> {
  String _status = 'Preparing Pokoin extension auth bridge...';
  bool _posted = false;

  @override
  void initState() {
    super.initState();
    unawaited(_postToken());
  }

  Future<void> _postToken() async {
    try {
      await ref.read(authBootstrapProvider.future);
      final forceRefresh = Uri.base.queryParameters['forceRefresh'] == '1' ||
          Uri.base.queryParameters['forceRefresh'] == 'true';
      final token = await ref
          .read(pokoinApiAuthServiceProvider)
          .currentToken(forceRefresh: forceRefresh);
      if (!mounted) return;
      if (token == null) {
        _post({
          'type': 'pokoin-auth-token',
          'ok': false,
          'status': 'signed_out',
          'message': 'No active Pokoin session.',
        });
        setState(() {
          _status = 'No active Pokoin session. Sign in on pokoin.com first.';
          _posted = true;
        });
        return;
      }
      _post({
        'type': 'pokoin-auth-token',
        'ok': true,
        'status': 'authenticated',
        'token': token.toJson(),
      });
      setState(() {
        _status = 'Pokoin session token sent to the extension.';
        _posted = true;
      });
      _closeAfterAuth();
    } catch (error) {
      if (!mounted) return;
      _post({
        'type': 'pokoin-auth-token',
        'ok': false,
        'status': 'error',
        'message': '$error',
      });
      setState(() {
        _status = 'Unable to read the Pokoin session: $error';
        _posted = true;
      });
    }
  }

  void _post(Map<String, Object?> payload) {
    postAuthBridgeMessage(payload, _targetOrigin());
  }

  String _targetOrigin() {
    final requested = Uri.base.queryParameters['targetOrigin'] ?? '';
    if (requested.startsWith('chrome-extension://')) {
      return requested;
    }
    return '*';
  }

  void _closeAfterAuth() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      closeAuthWindow();
    });
  }

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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _posted ? Icons.check_circle : Icons.sync,
                color:
                    _posted ? const Color(0xFF22C55E) : const Color(0xFFFACC15),
                size: 34,
              ),
              const SizedBox(height: 14),
              const Text(
                'Pokoin Extension Auth',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF93A4C8)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
