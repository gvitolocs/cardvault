import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../providers/auth_provider.dart';
import '../providers/cardtrader_integration_provider.dart';
import '../providers/card_listing_provider.dart';
import '../services/cardtrader_integration_service.dart';

class CardTraderConnectScreen extends ConsumerStatefulWidget {
  const CardTraderConnectScreen({super.key});

  @override
  ConsumerState<CardTraderConnectScreen> createState() =>
      _CardTraderConnectScreenState();
}

class _CardTraderConnectScreenState
    extends ConsumerState<CardTraderConnectScreen> {
  final TextEditingController _tokenController = TextEditingController();
  bool _submitting = false;
  bool _disconnecting = false;
  bool _cleaningListings = false;
  bool _dryRunning = false;
  String? _message;
  bool _messageIsError = false;
  CardTraderDryRunSummary? _dryRunSummary;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final statusState = ref.watch(cardTraderConnectionStatusProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: const Color(0xE60A1026),
            title: const Text('Connect CardTrader'),
            actions: [
              TextButton(
                onPressed: () => context.go('/marketplace'),
                child: const Text('Marketplace'),
              ),
              TextButton(
                onPressed: () => context.go('/profile'),
                child: const Text('Profile'),
              ),
              const SizedBox(width: 12),
            ],
          ),
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: user == null
                      ? const _SignInPanel()
                      : statusState.when(
                          data: (status) => _buildConnectedContent(status),
                          loading: () => const _Panel(
                            child: Padding(
                              padding: EdgeInsets.all(36),
                              child: Center(child: CircularProgressIndicator()),
                            ),
                          ),
                          error: (error, _) => _buildErrorContent(error),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectedContent(CardTraderConnectionStatus status) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HeroPanel(
          status: status,
          disconnecting: _disconnecting,
          onDisconnect: status.connected ? _confirmDisconnect : null,
        ),
        const SizedBox(height: 18),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'API token',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Paste your seller CardTrader token once. Pokoin validates it server-side and stores only an encrypted copy. The raw token is never shown again after submission.',
                style: TextStyle(color: Color(0xFFB8C4E6), height: 1.5),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _tokenController,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'\s'))
                ],
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'CardTrader API token',
                  labelStyle: TextStyle(color: Color(0xFFB8C4E6)),
                  helperText:
                      'The token is sent only to Pokoin API over HTTPS.',
                  helperStyle: TextStyle(color: Color(0xFF93A4C8)),
                ),
                onSubmitted: (_) => _connect(),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: _submitting ? null : _connect,
                    icon: _submitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.link),
                    label: Text(
                        status.connected ? 'Reconnect token' : 'Connect token'),
                  ),
                ],
              ),
              if (_message != null) ...[
                const SizedBox(height: 14),
                Text(
                  _message!,
                  style: TextStyle(
                    color: _messageIsError
                        ? const Color(0xFFFCA5A5)
                        : const Color(0xFF86EFAC),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        _StatusDetails(status: status),
        const SizedBox(height: 18),
        _LinkedListingsCleanupPanel(
          loading: _cleaningListings,
          onClean: _confirmCleanLinkedListings,
        ),
        const SizedBox(height: 18),
        _DryRunPanel(
          connected: status.connected,
          loading: _dryRunning,
          summary: _dryRunSummary,
          onRun: _runDryRun,
        ),
      ],
    );
  }

  Widget _buildErrorContent(Object error) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CardTrader status unavailable',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '$error',
            style: const TextStyle(color: Color(0xFFFCA5A5), height: 1.45),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => ref.invalidate(cardTraderConnectionStatusProvider),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Future<void> _connect() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      _setMessage('Paste your CardTrader token first.', isError: true);
      return;
    }
    setState(() {
      _submitting = true;
      _dryRunSummary = null;
    });
    try {
      await ref.read(cardTraderIntegrationServiceProvider).connect(token);
      _tokenController.clear();
      ref.invalidate(cardTraderConnectionStatusProvider);
      _setMessage('CardTrader connected. Token stored encrypted server-side.');
    } catch (error) {
      _setMessage('$error', isError: true);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _confirmDisconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unlink CardTrader?'),
        content: const Text(
          'This disables the encrypted CardTrader token for your seller account. Existing linked listings are not removed unless you clean them separately.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Unlink'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _disconnect();
    }
  }

  Future<void> _disconnect() async {
    setState(() => _disconnecting = true);
    try {
      await ref.read(cardTraderIntegrationServiceProvider).disconnect();
      ref.invalidate(cardTraderConnectionStatusProvider);
      _setMessage(
          'CardTrader disconnected. Stored encrypted secrets were disabled.');
    } catch (error) {
      _setMessage('$error', isError: true);
    } finally {
      if (mounted) {
        setState(() => _disconnecting = false);
      }
    }
  }

  Future<void> _confirmCleanLinkedListings() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clean CardTrader linked listings?'),
        content: const Text(
          'This will inactivate only your Pokoin listings linked to CardTrader. Native Pokoin listings are not touched. This action is intended before reconnecting or replacing imported inventory.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            child: const Text('Clean linked listings'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _cleanLinkedListings();
    }
  }

  Future<void> _cleanLinkedListings() async {
    setState(() => _cleaningListings = true);
    try {
      final result = await ref
          .read(cardTraderIntegrationServiceProvider)
          .cleanLinkedListings();
      ref.invalidate(activeCardListingsProvider);
      final user = ref.read(authStateProvider).valueOrNull;
      if (user != null) {
        ref.invalidate(sellerListingsProvider(user.uid));
      }
      _setMessage(
        result.cleanedCount == 0
            ? 'No CardTrader-linked listings needed cleanup.'
            : 'Cleaned ${result.cleanedCount} CardTrader-linked listing${result.cleanedCount == 1 ? '' : 's'}.',
      );
    } catch (error) {
      _setMessage('$error', isError: true);
    } finally {
      if (mounted) {
        setState(() => _cleaningListings = false);
      }
    }
  }

  Future<void> _runDryRun() async {
    setState(() {
      _dryRunning = true;
      _dryRunSummary = null;
    });
    try {
      final summary =
          await ref.read(cardTraderIntegrationServiceProvider).importDryRun();
      if (mounted) {
        setState(() => _dryRunSummary = summary);
      }
      _setMessage('Dry-run completed without writing inventory.');
    } catch (error) {
      _setMessage('$error', isError: true);
    } finally {
      if (mounted) {
        setState(() => _dryRunning = false);
      }
    }
  }

  void _setMessage(String message, {bool isError = false}) {
    if (!mounted) {
      return;
    }
    setState(() {
      _message = message.replaceFirst('Bad state: ', '');
      _messageIsError = isError;
    });
  }
}

