import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'auth_service.dart';
import 'wallet_bridge_stub.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PokoinApp());
}

class PokoinApp extends StatelessWidget {
  const PokoinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pokoin Wallet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF050816),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFACC15),
          secondary: Color(0xFF38BDF8),
          surface: Color(0xFF0B1020),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF111936),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        ),
        useMaterial3: true,
      ),
      home: const WalletHomePage(),
    );
  }
}

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class WalletHomePage extends WalletScreen {
  const WalletHomePage({super.key});
}

class _WalletScreenState extends State<WalletScreen> {
  static const rpcUrl = 'https://rpc.pokoin.com/rpc';
  static const nativeSymbol = 'PKN';
  static const recentRecipientLimit = 5;

  final WalletAuthService _auth = WalletAuthService();
  final WalletBridge _wallet = createWalletBridge();
  final TextEditingController _toController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final List<ActivityItem> _activity = <ActivityItem>[];
  final List<String> _recipientSuggestions = <String>[];

  String? _address;
  WalletUser? _user;
  String? _username;
  String _balance = '0';
  bool _loading = false;
  String? _error;
  int _recipientSearchToken = 0;

  @override
  void dispose() {
    _toController.dispose();
    _amountController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _syncConnectedWallet();
    if (_wallet.hasProvider) {
      _wallet.onAccountsChanged((address) {
        if (!mounted) {
          return;
        }
        if (address == null) {
          _handleWalletDisconnected();
          return;
        }
        setState(() {
          _address = address;
        });
        _loadBalance(address);
      });
      _wallet.onChainChanged(() {
        if (_address != null) {
          _loadBalance(_address!);
        }
      });
    }
    _auth.authState.listen((user) {
      if (mounted) {
        setState(() => _user = user);
        _loadUsername();
        _loadLinkedWallet();
      }
    });
  }

  Future<void> _handleWalletDisconnected() async {
    setState(() {
      _address = null;
      _balance = '0';
      _username = null;
      _recipientSuggestions.clear();
    });
    await _auth.signOut();
    if (mounted) {
      _showMessage('MetaMask disconnected. You have been logged out.');
    }
  }

  Future<void> _refreshAll() async {
    await _syncConnectedWallet();
    await _loadLinkedWallet();
    await Future.wait(<Future<void>>[
      if (_address != null) _loadBalance(_address!),
    ]);
  }

  Future<void> _syncConnectedWallet() async {
    if (!_wallet.hasProvider) {
      return;
    }
    final address = await _wallet.currentAccount();
    if (!mounted || address == null || address == _address) {
      return;
    }
    setState(() => _address = address);
    await _loadBalance(address);
  }

  Future<void> _loadLinkedWallet() async {
    final address = await _auth.linkedWalletAddress();
    if (!mounted || address == null || address == _address) {
      return;
    }
    setState(() => _address = address);
    await _loadBalance(address);
  }

  Future<void> _loadUsername() async {
    final username = await _auth.ensureUsername();
    if (!mounted || username == null || username == _username) {
      return;
    }
    setState(() => _username = username);
  }

  Future<void> _connectWallet() async {
    if (!_wallet.hasProvider) {
      _showMessage('Install MetaMask or another EVM browser wallet first.');
      return;
    }

    await _runTask(() async {
      final account = await _wallet.requestAccount();
      if (account == null) {
        throw Exception('No wallet account selected');
      }
      final nonce = await _auth.requestWalletNonce(account);
      final message = nonce['message'];
      if (message == null || message.isEmpty) {
        throw Exception('Wallet sign-in nonce was empty.');
      }
      final signature = await _wallet.signMessage(
        address: account,
        message: message,
      );
      final verified = await _auth.verifyWalletSignature(
        address: account,
        signature: signature,
      );
      final customToken = verified['customToken'];
      if (customToken == null || customToken.isEmpty) {
        throw Exception('Wallet sign-in token was empty.');
      }
      await _auth.signInWithCustomToken(customToken);
      await _wallet.addNetwork();
      await _wallet.switchNetwork();
      await _loadBalance(account);
      setState(() {
        _address = account;
      });
      _record('Wallet signed in', account, ActivityKind.inbound);
    });
  }

  Future<void> _loadBalance(String address) async {
    final result = await _rpc('eth_getBalance', <Object>[address, 'latest']);
    if (!mounted) {
      return;
    }
    setState(() => _balance = _formatWei(_hexToBigInt(result as String)));
  }

