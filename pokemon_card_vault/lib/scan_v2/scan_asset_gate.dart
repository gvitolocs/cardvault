import 'dart:io';

import 'package:flutter/material.dart';

import 'scan_assets.dart';

typedef ScanAssetInspector = Future<ScanAssetStatus> Function(String gallery);

/// Bundled packs are prepared automatically. This is an error boundary, not a
/// setup step: a healthy installation opens the camera without user action.
class ScanAssetGate extends StatefulWidget {
  const ScanAssetGate({super.key, required this.builder, this.inspect});

  final Widget Function(BuildContext context, String gallery) builder;
  final ScanAssetInspector? inspect;

  @override
  State<ScanAssetGate> createState() => _ScanAssetGateState();
}

class _ScanAssetGateState extends State<ScanAssetGate> {
  static const _gallery = 'western';
  ScanAssetStatus? _status;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final inspect = widget.inspect;
      final status = await (inspect != null
          ? inspect(_gallery)
          : Platform.isAndroid
              ? ScanAssetStore.prepareAndroidBundle(gallery: _gallery)
              : ScanAssetStore.inspect(gallery: _gallery));
      if (mounted) setState(() => _status = status);
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = 'Impossibile preparare i modelli dello scanner. Riprova.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    if (!_busy && _error == null && status?.ready == true) {
      return widget.builder(context, _gallery);
    }
    return Material(
      color: const Color(0xFF070B18),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.document_scanner_outlined,
                      size: 48, color: Color(0xFFFACC15)),
                  const SizedBox(height: 16),
                  Text(
                      _busy
                          ? 'Preparazione scanner'
                          : 'Scanner non disponibile',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  Text(
                    _busy
                        ? 'Preparazione automatica dei modelli inclusi nell’app…'
                        : _error ??
                            'Questa versione non contiene tutti i file necessari '
                                'al riconoscimento. Serve una build completa '
                                'dell’app; non devi scaricare pacchetti a mano.',
                    style: const TextStyle(color: Color(0xFFBAC5E0)),
                  ),
                  if (_busy) ...[
                    const SizedBox(height: 20),
                    const LinearProgressIndicator(),
                  ],
                  if (!_busy && status != null && !status.ready)
                    ExpansionTile(
                      title: const Text('Dettagli tecnici'),
                      children: [
                        for (final file in status.missing)
                          ListTile(dense: true, title: Text(file)),
                      ],
                    ),
                  if (!_busy) ...[
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: _prepare,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Riprova'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