class _SignInPanel extends StatelessWidget {
  const _SignInPanel();

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sign in to connect CardTrader',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Seller integrations are tied to your Firebase account. Sign in first, then return here to store your CardTrader token securely.',
            style: TextStyle(color: Color(0xFFB8C4E6), height: 1.5),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: () => context.go('/auth?from=/marketplace/connect'),
            child: const Text('Sign in'),
          ),
        ],
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.status,
    required this.disconnecting,
    required this.onDisconnect,
  });

  final CardTraderConnectionStatus status;
  final bool disconnecting;
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: const EdgeInsets.all(28),
      gradient: const RadialGradient(
        center: Alignment.topRight,
        radius: 1.3,
        colors: [Color(0x2238BDF8), Color(0x00050816)],
      ),
      child: Wrap(
        spacing: 22,
        runSpacing: 22,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Pill(status.connected ? 'Connected' : 'Not connected'),
                const SizedBox(height: 16),
                Text(
                  'CardTrader seller inventory sync',
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'This first production slice validates your token, stores it encrypted in Firestore, and enables safe inventory import dry-runs. Live two-way stock updates stay disabled until idempotent sync events are in place.',
                  style: TextStyle(
                    color: Color(0xFFB8C4E6),
                    fontSize: 16,
                    height: 1.55,
                  ),
                ),
                if (status.connected) ...[
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: disconnecting ? null : onDisconnect,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                    ),
                    icon: disconnecting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.link_off),
                    label: const Text('Unlink CardTrader'),
                  ),
                ],
              ],
            ),
          ),
          _ConnectionBadge(connected: status.connected),
        ],
      ),
    );
  }
}