  Future<void> _openSendSheet() async {
    final balanceWei = _parsePknToWei(_balance) ?? BigInt.zero;
    _recipientSuggestions.clear();
    var loadedRecentRecipients = false;

    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (_toController.text.trim().isEmpty &&
                _recipientSuggestions.isEmpty &&
                !loadedRecentRecipients) {
              loadedRecentRecipients = true;
              _showRecentRecipientSuggestions(setDialogState);
            }
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                    22,
                    22,
                    22,
                    22 + MediaQuery.of(dialogContext).viewInsets.bottom,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xF20B1020),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                    boxShadow: const <BoxShadow>[
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
                    children: <Widget>[
                      const Text(
                        'Send PKN',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Use a Pokoin username for site balance transfers, or a 0x address to send from your connected MetaMask wallet.',
                        style: TextStyle(color: Color(0xFFB8C4E6)),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _toController,
                        keyboardType: TextInputType.text,
                        onTap: () {
                          if (_toController.text.trim().isEmpty) {
                            _showRecentRecipientSuggestions(setDialogState);
                          }
                        },
                        onChanged: (value) {
                          _searchRecipientSuggestions(value, setDialogState);
                        },
                        decoration: const InputDecoration(
                          labelText: 'Recipient username or 0x address',
                          prefixIcon: Icon(Icons.person_search_outlined),
                        ),
                      ),
                      if (_recipientSuggestions.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            for (final recipient in _recipientSuggestions)
                              ActionChip(
                                label: Text(recipient),
                                avatar: const Icon(
                                  Icons.history,
                                  size: 16,
                                ),
                                onPressed: () {
                                  _toController.text = recipient;
                                  _recipientSuggestions.clear();
                                  setDialogState(() {});
                                },
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Amount in PKN',
                          prefixIcon: Icon(Icons.payments_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: <Widget>[
                          _PercentButton(
                            label: '25%',
                            onTap: () => _setAmountPercent(balanceWei, 0.25),
                          ),
                          _PercentButton(
                            label: '50%',
                            onTap: () => _setAmountPercent(balanceWei, 0.50),
                          ),
                          _PercentButton(
                            label: '100%',
                            onTap: () => _setAmountPercent(balanceWei, 1.00),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: TextButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: () {
                                Navigator.of(dialogContext).pop();
                                _sendTransaction();
                              },
                              icon: const Icon(Icons.send_rounded),
                              label: const Text('Send'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _searchRecipientSuggestions(
    String value,
    void Function(VoidCallback fn) setDialogState,
  ) async {
    final token = ++_recipientSearchToken;
    final query = value.trim();
    if (query.isEmpty) {
      await _showRecentRecipientSuggestions(setDialogState, token: token);
      return;
    }
    if (query.length < 2 || query.contains('@') || _isAddress(query)) {
      _recipientSuggestions.clear();
      setDialogState(() {});
      return;
    }
    try {
      final results = await _auth.searchRecipientUsernames(query);
      if (!mounted || token != _recipientSearchToken) {
        return;
      }
      _recipientSuggestions
        ..clear()
        ..addAll(results);
      setDialogState(() {});
    } catch (_) {
      if (!mounted || token != _recipientSearchToken) {
        return;
      }
      _recipientSuggestions.clear();
      setDialogState(() {});
    }
  }

  Future<void> _showRecentRecipientSuggestions(
    void Function(VoidCallback fn) setDialogState, {
    int? token,
  }) async {
    final recent = await _loadRecentRecipients();
    if (!mounted || (token != null && token != _recipientSearchToken)) {
      return;
    }
    _recipientSuggestions
      ..clear()
      ..addAll(recent);
    setDialogState(() {});
  }

  Future<void> _sendTransaction() async {
    final recipient = _toController.text.trim();
    final amount = _amountController.text.trim();
    final accountAmount = int.tryParse(amount);

    if (!_isAddress(recipient)) {
      if (accountAmount == null || accountAmount <= 0) {
        _showMessage('Username transfers use whole PKN amounts.');
        return;
      }
      if (!RegExp(r'^[a-zA-Z0-9_]{3,32}$').hasMatch(recipient)) {
        _showMessage('Enter a valid username or 0x address.');
        return;
      }
      await _runTask(() async {
        await _auth.transferAccountBalance(
          recipientUsername: recipient,
          amountPkn: accountAmount,
        );
        await _rememberRecipient(recipient);
        _toController.clear();
        _amountController.clear();
        _record(
          'Sent $accountAmount PKN to account',
          recipient,
          ActivityKind.outbound,
        );
        _showMessage('Account balance transfer sent.');
      });
      return;
    }

    if (accountAmount == null || accountAmount <= 0) {
      _showMessage('0x transfers use whole PKN amounts.');
      return;
    }

    final from = _address?.trim();
    if (from != null && from.isNotEmpty) {
      await _runTask(() async {
        final hash = await _wallet.sendTransaction(
          from: from,
          to: recipient,
          valueWei: BigInt.from(accountAmount) * BigInt.from(10).pow(18),
        );
        await _rememberRecipient(recipient);
        await _loadBalance(from);
        _toController.clear();
        _amountController.clear();
        _record(
          'Sent $accountAmount PKN on-chain',
          hash,
          ActivityKind.outbound,
        );
        _showMessage('On-chain transaction sent.');
      });
      return;
    }

    if (_user == null) {
      _showMessage('Connect MetaMask or log in before sending PKN.');
      return;
    }

    await _runTask(() async {
      await _auth.requestPknWithdraw(
        toAddress: recipient,
        amountPkn: accountAmount,
      );
      await _rememberRecipient(recipient);
      _toController.clear();
      _amountController.clear();
      _record(
        'Requested $accountAmount PKN withdraw',
        recipient,
        ActivityKind.outbound,
      );
      _showMessage(
        'Withdraw request created. An operator will send PKN from the site treasury account.',
      );
    });
  }

  void _setAmountPercent(BigInt balanceWei, double percent) {
    final selected =
        (balanceWei * BigInt.from((percent * 100).round())) ~/ BigInt.from(100);
    _amountController.text = _formatWei(selected);
  }

  String? get _recentRecipientKey {
    final accountKey = (_user?.uid ?? _address)?.trim().toLowerCase();
    if (accountKey == null || accountKey.isEmpty) {
      return null;
    }
    return 'pokoin_wallet_recent_recipients:$accountKey';
  }

  Future<List<String>> _loadRecentRecipients() async {
    final key = _recentRecipientKey;
    if (key == null) {
      return const <String>[];
    }
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(key) ?? const <String>[])
        .where((recipient) => recipient.trim().isNotEmpty)
        .take(recentRecipientLimit)
        .toList(growable: false);
  }

  Future<void> _rememberRecipient(String recipient) async {
    final key = _recentRecipientKey;
    if (key == null) {
      return;
    }
    final normalized = _isAddress(recipient)
        ? recipient.trim().toLowerCase()
        : recipient.trim().toLowerCase();
    if (normalized.isEmpty) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final previous = prefs.getStringList(key) ?? const <String>[];
    final updated = <String>[
      normalized,
      ...previous.where((item) => item.trim().toLowerCase() != normalized),
    ].take(recentRecipientLimit).toList(growable: false);
    await prefs.setStringList(key, updated);
  }

  Future<Object?> _rpc(String method, List<Object> params) async {
    final response = await http
        .post(
          Uri.parse(rpcUrl),
          headers: const <String, String>{'content-type': 'application/json'},
          body: jsonEncode(<String, Object>{
            'jsonrpc': '2.0',
            'id': DateTime.now().microsecondsSinceEpoch,
            'method': method,
            'params': params,
          }),
        )
        .timeout(const Duration(seconds: 10));

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400 || payload['error'] != null) {
      throw Exception(payload['error'] ?? 'RPC HTTP ${response.statusCode}');
    }
    return payload['result'];
  }

  Future<void> _runTask(Future<void> Function() task) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await task();
    } catch (error) {
      if (mounted) {
        final message = _friendlyError(error);
        setState(() => _error = message);
        _showMessage(message);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  static String _friendlyError(Object error) {
    final text = error.toString();
    if (text == '[object Object]' || text.contains('JSObject')) {
      return 'The wallet rejected the request or returned an unsupported error. Check MetaMask and try again.';
    }
    return text
        .replaceFirst('Exception: ', '')
        .replaceFirst('Bad state: ', '')
        .replaceFirst('Invalid argument(s): ', '');
  }

  void _record(String title, String detail, ActivityKind kind) {
    setState(() {
      _activity.insert(
        0,
        ActivityItem(
          title: title,
          detail: detail,
          kind: kind,
          at: DateTime.now(),
        ),
      );
      if (_activity.length > 10) {
        _activity.removeLast();
      }
    });
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handleEmailAuth() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (!email.contains('@') || password.length < 6) {
      _showMessage(
        'Enter a valid email and a password with at least 6 characters.',
      );
      return;
    }

    await _runTask(() async {
      await _auth.signInWithEmail(email, password);
      _passwordController.clear();
      _showMessage('Logged in.');
    });
  }

  Future<void> _handleGoogleAuth() async {
    await _runTask(() async {
      await _auth.signInWithGoogle();
      _showMessage('Logged in with Google.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 860;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshAll,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 44),
            children: <Widget>[
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _TopBar(
                        onOpenHome: () =>
                            _openUrl('https://pokoin.com/marketplace'),
                      ),
                      const SizedBox(height: 20),
                      _buildAuthPanel(),
                      if (_error != null) _ErrorBanner(message: _error!),
                      if (_loading) const LinearProgressIndicator(),
                      const SizedBox(height: 14),
                      Align(
                        alignment: Alignment.center,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: wide ? 760 : double.infinity,
                          ),
                          child: _buildWalletPanel(),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _buildActions(),
                      if (_activity.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 22),
                        _buildActivity(),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWalletPanel() {
    final hasConnectedWallet = (_address ?? '').trim().isNotEmpty;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Live PKN balance',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 10),
          Text(
            '$_balance $nativeSymbol',
            style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          SelectableText(
            _address ?? 'No wallet connected',
            style: const TextStyle(
              color: Color(0xFFCBD5E1),
              fontFamily: 'monospace',
            ),
          ),
          if (!hasConnectedWallet) ...<Widget>[
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: _connectWallet,
                  icon: const Icon(Icons.account_balance_wallet),
                  label: const Text('Sign in with MetaMask'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _runTask(() async {
                    await _wallet.addNetwork();
                    await _wallet.switchNetwork();
                    _showMessage('PokoinPoS network added or selected.');
                  }),
                  icon: const Icon(Icons.add_link),
                  label: const Text('Add Pokoin network'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAuthPanel() {
    return StreamBuilder<WalletUser?>(
      stream: _auth.authState,
      builder: (context, snapshot) {
        final user = snapshot.data;
        final hasConnectedWallet = (_address ?? '').trim().isNotEmpty;
        if (user != null || hasConnectedWallet) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Login to Pokoin',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Use the same account as pokoin.com. Wallet connection remains separate and optional.',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: _handleEmailAuth,
                      icon: const Icon(Icons.login),
                      label: const Text('Login'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _handleGoogleAuth,
                      icon: const Icon(Icons.g_mobiledata),
                      label: const Text('Google'),
                    ),
                    TextButton(
                      onPressed: _connectWallet,
                      child: const Text('Connect crypto wallet'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActions() {
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      alignment: WrapAlignment.center,
      children: <Widget>[
        _QuickActionButton(
          icon: Icons.arrow_upward_rounded,
          label: 'Send',
          onTap: _openSendSheet,
        ),
        _QuickActionButton(
          icon: Icons.arrow_downward_rounded,
          label: 'Receive',
          onTap: () {
            if ((_user?.email ?? '').isEmpty && _address == null) {
              _showMessage('Log in or connect a wallet first.');
              return;
            }
            _showAddressDialog();
          },
        ),
        _QuickActionButton(
          icon: Icons.currency_exchange,
          label: 'wPKN',
          onTap: () => _openUrl(
            'https://pancakeswap.finance/swap?outputCurrency=0x91A17E2bddfF839078BD395482B38e4AC15276f4&chain=bsc',
          ),
        ),
        _QuickActionButton(
          icon: Icons.shopping_cart_checkout,
          label: 'Buy',
          onTap: () => _openUrl('https://pokoin.com/buy'),
        ),
        _QuickActionButton(
          icon: Icons.person_outline,
          label: 'Profile',
          onTap: () => _openUrl('https://pokoin.com/profile'),
        ),
      ],
    );
  }

  Widget _buildActivity() {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Recent activity',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          if (_activity.isEmpty)
            const Text(
              'Connect a wallet, watch an address, or submit a transaction to see activity here.',
              style: TextStyle(color: Colors.white70),
            )
          else
            for (final item in _activity)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: item.kind == ActivityKind.inbound
                      ? const Color(0x2238D39F)
                      : const Color(0x22FF5F7A),
                  child: Icon(
                    item.kind == ActivityKind.inbound
                        ? Icons.call_received_rounded
                        : Icons.call_made_rounded,
                    color: item.kind == ActivityKind.inbound
                        ? const Color(0xFF38D39F)
                        : const Color(0xFFFF5F7A),
                  ),
                ),
                title: Text(item.title),
                subtitle: SelectableText(item.detail),
                trailing: Text(_formatDate(item.at)),
              ),
        ],
      ),
    );
  }

  Future<void> _showAddressDialog() async {
    final address = _address?.trim();
    final hasWallet = address != null && address.isNotEmpty;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Receive PKN'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (hasWallet) ...<Widget>[
              const Text(
                'Receive on your linked crypto wallet',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              SelectableText(
                address,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ] else ...<Widget>[
              const Text(
                'Receive on your account balance',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              SelectableText(
                _username == null || _username!.isEmpty
                    ? 'Log in to receive by username.'
                    : _username!,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ],
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  static bool _isAddress(String value) {
    return RegExp(r'^0x[a-fA-F0-9]{40}$').hasMatch(value);
  }

  static BigInt _hexToBigInt(String hex) {
    final clean = hex.startsWith('0x') ? hex.substring(2) : hex;
    if (clean.isEmpty) {
      return BigInt.zero;
    }
    return BigInt.parse(clean, radix: 16);
  }

  static String _formatWei(BigInt wei) {
    final base = BigInt.from(10).pow(18);
    final whole = wei ~/ base;
    final fraction = wei.remainder(base).toString().padLeft(18, '0');
    final compactFraction = fraction.substring(0, math.min(2, fraction.length));
    return '$whole.${compactFraction.padRight(2, '0')}';
  }

  static BigInt? _parsePknToWei(String value) {
    final clean = value.trim().replaceAll(',', '.');
    if (!RegExp(r'^\d+(\.\d{1,18})?$').hasMatch(clean)) {
      return null;
    }
    final parts = clean.split('.');
    final whole = BigInt.parse(parts[0]);
    final fraction = parts.length == 2 ? parts[1].padRight(18, '0') : '0' * 18;
    return whole * BigInt.from(10).pow(18) + BigInt.parse(fraction);
  }

  static String _formatDate(DateTime at) {
    final minute = at.minute.toString().padLeft(2, '0');
    final day = at.day.toString().padLeft(2, '0');
    final month = at.month.toString().padLeft(2, '0');
    return '$day/$month ${at.hour}:$minute';
  }

  static Future<void> _openUrl(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onOpenHome});

  final VoidCallback onOpenHome;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: const Color(0xFF111936),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white24),
          ),
          padding: const EdgeInsets.all(6),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              'https://pokoin.com/pokoin-512.png',
              filterQuality: FilterQuality.none,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.account_balance_wallet_outlined,
                color: Color(0xFFFACC15),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Pokoin Wallet',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              Text(
                'Live wallet for PokoinPoS',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
        FilledButton.icon(
          onPressed: onOpenHome,
          icon: const Icon(Icons.storefront, size: 18),
          label: const Text('Shop'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFFACC15),
            foregroundColor: const Color(0xFF111827),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            textStyle: const TextStyle(fontWeight: FontWeight.w900),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xCC0B1020),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 32,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x33F97316),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x99F97316)),
      ),
      child: Text(message),
    );
  }
}

class _PercentButton extends StatelessWidget {
  const _PercentButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFFACC15),
        side: const BorderSide(color: Color(0x99FACC15)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      child: Text(label),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 78,
      child: _HoverCircleAction(icon: icon, label: label, onTap: onTap),
    );
  }
}

class _HoverCircleAction extends StatefulWidget {
  const _HoverCircleAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_HoverCircleAction> createState() => _HoverCircleActionState();
}

class _HoverCircleActionState extends State<_HoverCircleAction> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _hovering ? const Color(0x1AFACC15) : Colors.transparent,
                boxShadow: _hovering
                    ? const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x66FACC15),
                          blurRadius: 22,
                          spreadRadius: 1,
                        ),
                      ]
                    : const <BoxShadow>[],
              ),
              child: Icon(
                widget.icon,
                color: const Color(0xFFFACC15),
                size: 30,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

enum ActivityKind { inbound, outbound }

class ActivityItem {
  ActivityItem({
    required this.title,
    required this.detail,
    required this.kind,
    required this.at,
  });

  final String title;
  final String detail;
  final ActivityKind kind;
  final DateTime at;
}