class _ConnectionBadge extends StatelessWidget {
  const _ConnectionBadge({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF111936),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: connected ? const Color(0xFF22C55E) : const Color(0xFF475569),
        ),
      ),
      child: Column(
        children: [
          Icon(
            connected ? Icons.verified_user_outlined : Icons.link_off,
            color:
                connected ? const Color(0xFF86EFAC) : const Color(0xFFCBD5E1),
            size: 40,
          ),
          const SizedBox(height: 12),
          Text(
            connected ? 'Connected' : 'Disconnected',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Token remains server-side',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF93A4C8)),
          ),
        ],
      ),
    );
  }
}

class _StatusDetails extends StatelessWidget {
  const _StatusDetails({required this.status});

  final CardTraderConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final metadata = status.metadata;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Connection status',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _StatusTile(
                label: 'State',
                value: status.connected ? 'Connected' : 'Disconnected',
              ),
              _StatusTile(
                label: 'CardTrader user',
                value: metadata?.username.isNotEmpty == true
                    ? metadata!.username
                    : metadata?.userEmail ?? 'Not available',
              ),
              _StatusTile(
                label: 'Seller',
                value: metadata?.sellerName.isNotEmpty == true
                    ? metadata!.sellerName
                    : metadata?.sellerId ?? 'Not available',
              ),
              _StatusTile(
                label: 'Last validated',
                value: _formatDate(status.lastValidatedAt),
              ),
            ],
          ),
          if (metadata != null && metadata.scopes.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final scope in metadata.scopes) _Pill(scope),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 230,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111936),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFFDE68A),
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value.isEmpty ? 'Not available' : value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _LinkedListingsCleanupPanel extends StatelessWidget {
  const _LinkedListingsCleanupPanel({
    required this.loading,
    required this.onClean,
  });

  final bool loading;
  final VoidCallback onClean;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Clean linked listings',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Inactivate only your listings imported or linked from CardTrader. Native Pokoin listings are preserved. You will be asked to confirm before anything changes.',
            style: TextStyle(color: Color(0xFFB8C4E6), height: 1.5),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: loading ? null : onClean,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFFCA5A5),
              side: const BorderSide(color: Color(0xFFEF4444)),
            ),
            icon: loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cleaning_services_outlined),
            label: const Text('Clean CardTrader-linked listings'),
          ),
        ],
      ),
    );
  }
}

class _DryRunPanel extends StatelessWidget {
  const _DryRunPanel({
    required this.connected,
    required this.loading,
    required this.summary,
    required this.onRun,
  });

  final bool connected;
  final bool loading;
  final CardTraderDryRunSummary? summary;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Import dry-run',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Fetch CardTrader products/export and show counts plus a small sample only. This does not create, update, or delete Pokoin listings.',
            style: TextStyle(color: Color(0xFFB8C4E6), height: 1.5),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: connected && !loading ? onRun : null,
            icon: loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.fact_check_outlined),
            label: const Text('Run dry-run'),
          ),
          if (summary != null) ...[
            const SizedBox(height: 18),
            Text(
              'Products found: ${summary!.productCount}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 12),
            for (final item in summary!.sample)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  [
                    item.name.isEmpty
                        ? 'CardTrader product ${item.id}'
                        : item.name,
                    if (item.blueprintId.isNotEmpty)
                      'blueprint ${item.blueprintId}',
                    'qty ${item.quantity}',
                  ].join(' · '),
                  style: const TextStyle(color: Color(0xFFE5E7EB)),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.gradient,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: const Color(0xCC0B1024),
        gradient: gradient,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 34,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0x1AFACC15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x55FACC15)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFFFDE68A),
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

String _formatDate(DateTime? value) {
  if (value == null) {
    return 'Not available';
  }
  return DateFormat.yMMMd().add_Hm().format(value.toLocal());
}
