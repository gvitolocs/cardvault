import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
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
  const WalletScreen({super.key, this.initialSwapOpen = false});

  final bool initialSwapOpen;

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class WalletHomePage extends WalletScreen {
  const WalletHomePage({super.key});
}

class _WalletScreenState extends State<WalletScreen> {
  static const rpcUrl = 'https://rpc.pokoin.com/rpc';
  static const swapBaseUrl = 'https://rpc.pokoin.com';
  static const pokoinApiBaseUrl = 'https://pokoin.com';
  static const nativeSymbol = 'PKN';
  static const externalCryptoSettlementAddress =
      '0x74466c3a204429B22CE8558F3F18f3C59F67fCB3';
  static const pokoinSwapRouterAddress =
      '0x0000000000000000000000000000000000002606';
  static const pokoinSwapCalldataPrefix = 'pokoinswap:v1:';
  static const defaultSwapAssets = <String>[
    'WPKN',
    'BTC',
    'ETH',
    'BNB',
    'EURC',
    'USDT'
  ];
  static const _stablecoinSwapAssets = <String>{'USDT', 'USDC', 'DAI'};
  static const _cryptoPriceIds = <String, String>{
    'BTC': 'bitcoin',
    'ETH': 'ethereum',
    'BNB': 'binancecoin',
    'EURC': 'eurc',
    'LINK': 'chainlink',
    'UNI': 'uniswap',
    'CAKE': 'pancakeswap-token',
  };
  static const _externalChainIds = <String, String>{
    'ETH': '0x1',
    'BNB': '0x38',
    'EURC': '0x1',
    'USDT': '0x38',
    'USDC': '0x38',
    'DAI': '0x38',
    'LINK': '0x1',
    'UNI': '0x1',
    'CAKE': '0x38',
  };
  static const _manualDepositAssets = <String>{'BTC'};
  static const customSwapAsset = 'CUSTOM';
  static const _tokenListSources = <_TokenListSource>[
    _TokenListSource(
      name: 'Ethereum',
      chainId: 1,
      explorerHost: 'etherscan.io',
      url: 'https://tokens.uniswap.org',
    ),
    _TokenListSource(
      name: 'BNB Chain',
      chainId: 56,
      explorerHost: 'bscscan.com',
      url: 'https://tokens.pancakeswap.finance/pancakeswap-extended.json',
    ),
  ];
  static const recentRecipientLimit = 5;
  static const nativeBankAddress = '0xb4029F68E360280aa4Ad21D8aE5AD8896b8768B2';

  final WalletAuthService _auth = WalletAuthService();
  final WalletBridge _wallet = createWalletBridge();
  final TextEditingController _toController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _exchangeAmountController =
      TextEditingController();
  final TextEditingController _exchangeAddressController =
      TextEditingController();
  final TextEditingController _customSwapAssetController =
      TextEditingController();
  final List<ActivityItem> _activity = <ActivityItem>[];
  final List<String> _recipientSuggestions = <String>[];
  final List<String> _swapAssets = <String>[...defaultSwapAssets];
  final Map<String, _SwapTokenInfo> _swapTokenCatalog =
      <String, _SwapTokenInfo>{
    for (final token in _defaultSwapTokenCatalog) token.symbol: token,
  };
  final Map<String, _SwapPoolSnapshot> _swapPoolsByAsset =
      <String, _SwapPoolSnapshot>{};

  RecipientSuggestionSource _recipientSuggestionSource =
      RecipientSuggestionSource.recent;
  bool _recipientSearchLoading = false;
  bool _recipientSearchHadQuery = false;
  late bool _showSwapPage = widget.initialSwapOpen;
  bool _swapQuoteLoading = false;
  bool _swapPoolsLoading = false;
  bool _swapTokenCatalogLoading = false;
  String? _address;
  WalletUser? _user;
  String? _username;
  String? _linkedAddress;
  String _balance = '0';
  int _accountBalance = 0;
  bool _loading = false;
  bool _authResolved = false;
  bool _accountBalanceReady = false;
  String? _error;
  Object? _swapPoolError;
  int _recipientSearchToken = 0;
  int _swapQuoteToken = 0;
  String _swapAsset = 'ETH';
  bool _swapFromPkn = false;
  bool _autoSwapHandled = false;
  String? _swapQuoteError;
  Map<String, dynamic>? _swapQuote;

  @override
  void dispose() {
    _toController.dispose();
    _amountController.dispose();
    _exchangeAmountController.dispose();
    _exchangeAddressController.dispose();
    _customSwapAssetController.dispose();
    super.dispose();
  }

  void _setSwapPageVisible(bool visible) {
    setState(() {
      _showSwapPage = visible;
      if (!visible) {
        _swapQuote = null;
        _swapQuoteError = null;
        _swapQuoteLoading = false;
        _exchangeAmountController.clear();
        _swapQuoteToken++;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _syncConnectedWallet();
    if (_wallet.hasProvider) {
      _wallet.onChainChanged(() {
        if (_address != null) {
          _loadBalance(_address!);
        }
      });
    }
    if (widget.initialSwapOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(_loadSwapPools());
        unawaited(_loadSwapTokenCatalog());
      });
    }
    _auth.authState.listen((user) async {
      if (mounted) {
        setState(() {
          _authResolved = true;
          _user = user;
        });
        if (user == null) {
          _redirectToAuth();
          return;
        }
        final cached = await _auth.cachedAccountBalance(user.uid);
        if (mounted) {
          setState(() {
            if (cached != null) {
              _accountBalance = cached;
            }
            _accountBalanceReady = true;
          });
        }
        _loadUsername();
        _loadLinkedWallet();
        _loadAccountBalance();
        _loadActivity();
        _openSwapFromDeepLinkIfNeeded();
      }
    });
  }

  void _openSwapFromDeepLinkIfNeeded() {
    if (_autoSwapHandled || _showSwapPage) {
      return;
    }
    final query = Uri.base.queryParameters;
    final requested = query['swap'] == '1' ||
        query['open'] == 'swap' ||
        query['action'] == 'swap';
    if (!requested) {
      return;
    }
    _autoSwapHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _setSwapPageVisible(true);
      unawaited(_loadSwapPools());
      unawaited(_loadSwapTokenCatalog());
    });
  }

  Future<void> _refreshAll() async {
    await _syncConnectedWallet();
    await _loadLinkedWallet();
    await Future.wait(<Future<void>>[
      if (_address != null) _loadBalance(_address!),
      _loadAccountBalance(),
    ]);
    await _loadActivity();
  }

  Future<void> _syncConnectedWallet() async {
    if (!_wallet.hasProvider) {
      return;
    }
    final address = await _wallet.currentAccount();
    if (!mounted) {
      return;
    }
    final normalized = address?.trim();
    if (normalized == null || normalized.isEmpty) {
      if (_address != null) {
        setState(() {
          _address = null;
          _balance = '0';
        });
      }
      return;
    }
    if (normalized == _address) {
      return;
    }
    setState(() => _address = normalized);
    await _loadBalance(normalized);
    await _loadActivity();
  }

  Future<void> _loadLinkedWallet() async {
    final address = await _auth.linkedWalletAddress();
    if (!mounted || address == _linkedAddress) {
      return;
    }
    setState(() => _linkedAddress = address);
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
      if (_wallet.openMetaMaskDapp()) {
        _showMessage('Opening this page in MetaMask...');
        return;
      }
      _showMessage('Install MetaMask or another EVM browser wallet first.');
      return;
    }

    await _runTask(() async {
      final account = await _wallet.requestAccount();
      if (account == null) {
        throw Exception('No wallet account selected');
      }
      await _linkWalletAddress(account);
      await _wallet.addNetwork();
      await _wallet.switchNetwork();
      await _loadBalance(account);
      setState(() {
        _address = account;
        _linkedAddress = account.trim().toLowerCase();
      });
      await _loadLinkedWallet();
      await _record('Wallet connected', account, ActivityKind.inbound);
    });
  }

  Future<void> _addPokoinNetwork() async {
    if (!_wallet.hasProvider) {
      if (_wallet.openMetaMaskDapp()) {
        _showMessage(
          'Opening this page in MetaMask. Tap Add Pokoin network again there.',
        );
        return;
      }
      _showMessage(
          'Open this page in MetaMask or install an EVM wallet first.');
      return;
    }

    await _runTask(() async {
      await _wallet.addNetwork();
      await _wallet.switchNetwork();
      _showMessage('PokoinPoS network added or selected.');
    });
  }

  Future<void> _linkWalletAddress(String address) async {
    final normalized = address.trim().toLowerCase();
    final nonce = await _auth.requestWalletNonce(normalized);
    final message = nonce['message'];
    if (message == null || message.isEmpty) {
      throw Exception('Wallet sign-in nonce was empty.');
    }
    final signature = await _wallet.signMessage(
      address: normalized,
      message: message,
    );
    await _auth.linkSignedWallet(
      address: normalized,
      signature: signature,
    );
  }

  Future<void> _loadBalance(String address) async {
    final result = await _rpc('eth_getBalance', <Object>[address, 'latest']);
    if (!mounted) {
      return;
    }
    setState(() => _balance = _formatWei(_hexToBigInt(result as String)));
  }

  Future<void> _loadAccountBalance() async {
    final cached = await _auth.cachedAccountBalance(_user?.uid);
    if (mounted && cached != null && cached != _accountBalance) {
      setState(() => _accountBalance = cached);
    }
    final balance = await _auth.accountBalance();
    if (!mounted) {
      return;
    }
    setState(() => _accountBalance = balance);
  }

  Future<void> _reconcileRecentTopUps(int amountPkn) async {
    if (_user == null) {
      return;
    }
    try {
      final result = await _auth.reconcileRecentTopUps(amountPkn: amountPkn);
      final credited = _readInt(result['creditedAmountPkn']);
      if (credited <= 0) {
        return;
      }
      await _loadAccountBalance();
      await _loadActivity();
      if (mounted) {
        _showMessage('Recovered $credited PKN from confirmed top-up.');
      }
    } catch (_) {
      // Reconciliation is a safety net; normal wallet loading should continue.
    }
  }

  Future<void> _openSendSheet() async {
    final balanceWei = _parsePknToWei(_balance) ?? BigInt.zero;
    _recipientSuggestions.clear();
    _recipientSuggestionSource = RecipientSuggestionSource.recent;
    _recipientSearchLoading = false;
    _recipientSearchHadQuery = false;
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
                      if (_recipientSearchLoading ||
                          _recipientSuggestions.isNotEmpty ||
                          _recipientSearchHadQuery) ...<Widget>[
                        const SizedBox(height: 8),
                        _RecipientSuggestions(
                          loading: _recipientSearchLoading,
                          hadQuery: _recipientSearchHadQuery,
                          source: _recipientSuggestionSource,
                          suggestions: List<String>.unmodifiable(
                            _recipientSuggestions,
                          ),
                          onSelect: (recipient) {
                            _toController.text = recipient;
                            _recipientSuggestions.clear();
                            _recipientSearchLoading = false;
                            _recipientSearchHadQuery = false;
                            setDialogState(() {});
                          },
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
    final query = value.trim().toLowerCase();
    if (query.isEmpty) {
      _recipientSearchLoading = false;
      _recipientSearchHadQuery = false;
      await _showRecentRecipientSuggestions(setDialogState, token: token);
      return;
    }
    _recipientSearchHadQuery =
        query.length >= 2 && !query.contains('@') && !_isAddress(query);
    if (query.length < 2 || query.contains('@') || _isAddress(query)) {
      _recipientSuggestions.clear();
      _recipientSearchLoading = false;
      setDialogState(() {});
      return;
    }
    _recipientSuggestionSource = RecipientSuggestionSource.search;
    _recipientSearchLoading = true;
    setDialogState(() {});
    try {
      final results = await _auth.searchRecipientUsernames(query);
      if (!mounted || token != _recipientSearchToken) {
        return;
      }
      _recipientSuggestions
        ..clear()
        ..addAll(results.map((username) => username.trim().toLowerCase()));
      _recipientSuggestionSource = RecipientSuggestionSource.search;
      _recipientSearchLoading = false;
      setDialogState(() {});
    } catch (_) {
      if (!mounted || token != _recipientSearchToken) {
        return;
      }
      _recipientSuggestions.clear();
      _recipientSearchLoading = false;
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
    _recipientSuggestionSource = RecipientSuggestionSource.recent;
    _recipientSearchLoading = false;
    _recipientSearchHadQuery = false;
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
      if (!RegExp(r'^[a-zA-Z0-9]{3,32}$').hasMatch(recipient)) {
        _showMessage('Enter a valid username or 0x address.');
        return;
      }
      await _rememberRecipient(recipient);
      await _runTask(() async {
        await _auth.transferAccountBalance(
          recipientUsername: recipient,
          amountPkn: accountAmount,
        );
        _toController.clear();
        _amountController.clear();
        await _loadAccountBalance();
        _showMessage('Account balance transfer sent.');
        await _loadActivity();
      });
      return;
    }

    if (accountAmount == null || accountAmount <= 0) {
      _showMessage('Withdrawals use whole PKN amounts.');
      return;
    }

    if (_user == null) {
      _showMessage('Log in before withdrawing PKN.');
      return;
    }

    await _runTask(() async {
      final result = await _auth.requestPknWithdraw(
        toAddress: recipient,
        amountPkn: accountAmount,
      );
      await _rememberRecipient(recipient);
      _toController.clear();
      _amountController.clear();
      await _record(
        'Requested $accountAmount PKN withdrawal',
        recipient,
        ActivityKind.outbound,
      );
      _showMessage(_withdrawMessage(result));
      await _loadActivity();
    });
  }

  Future<void> _topUpAccountBalance() async {
    final from = _address?.trim();
    if (from == null || from.isEmpty) {
      _showMessage(
          'Connect MetaMask with your linked wallet before topping up.');
      return;
    }
    final linked = _linkedAddress?.trim().toLowerCase();
    if (linked == null || linked.isEmpty) {
      _showMessage('Link a wallet before topping up your account balance.');
      return;
    }
    if (from.toLowerCase() != linked) {
      _showMessage('Switch MetaMask to your linked wallet before topping up.');
      return;
    }
    final amount = int.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      _showMessage('Enter a whole PKN top-up amount.');
      return;
    }

    await _runTask(() async {
      final hash = await _wallet.sendTransaction(
        from: from,
        to: nativeBankAddress,
        valueWei: BigInt.from(amount) * BigInt.from(10).pow(18),
      );
      await _auth.topUpAccountBalance(amountPkn: amount, fundingTxHash: hash);
      await _reconcileRecentTopUps(amount);
      await _loadBalance(from);
      await _loadAccountBalance();
      _amountController.clear();
      _showMessage('Account balance topped up.');
      await _loadActivity();
    });
  }

  Future<void> _openTopUpSheet() async {
    final from = _address?.trim();
    if (from == null || from.isEmpty) {
      _showMessage(
          'Connect MetaMask with your linked wallet before topping up.');
      return;
    }
    final linked = _linkedAddress?.trim().toLowerCase();
    if (linked == null || linked.isEmpty) {
      _showMessage('Link a wallet before topping up your account balance.');
      return;
    }
    if (from.toLowerCase() != linked) {
      _showMessage('Switch MetaMask to your linked wallet before topping up.');
      return;
    }
    _amountController.clear();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
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
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Text(
                  'Top up account balance',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Enter how many whole PKN to move from your connected MetaMask wallet into your site account balance.',
                  style: TextStyle(color: Color(0xFFB8C4E6), height: 1.45),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _amountController,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Amount in PKN',
                    prefixIcon: Icon(Icons.add_card_rounded),
                  ),
                  onSubmitted: (_) {
                    Navigator.of(dialogContext).pop();
                    _topUpAccountBalance();
                  },
                ),
                const SizedBox(height: 18),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          _topUpAccountBalance();
                        },
                        icon: const Icon(Icons.add_card_rounded),
                        label: const Text('Top up'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openWithdrawSheet() async {
    final to = _linkedAddress?.trim();
    if (to == null || to.isEmpty) {
      _showMessage('Link a default wallet before withdrawing.');
      return;
    }
    if (_accountBalance <= 0) {
      _showMessage('Your account balance is empty.');
      return;
    }
    _amountController.clear();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
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
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Text(
                  'Withdraw PKN',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter how many whole PKN to send instantly to your linked wallet. Available: $_accountBalance PKN.',
                  style: const TextStyle(
                    color: Color(0xFFB8C4E6),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  to,
                  style: const TextStyle(
                    color: Color(0xFFFACC15),
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _amountController,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Amount in PKN',
                    prefixIcon: Icon(Icons.savings_outlined),
                  ),
                  onSubmitted: (_) {
                    Navigator.of(dialogContext).pop();
                    _withdrawToLinkedWallet();
                  },
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final preset in <int>[
                      1,
                      5,
                      10,
                      _accountBalance,
                    ])
                      if (preset > 0 && preset <= _accountBalance)
                        ActionChip(
                          label: Text(
                            preset == _accountBalance ? 'Max' : '$preset PKN',
                          ),
                          onPressed: () {
                            _amountController.text = preset.toString();
                            _amountController.selection =
                                TextSelection.collapsed(
                              offset: _amountController.text.length,
                            );
                          },
                        ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          Navigator.of(dialogContext).pop();
                          _withdrawToLinkedWallet();
                        },
                        icon: const Icon(Icons.savings_outlined),
                        label: const Text('Withdraw'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _withdrawToLinkedWallet() async {
    final to = _linkedAddress?.trim();
    if (to == null || to.isEmpty) {
      _showMessage('Link a default wallet before withdrawing.');
      return;
    }
    final amount = int.tryParse(_amountController.text.trim());
    if (amount == null || amount <= 0) {
      _showMessage('Enter a whole PKN withdraw amount.');
      return;
    }

    await _runTask(() async {
      final result =
          await _auth.requestPknWithdraw(toAddress: to, amountPkn: amount);
      await _loadAccountBalance();
      _amountController.clear();
      await _record(
          'Requested $amount PKN withdraw', to, ActivityKind.outbound);
      _showMessage(_withdrawMessage(result));
      await _loadActivity();
    });
  }

  String _withdrawMessage(Map<String, dynamic> result) {
    final txHash = result['payoutTxHash'] as String? ?? '';
    if (txHash.isNotEmpty) {
      return 'Withdraw sent from the bank wallet.';
    }
    return result['warning'] as String? ??
        'Withdraw request created for manual bank payout.';
  }

  Future<void> _openWpknExchangeSheet() async {
    if (!_wallet.hasProvider) {
      if (_wallet.openMetaMaskDappUrl('https://pokoin.com/swap')) {
        _showMessage('Opening PokoinSwap in MetaMask.');
        return;
      }
      _showMessage('Install MetaMask or another EVM browser wallet first.');
      return;
    }

    final from = _address?.trim();
    if (from == null || from.isEmpty) {
      _showMessage('Connect MetaMask before using PokoinSwap.');
      await _connectWallet();
      return;
    }

    if (!mounted) {
      return;
    }
    _setSwapPageVisible(true);
    unawaited(_loadSwapPools());
    unawaited(_loadSwapTokenCatalog());
  }

  Future<void> _loadSwapTokenCatalog() async {
    if (_swapTokenCatalogLoading) {
      return;
    }
    setState(() {
      _swapTokenCatalogLoading = true;
    });
    final discovered = <String, _SwapTokenInfo>{
      for (final entry in _swapTokenCatalog.entries) entry.key: entry.value,
    };
    for (final source in _tokenListSources) {
      try {
        final response = await http
            .get(Uri.parse(source.url))
            .timeout(const Duration(seconds: 10));
        if (response.statusCode < 200 || response.statusCode >= 300) {
          continue;
        }
        final payload = jsonDecode(response.body) as Map<String, dynamic>;
        for (final row
            in (payload['tokens'] as List<dynamic>? ?? <dynamic>[])) {
          if (row is! Map<String, dynamic>) {
            continue;
          }
          if (_readInt(row['chainId']) != source.chainId) {
            continue;
          }
          final symbol = (row['symbol'] as String? ?? '').trim().toUpperCase();
          final address = (row['address'] as String? ?? '').trim();
          if (!_isSupportedSwapSymbol(symbol) || !_isAddress(address)) {
            continue;
          }
          discovered.putIfAbsent(
            symbol,
            () => _SwapTokenInfo(
              symbol: symbol,
              name: row['name'] as String? ?? symbol,
              chainName: source.name,
              chainId: source.chainId,
              address: address,
              explorerUrl: 'https://${source.explorerHost}/token/$address',
              logoUri: row['logoURI'] as String?,
            ),
          );
        }
      } catch (_) {
        // Token lists are discovery aids; pool quoting remains authoritative.
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _swapTokenCatalog
        ..clear()
        ..addAll(discovered);
      _refreshSwapAssetOptions();
      _swapTokenCatalogLoading = false;
    });
  }

  Future<void> _loadSwapPools() async {
    setState(() {
      _swapPoolsLoading = true;
      _swapPoolError = null;
    });
    try {
      final response = await http
          .get(Uri.parse('$swapBaseUrl/chain/swap/pools'))
          .timeout(const Duration(seconds: 10));
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
            payload['error'] as String? ?? 'Pool list unavailable.');
      }
      final liveAssets = <String>{};
      final livePools = <String, _SwapPoolSnapshot>{};
      for (final pool in (payload['pools'] as List<dynamic>? ?? <dynamic>[])) {
        if (pool is! Map<String, dynamic>) {
          continue;
        }
        final assetA = (pool['assetA'] as String? ?? '').toUpperCase();
        final assetB = (pool['assetB'] as String? ?? '').toUpperCase();
        String? asset;
        if (assetA == nativeSymbol && assetB.isNotEmpty) {
          asset = assetB;
        } else if (assetB == nativeSymbol && assetA.isNotEmpty) {
          asset = assetA;
        }
        if (asset == null) {
          continue;
        }
        liveAssets.add(asset);
        livePools[asset] = _SwapPoolSnapshot.fromJson(pool, asset);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        for (final asset in liveAssets) {
          _swapTokenCatalog.putIfAbsent(
            asset,
            () => _SwapTokenInfo(
              symbol: asset,
              name: asset,
              chainName: 'PokoinSwap',
            ),
          );
        }
        _swapPoolsByAsset
          ..clear()
          ..addAll(livePools);
        _refreshSwapAssetOptions();
        if (!_canSwapAsset(_selectedSwapAssetSymbol())) {
          final firstLive = liveAssets.toList()..sort();
          if (firstLive.isNotEmpty) {
            _swapAsset = firstLive.first;
          }
        }
        _swapPoolsLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _swapPoolError = error;
        _swapPoolsLoading = false;
      });
    }
  }

  void _refreshSwapAssetOptions() {
    final symbols = <String>{...defaultSwapAssets, ..._swapTokenCatalog.keys};
    _swapAssets
      ..clear()
      ..addAll(symbols.where(_isSupportedSwapSymbol).toList()..sort());
  }

  void _onSwapAmountChanged(String value) {
    final token = ++_swapQuoteToken;
    final amount = double.tryParse(value.trim().replaceAll(',', '.'));
    if (amount == null ||
        amount <= 0 ||
        !_canSwapAsset(_selectedSwapAssetSymbol())) {
      setState(() {
        _swapQuote = null;
        _swapQuoteError = null;
        _swapQuoteLoading = false;
      });
      return;
    }
    setState(() {
      _swapQuote = null;
      _swapQuoteError = null;
      _swapQuoteLoading = true;
    });
    Future<void>.delayed(const Duration(milliseconds: 350), () async {
      if (!mounted || token != _swapQuoteToken) {
        return;
      }
      try {
        final quote = await _loadSwapQuote(amountIn: amount);
        if (!mounted || token != _swapQuoteToken) {
          return;
        }
        setState(() {
          _swapQuote = quote;
          _swapQuoteError = null;
          _swapQuoteLoading = false;
        });
      } catch (error) {
        if (!mounted || token != _swapQuoteToken) {
          return;
        }
        setState(() {
          _swapQuote = null;
          _swapQuoteError = _friendlyError(error);
          _swapQuoteLoading = false;
        });
      }
    });
  }

  Future<void> _submitCurrentSwap() async {
    final from = _address?.trim();
    final quote = _swapQuote;
    if (from == null || from.isEmpty) {
      _showMessage('Connect MetaMask before using PokoinSwap.');
      return;
    }
    if (quote == null) {
      _showMessage('Enter an amount and wait for the live quote.');
      return;
    }
    final externalSell = quote['source'] == 'external_sell';
    await _runTask(() async {
      final executionQuote = quote['source'] == 'wpkn_market'
          ? await _freshWpknMarketQuoteForSubmit()
          : quote;
      final txHash = await _submitSwap(from: from, quote: executionQuote);
      _swapQuote = null;
      _swapQuoteError = null;
      _exchangeAmountController.clear();
      _swapQuoteToken++;
      setState(() {});
      if (externalSell) {
        _showMessage(
          'Sale request ${_shortAddress(txHash)} created. Crypto payout is pending settlement.',
        );
      } else {
        _showMessage(
          'PokoinSwap submitted (${_shortAddress(txHash)}). It will appear in activity after it confirms.',
        );
      }
      await _loadBalance(from);
      await _loadActivity();
    });
  }

  Widget _buildSwapPage() {
    final asset = _selectedSwapAssetSymbol();
    final pool = _swapPoolsByAsset[asset];
    final showAmmReserves =
        !_isAcceptedSwapAssetWithoutPool(asset) && asset != 'WPKN';
    final displayedPool = showAmmReserves ? pool : null;
    final fromAsset = _swapFromPkn ? nativeSymbol : asset;
    final toAsset = _swapFromPkn ? asset : nativeSymbol;
    final tokenOptions = <String>[..._swapAssets, customSwapAsset];
    final quote = _swapQuote;
    final amountOut = quote == null ? '' : '${quote['amountOut']}';
    final amountIn = double.tryParse(
        _exchangeAmountController.text.trim().replaceAll(',', '.'));
    final wpknQuoteStale = quote != null &&
        quote['source'] == 'wpkn_market' &&
        _isWpknMarketQuoteExpired(quote);
    final canSwap = quote != null &&
        !_loading &&
        _canSwapAsset(asset) &&
        !wpknQuoteStale;
    final missingPool = !_swapPoolsLoading && !_canSwapAsset(asset);
    final quoteError = _swapQuoteError;
    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      appBar: AppBar(
        backgroundColor: const Color(0xFF050816),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'PokoinSwap',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _setSwapPageVisible(false),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              18,
              18,
              18,
              28 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: _SwapExchangeCard(
                poolsLoading: _swapPoolsLoading,
                poolError: _swapPoolError == null
                    ? null
                    : _friendlyError(_swapPoolError!),
                fromAsset: fromAsset,
                toAsset: toAsset.isEmpty ? 'TOKEN' : toAsset,
                amountController: _exchangeAmountController,
                amountOut: amountOut,
                quoteLoading: _swapQuoteLoading,
                quote: quote,
                pool: displayedPool,
                canSwap: canSwap,
                loading: _loading,
                fromTokenSelector: _buildSwapTokenSelector(
                  value: fromAsset,
                  options: tokenOptions,
                  fixedAsset: toAsset,
                  isFromSelector: true,
                ),
                onAmountChanged: _onSwapAmountChanged,
                onSwap: _submitCurrentSwap,
                onFlip: () {
                  setState(() {
                    _swapFromPkn = !_swapFromPkn;
                    _swapQuote = null;
                    _swapQuoteError = null;
                    _swapQuoteToken++;
                  });
                  _onSwapAmountChanged(_exchangeAmountController.text);
                },
                toTokenSelector: _buildSwapTokenSelector(
                  value: toAsset,
                  options: tokenOptions,
                  fixedAsset: fromAsset,
                  isFromSelector: false,
                ),
                customTokenField: _swapAsset == customSwapAsset
                    ? Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: TextField(
                          controller: _customSwapAssetController,
                          textCapitalization: TextCapitalization.characters,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Token symbol',
                            hintText: 'DOGE',
                          ),
                          onChanged: (_) {
                            setState(() {
                              _swapQuote = null;
                              _swapQuoteError = null;
                              _swapQuoteToken++;
                            });
                            _onSwapAmountChanged(
                              _exchangeAmountController.text,
                            );
                          },
                        ),
                      )
                    : null,
                statusLabel: amountIn == null || amountIn <= 0
                    ? 'Enter amount'
                    : missingPool
                        ? 'Pool unavailable'
                        : wpknQuoteStale
                            ? 'Refreshing price'
                            : quoteError ?? (quote == null ? 'No quote' : 'Ready'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<Map<String, dynamic>> _loadSwapQuote({
    required double amountIn,
  }) async {
    final asset = _selectedSwapAssetSymbol();
    if (!_canSwapAsset(asset)) {
      throw StateError('No active PokoinSwap route for $asset.');
    }
    if (_usesExternalBuyQuote(asset)) {
      return _loadExternalBuyQuote(asset: asset, amountIn: amountIn);
    }
    if (_usesExternalSellQuote(asset)) {
      return _loadExternalSellQuote(asset: asset, amountIn: amountIn);
    }
    if (_usesWpknMarketQuote(asset)) {
      return _loadWpknMarketQuote(amountIn: amountIn);
    }
    final assetIn = _swapFromPkn ? nativeSymbol : asset;
    final uri = Uri.parse('$swapBaseUrl/chain/swap/quote').replace(
      queryParameters: <String, String>{
        'pool': _swapPoolId(asset),
        'assetIn': assetIn,
        'amountIn': amountIn.round().toString(),
      },
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        payload['error'] as String? ??
            'PokoinSwap quote unavailable. The pool may need liquidity.',
      );
    }
    return payload;
  }

  Future<Map<String, dynamic>> _freshWpknMarketQuoteForSubmit() async {
    final amount = double.tryParse(
      _exchangeAmountController.text.trim().replaceAll(',', '.'),
    );
    if (amount == null || amount <= 0) {
      throw StateError('Enter an amount and wait for the live quote.');
    }
    final fresh = await _loadWpknMarketQuote(amountIn: amount);
    final prior = _swapQuote;
    if (prior != null &&
        prior['source'] == 'wpkn_market' &&
        _readInt(prior['amountOut']) != _readInt(fresh['amountOut'])) {
      if (mounted) {
        setState(() => _swapQuote = fresh);
      }
    }
    return fresh;
  }

  bool _isWpknMarketQuoteExpired(Map<String, dynamic> quote) {
    final expiresAt = DateTime.tryParse(
      quote['quoteExpiresAt'] as String? ?? '',
    );
    if (expiresAt == null) {
      return false;
    }
    return DateTime.now().toUtc().isAfter(expiresAt.toUtc());
  }

  Future<Map<String, dynamic>> _loadWpknMarketQuote({
    required double amountIn,
  }) async {
    final amount = amountIn.round();
    if (amount <= 0) {
      throw StateError('Enter a whole wPKN or PKN amount.');
    }
    final direction = _swapFromPkn ? 'pkn_to_wpkn' : 'wpkn_to_pkn';
    final uri = Uri.parse('$pokoinApiBaseUrl/api/wpkn-pkn-quote').replace(
      queryParameters: <String, String>{
        'direction': direction,
        'amountIn': amount.toString(),
      },
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        payload['error'] as String? ?? 'wPKN market quote is unavailable.',
      );
    }
    return <String, dynamic>{
      ...payload,
      'source': 'wpkn_market',
      'assetIn': payload['fromAsset'] ?? (_swapFromPkn ? nativeSymbol : 'WPKN'),
      'assetOut': payload['toAsset'] ?? (_swapFromPkn ? 'WPKN' : nativeSymbol),
      'reserveIn':
          'wPKN ${_formatQuoteNumber(_readDouble(payload['wpknUsd']))} USD',
      'reserveOut':
          'PKN ${_formatQuoteNumber(_readDouble(payload['pknUsd']))} USD',
    };
  }

  Future<Map<String, dynamic>> _loadExternalBuyQuote({
    required String asset,
    required double amountIn,
  }) async {
    if (_swapFromPkn) {
      throw StateError('$asset purchases only support buying PKN.');
    }
    final quote = await _auth.quoteCryptoPknPurchase(
      asset: asset,
      amountIn: amountIn,
    );
    return <String, dynamic>{
      ...quote,
      'source': 'external_buy',
      'poolId': '$asset-PKN-market',
      'assetIn': quote['fromAsset'] ?? asset,
      'assetOut': quote['toAsset'] ?? nativeSymbol,
      'reserveIn':
          '${_formatQuoteNumber(_readDouble(quote['marketPrice']))} USDT/$asset',
      'reserveOut':
          '1 PKN = ${_formatQuoteNumber(_readDouble(quote['pknUsd']))} USDT',
    };
  }

  Future<Map<String, dynamic>> _loadExternalSellQuote({
    required String asset,
    required double amountIn,
  }) async {
    if (!_swapFromPkn) {
      throw StateError('$asset sales only support selling PKN.');
    }
    final amountPkn = amountIn.floor();
    if (amountPkn <= 0) {
      throw StateError('Enter a whole PKN amount to sell.');
    }
    final quote = await _auth.quoteCryptoPknSale(
      asset: asset,
      amountPkn: amountPkn,
    );
    return <String, dynamic>{
      ...quote,
      'source': 'external_sell',
      'poolId': 'PKN-$asset-market',
      'assetIn': quote['fromAsset'] ?? nativeSymbol,
      'assetOut': quote['toAsset'] ?? asset,
      'reserveIn':
          '1 PKN = ${_formatQuoteNumber(_readDouble(quote['pknUsd']))} USDT',
      'reserveOut':
          '${_formatQuoteNumber(_readDouble(quote['marketPrice']))} USDT/$asset',
    };
  }

  String _selectedSwapAssetSymbol() {
    if (_swapAsset != customSwapAsset) {
      return _swapAsset.toUpperCase();
    }
    return _customSwapAssetController.text.trim().toUpperCase();
  }

  bool _isSupportedSwapSymbol(String asset) {
    return RegExp(r'^[A-Z0-9]{2,12}$').hasMatch(asset) && asset != nativeSymbol;
  }

  bool _canSwapAsset(String asset) {
    return _isSupportedSwapSymbol(asset) &&
        (_swapPoolsByAsset.containsKey(asset) ||
            _isAcceptedSwapAssetWithoutPool(asset));
  }

  bool _isAcceptedSwapAssetWithoutPool(String asset) {
    return _stablecoinSwapAssets.contains(asset) ||
        _cryptoPriceIds.containsKey(asset);
  }

  bool _usesExternalBuyQuote(String asset) {
    return !_swapFromPkn && _isAcceptedSwapAssetWithoutPool(asset);
  }

  bool _usesExternalSellQuote(String asset) {
    return _swapFromPkn && _isAcceptedSwapAssetWithoutPool(asset);
  }

  bool _usesWpknMarketQuote(String asset) {
    return asset == 'WPKN';
  }

  Widget _buildSwapTokenSelector({
    required String value,
    required List<String> options,
    required String fixedAsset,
    required bool isFromSelector,
  }) {
    final selected = value == customSwapAsset
        ? const _SwapTokenInfo(symbol: customSwapAsset, name: 'Custom token')
        : _swapTokenCatalog[value] ??
            _SwapTokenInfo(symbol: value, name: value, chainName: 'Pokoin');
    return _SwapTokenSelector(
      token: selected,
      isAvailable: value == nativeSymbol || _canSwapAsset(value),
      onTap: () => _showSwapTokenPicker(
        fixedAsset: fixedAsset,
        isFromSelector: isFromSelector,
      ),
    );
  }

  Future<void> _showSwapTokenPicker({
    required String fixedAsset,
    required bool isFromSelector,
  }) async {
    if (_swapTokenCatalog.length <= _defaultSwapTokenCatalog.length) {
      unawaited(_loadSwapTokenCatalog());
    }
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SwapTokenPickerSheet(
        tokens: _swapPickerTokens(),
        fixedAsset: fixedAsset,
        nativeSymbol: nativeSymbol,
        availableAssets: <String>{
          ..._swapPoolsByAsset.keys,
          if (_isAcceptedSwapAssetWithoutPool('ETH')) 'ETH',
        },
        loading: _swapTokenCatalogLoading,
      ),
    );
    if (selected == null) {
      return;
    }
    if (selected == nativeSymbol) {
      setState(() {
        _swapFromPkn = isFromSelector;
        _swapQuote = null;
        _swapQuoteError = null;
        _swapQuoteToken++;
      });
      _onSwapAmountChanged(_exchangeAmountController.text);
      return;
    }
    setState(() {
      _swapAsset = selected;
      _swapFromPkn = !isFromSelector;
      _swapQuote = null;
      _swapQuoteError = null;
      _swapQuoteToken++;
    });
    _onSwapAmountChanged(_exchangeAmountController.text);
  }

  List<_SwapTokenInfo> _swapPickerTokens() {
    final tokens = <String, _SwapTokenInfo>{
      nativeSymbol: const _SwapTokenInfo(
        symbol: nativeSymbol,
        name: 'Pokoin',
        chainName: 'PokoinPoS',
      ),
      for (final entry in _swapTokenCatalog.entries) entry.key: entry.value,
    };
    final live = tokens.values.where((token) => _canSwapAsset(token.symbol));
    final unavailable = tokens.values.where(
      (token) => token.symbol != nativeSymbol && !_canSwapAsset(token.symbol),
    );
    int compareTokens(_SwapTokenInfo a, _SwapTokenInfo b) {
      final aDefault = defaultSwapAssets.contains(a.symbol) ? 0 : 1;
      final bDefault = defaultSwapAssets.contains(b.symbol) ? 0 : 1;
      if (aDefault != bDefault) {
        return aDefault.compareTo(bDefault);
      }
      return a.symbol.compareTo(b.symbol);
    }

    return <_SwapTokenInfo>[
      tokens[nativeSymbol]!,
      ...(live.toList()..sort(compareTokens)),
      ...(unavailable.toList()..sort(compareTokens)),
    ];
  }

  String _swapPoolId(String asset) {
    if (asset == 'WPKN') {
      return 'PKN-WPKN';
    }
    return '$asset-PKN';
  }

  Future<String> _submitSwap({
    required String from,
    required Map<String, dynamic> quote,
  }) async {
    final asset = _selectedSwapAssetSymbol();
    if (quote['source'] == 'external_buy') {
      return _submitExternalBuy(from: from, quote: quote, asset: asset);
    }
    if (quote['source'] == 'external_sell') {
      return _submitExternalSell(quote: quote, asset: asset);
    }
    if (quote['source'] == 'wpkn_market' && _swapFromPkn) {
      throw StateError(
        'The on-chain PKN-wPKN pool cannot fill this market quote. '
        'Use the BNB Chain wPKN bridge instead.',
      );
    }
    await _wallet.addNetwork();
    await _wallet.switchNetwork();
    final amountOut = _readInt(quote['amountOut']);
    if (amountOut <= 0) {
      throw StateError('PokoinSwap quote returned no output amount.');
    }
    final minAmountOut = quote['source'] == 'wpkn_market'
        ? amountOut
        : (amountOut * 995) ~/ 1000;
    final payload = <String, Object>{
      'action': 'amm_swap',
      'poolId': quote['source'] == 'wpkn_market'
          ? _swapPoolId(asset)
          : quote['poolId'] as String? ?? _swapPoolId(asset),
      'assetIn': quote['assetIn'] as String? ?? nativeSymbol,
      'assetOut': quote['assetOut'] as String? ?? asset,
      'amountIn': _readInt(quote['amountIn']),
      'minAmountOut': minAmountOut,
    };
    final data =
        _hexEncodeUtf8('$pokoinSwapCalldataPrefix${jsonEncode(payload)}');
    final nonce = await _pendingNonce(from);
    return _wallet.sendDataTransaction(
      from: from,
      to: pokoinSwapRouterAddress,
      dataHex: data,
      valueWei: BigInt.zero,
      nonce: nonce,
    );
  }

  Future<String> _submitExternalBuy({
    required String from,
    required Map<String, dynamic> quote,
    required String asset,
  }) async {
    final amount = double.tryParse('${quote['amountIn']}') ?? 0;
    if (amount <= 0) {
      throw StateError('Enter an amount to buy PKN.');
    }
    final quoteId = (quote['quoteId'] as String? ?? '').trim();
    if (quoteId.isEmpty) {
      throw StateError('Request a fresh crypto quote before buying PKN.');
    }
    final chainId = (quote['chainId'] as num?)?.toInt();
    final chainIdHex = chainId == null
        ? _externalChainIds[asset] ?? '0x1'
        : '0x${chainId.toRadixString(16)}';
    final settlementAddress = (quote['settlementAddress'] as String? ??
            externalCryptoSettlementAddress)
        .trim();
    String txHash;
    if (_manualDepositAssets.contains(asset)) {
      txHash = await _promptExternalDepositTxHash(
        asset: asset,
        amount: amount,
        settlementAddress: settlementAddress,
      );
    } else if (asset == 'ETH' || asset == 'BNB') {
      txHash = await _wallet.sendExternalTransaction(
        from: from,
        to: settlementAddress,
        valueWei: _parseDecimalToWei(amount.toString()) ?? BigInt.zero,
        chainIdHex: chainIdHex,
      );
    } else {
      final tokenAddress = (quote['tokenAddress'] as String? ?? '').trim();
      if (!_isAddress(tokenAddress)) {
        throw StateError('$asset token contract is not configured.');
      }
      txHash = await _wallet.sendExternalTokenTransfer(
        from: from,
        tokenAddress: tokenAddress,
        to: settlementAddress,
        amountUnits: _parseDecimalToWei(amount.toString()) ?? BigInt.zero,
        chainIdHex: chainIdHex,
      );
    }
    final result = await _auth.requestCryptoPknPurchase(
      quoteId: quoteId,
      depositTxHash: txHash,
    );
    await _loadAccountBalance();
    await _record(
      'Bought ${result['amountPkn'] ?? quote['amountOut']} PKN with $asset',
      txHash,
      ActivityKind.inbound,
    );
    return txHash;
  }

  Future<String> _submitExternalSell({
    required Map<String, dynamic> quote,
    required String asset,
  }) async {
    final from = _address?.trim();
    if (from == null || from.isEmpty) {
      throw StateError('Connect MetaMask before selling PKN.');
    }
    final amountPkn = _readInt(quote['amountIn']);
    if (amountPkn <= 0) {
      throw StateError('Enter a whole PKN amount to sell.');
    }
    final quoteId = (quote['quoteId'] as String? ?? '').trim();
    if (quoteId.isEmpty) {
      throw StateError('Request a fresh crypto sale quote before selling PKN.');
    }
    final payoutAddress = await _promptExternalPayoutAddress(asset: asset);
    await _wallet.addNetwork();
    await _wallet.switchNetwork();
    final depositTxHash = await _wallet.sendTransaction(
      from: from,
      to: nativeBankAddress,
      valueWei: BigInt.from(amountPkn) * BigInt.from(10).pow(18),
    );
    final result = await _auth.requestCryptoPknSale(
      quoteId: quoteId,
      depositTxHash: depositTxHash,
      payoutAddress: payoutAddress,
    );
    await _loadBalance(from);
    await _record(
      'Sent ${result['amountPknDeposited'] ?? quote['amountIn']} PKN for $asset payout',
      depositTxHash,
      ActivityKind.outbound,
    );
    final status = result['status'] as String? ?? 'pending_liquidity';
    final payoutTxHash = (result['payoutTxHash'] as String? ?? '').trim();
    _showMessage(
      payoutTxHash.isNotEmpty || status == 'payout_submitted'
          ? 'PKN received. $asset payout submitted (${_shortAddress(payoutTxHash)}).'
          : 'PKN received. $asset payout is pending settlement.',
    );
    return depositTxHash;
  }

  Future<String> _promptExternalPayoutAddress({required String asset}) async {
    final controller = TextEditingController(
      text: asset == 'BTC' ? '' : (_linkedAddress ?? _address ?? ''),
    );
    try {
      final address = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Text('Receive $asset'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Enter the $asset address that should receive the payout. Your wallet will send PKN to the Pokoin treasury now, then the backend will submit the crypto payout when a signing wallet is configured.',
                style: const TextStyle(height: 1.4),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: '$asset payout address',
                  prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isNotEmpty) {
                  Navigator.of(dialogContext).pop(value);
                }
              },
              child: const Text('Send PKN'),
            ),
          ],
        ),
      );
      if (address == null || address.trim().isEmpty) {
        throw StateError('$asset payout request cancelled.');
      }
      return address.trim();
    } finally {
      controller.dispose();
    }
  }

  Future<String> _promptExternalDepositTxHash({
    required String asset,
    required double amount,
    required String settlementAddress,
  }) async {
    final controller = TextEditingController();
    try {
      final txHash = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Text('Send $asset deposit'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Send ${_formatQuoteNumber(amount)} $asset to this address, wait for confirmation, then paste the transaction id.',
                style: const TextStyle(height: 1.4),
              ),
              const SizedBox(height: 12),
              SelectableText(
                settlementAddress,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Transaction id',
                  prefixIcon: Icon(Icons.receipt_long_outlined),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final value = controller.text.trim();
                if (value.isNotEmpty) {
                  Navigator.of(dialogContext).pop(value);
                }
              },
              child: const Text('Verify deposit'),
            ),
          ],
        ),
      );
      if (txHash == null || txHash.trim().isEmpty) {
        throw StateError('$asset deposit verification cancelled.');
      }
      return txHash.trim();
    } finally {
      controller.dispose();
    }
  }

  Future<int> _pendingNonce(String address) async {
    final result = await _rpc('eth_getTransactionCount', <Object>[
      address,
      'pending',
    ]);
    return _hexToBigInt(result as String).toInt();
  }

  Future<void> _loadActivity() async {
    final address = _address?.trim();
    final results = await Future.wait<List<ActivityItem>>([
      _loadLedgerActivityItems(),
      _loadPersistentWalletActivityItems(),
      if (address != null && address.isNotEmpty)
        _loadOnChainActivityItems(address)
      else
        Future.value(const <ActivityItem>[]),
    ]);
    if (!mounted) {
      return;
    }
    final byKey = <String, ActivityItem>{};
    for (final item in results.expand((items) => items)) {
      byKey.putIfAbsent(item.key, () => item);
    }
    final merged = byKey.values.toList()..sort((a, b) => b.at.compareTo(a.at));
    setState(() {
      _activity
        ..clear()
        ..addAll(merged.take(12));
    });
  }

  Future<List<ActivityItem>> _loadLedgerActivityItems() async {
    final rows = await _auth.ledgerActivity();
    return rows.map(_activityFromLedger).toList(growable: false);
  }

  Future<List<ActivityItem>> _loadPersistentWalletActivityItems() async {
    final rows = await _auth.walletActivity();
    return rows
        .where((row) => !_isLegacyAccountBalanceActivity(
              row['title'] as String? ?? '',
            ))
        .where((row) => !_isUnconfirmedSwapActivity(
              row['title'] as String? ?? '',
            ))
        .map(_activityFromWalletActivity)
        .toList(growable: false);
  }

  Future<List<ActivityItem>> _loadOnChainActivityItems(String address) async {
    final rows = await _auth.onChainActivity(address: address);
    final normalized = address.trim().toLowerCase();
    return rows.map((row) => _activityFromChain(row, normalized)).toList(
          growable: false,
        );
  }

  ActivityItem _activityFromWalletActivity(Map<String, dynamic> row) {
    final kindText = (row['kind'] as String? ?? '').trim();
    final title = _cleanActivityTitle(
      row['title'] as String? ?? 'Wallet activity',
    );
    return ActivityItem(
      key: 'wallet_activity:${row['id'] ?? row['detail'] ?? ''}',
      title: title,
      detail: _shouldHideWalletActivityDetail(title)
          ? ''
          : row['detail'] as String? ?? '',
      kind:
          kindText == 'inbound' ? ActivityKind.inbound : ActivityKind.outbound,
      at: _readDate(row['createdAt']),
    );
  }

  bool _shouldHideWalletActivityDetail(String title) {
    final normalized = title.trim().toLowerCase();
    return normalized.contains('from account balance') ||
        normalized.contains('to account') ||
        normalized.contains('to wallet') ||
        RegExp(r'^(sent|received) \d+ pkn (to|from) ').hasMatch(normalized);
  }

  bool _isLegacyAccountBalanceActivity(String title) {
    final normalized = title.trim().toLowerCase();
    return normalized.contains('from account balance') ||
        normalized.contains('to account balance') ||
        RegExp(r'^topped up \d+ pkn$').hasMatch(normalized);
  }

  bool _isUnconfirmedSwapActivity(String title) {
    return title.trim().toLowerCase() == 'pokoinswap submitted';
  }

  String _cleanActivityTitle(String title) {
    return title
        .replaceAll(
          RegExp(r'\s+from account balance\b', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'\s+from account\b', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  ActivityItem _activityFromLedger(Map<String, dynamic> row) {
    final type = (row['type'] as String? ?? 'account_activity').trim();
    final amount = _readInt(row['amountPkn']);
    final outbound =
        amount < 0 || type.contains('sent') || type.contains('withdraw');
    final counterparty = (row['counterpartyUsername'] ??
            row['toAddress'] ??
            row['stripeSessionId'] ??
            '')
        .toString();
    return ActivityItem(
      key: 'ledger:${row['id'] ?? type}:$counterparty:$amount',
      title: _ledgerTitle(type, amount, counterparty),
      detail: type.startsWith('account_transfer_')
          ? ''
          : counterparty.isEmpty
              ? type
              : counterparty,
      kind: outbound ? ActivityKind.outbound : ActivityKind.inbound,
      at: _readDate(row['createdAt']),
    );
  }

  ActivityItem _activityFromChain(Map<String, dynamic> row, String address) {
    final from = (row['from'] as String? ?? '').trim().toLowerCase();
    final to = (row['to'] as String? ?? '').trim().toLowerCase();
    final hash = row['hash'] as String? ?? '';
    final outbound = from == address;
    final amount = _readInt(row['amount']);
    final block = _readInt(row['blockNumber']);
    final index = _readInt(row['transactionIndex']);
    final explicitDate = _readChainDate(row);
    final ammItem = _swapActivityFromChain(
      row: row,
      hash: hash,
      outbound: outbound,
      blockNumber: block,
      transactionIndex: index,
      explicitDate: explicitDate,
    );
    if (ammItem != null) {
      return ammItem;
    }
    return ActivityItem(
      key: 'chain:$hash',
      title:
          '${outbound ? 'Sent' : 'Received'} ${_formatWholePkn(amount)} PKN on-chain',
      detail: hash.isEmpty
          ? '${_shortAddress(from)} -> ${_shortAddress(to)}'
          : hash,
      kind: outbound ? ActivityKind.outbound : ActivityKind.inbound,
      at: explicitDate ??
          _chainSortDate(
            blockNumber: block,
            transactionIndex: index,
          ),
      timestampLabel: explicitDate == null && block > 0 ? 'Block $block' : null,
    );
  }

  ActivityItem? _swapActivityFromChain({
    required Map<String, dynamic> row,
    required String hash,
    required bool outbound,
    required int blockNumber,
    required int transactionIndex,
    required DateTime? explicitDate,
  }) {
    final amm = row['amm'];
    if (amm is! Map) {
      return null;
    }
    final action = (amm['action'] as String? ?? '').trim().toLowerCase();
    if (action != 'amm_swap') {
      return null;
    }
    final assetIn = (amm['assetIn'] as String? ?? '').trim().toUpperCase();
    final assetOut = (amm['assetOut'] as String? ?? '').trim().toUpperCase();
    final amountIn = _readInt(amm['amountIn']);
    final amountOut = _readInt(amm['amountOut']);
    if (assetIn.isEmpty ||
        assetOut.isEmpty ||
        amountIn <= 0 ||
        amountOut <= 0) {
      return null;
    }
    final confirmedLabel =
        blockNumber > 0 ? 'Confirmed in block $blockNumber' : '';
    return ActivityItem(
      key: 'chain:$hash',
      title:
          'Swapped ${_formatAssetAmount(amountIn, assetIn)} for ${_formatAssetAmount(amountOut, assetOut)}',
      detail: hash.isEmpty ? confirmedLabel : hash,
      kind: outbound ? ActivityKind.outbound : ActivityKind.inbound,
      at: explicitDate ??
          _chainSortDate(
            blockNumber: blockNumber,
            transactionIndex: transactionIndex,
          ),
      timestampLabel:
          explicitDate == null && blockNumber > 0 ? 'Block $blockNumber' : null,
    );
  }

  String _ledgerTitle(String type, int amount, String counterparty) {
    final abs = amount.abs();
    final name = counterparty.trim();
    if (type == 'account_transfer_sent') {
      return name.isEmpty ? 'Sent $abs PKN' : 'Sent $abs PKN to $name';
    }
    if (type == 'account_transfer_received') {
      return name.isEmpty
          ? 'Received $abs PKN'
          : 'Received $abs PKN from $name';
    }
    if (type == 'account_transfer_payout_pending' ||
        type == 'account_transfer_payout_sent') {
      return 'Received $abs PKN to wallet';
    }
    if (type == 'pkn_purchase_credit') {
      return 'Bought $abs PKN';
    }
    if (type == 'silver_unlock_payment_sent') {
      return 'Silver unlock $abs PKN';
    }
    if (type == 'silver_unlock_payment_received') {
      return 'Silver unlock received $abs PKN';
    }
    if (type.contains('withdraw') || type.contains('conversion')) {
      return 'Requested $abs PKN payout';
    }
    return '$type ${abs == 0 ? '' : '$abs PKN'}'.trim();
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

  static double _readDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static DateTime _readDate(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    return DateTime.now();
  }

  static DateTime? _readChainDate(Map<String, dynamic> row) {
    final explicit = row['timestamp'] ?? row['createdAt'] ?? row['time'];
    if (explicit != null) {
      final parsed = _readDate(explicit);
      if (explicit is! String || DateTime.tryParse(explicit) != null) {
        return parsed;
      }
    }
    return null;
  }

  static DateTime _chainSortDate({
    required int blockNumber,
    required int transactionIndex,
  }) {
    final base = DateTime(1970);
    if (blockNumber <= 0) {
      return base.add(Duration(milliseconds: transactionIndex));
    }
    return base
        .add(Duration(seconds: blockNumber, milliseconds: transactionIndex));
  }

  static String _formatWholePkn(int amount) {
    final text = amount.toString();
    if (text.length > 18) {
      return text.substring(0, text.length - 18);
    }
    return text;
  }

  static String _formatAssetAmount(int amount, String asset) {
    if (asset == nativeSymbol) {
      return '${_formatWholePkn(amount)} $asset';
    }
    return '$amount $asset';
  }

  static String _shortAddress(String value) {
    if (value.length <= 12) {
      return value;
    }
    return '${value.substring(0, 6)}...${value.substring(value.length - 4)}';
  }

  void _setAmountPercent(BigInt balanceWei, double percent) {
    final selected =
        (balanceWei * BigInt.from((percent * 100).round())) ~/ BigInt.from(100);
    _amountController.text = _formatWei(selected);
  }

  String? get _recentRecipientKey {
    final accountKey = (_address ?? _user?.uid)?.trim().toLowerCase();
    if (accountKey == null || accountKey.isEmpty) {
      return null;
    }
    return 'pokoin_wallet_recent_recipients:v2:$accountKey';
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

  Future<void> _record(String title, String detail, ActivityKind kind) async {
    final cleanTitle = _cleanActivityTitle(title);
    await _auth.recordWalletActivity(
      title: cleanTitle,
      detail: detail,
      kind: kind == ActivityKind.inbound ? 'inbound' : 'outbound',
    );
    setState(() {
      _activity.insert(
        0,
        ActivityItem(
          key: 'local:${DateTime.now().microsecondsSinceEpoch}:$detail',
          title: cleanTitle,
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

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 860;
    if (!_authResolved || _user == null || !_accountBalanceReady) {
      if (_authResolved) {
        _redirectToAuth();
      }
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_showSwapPage) {
      return _buildSwapPage();
    }

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
                      _TopBar(onOpenMarketplace: _openMarketplace),
                      const SizedBox(height: 20),
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

  void _redirectToAuth() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final location = GoRouterState.of(context).uri.toString();
      final from = Uri.encodeComponent(
        location.isEmpty || location == '/' ? '/wallet' : location,
      );
      context.go('/auth?from=$from');
    });
  }

  Widget _buildWalletPanel() {
    final hasConnectedWallet = (_address ?? '').trim().isNotEmpty;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Account balance',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 10),
          Text(
            '$_accountBalance $nativeSymbol',
            style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w900),
          ),
          if (hasConnectedWallet) ...<Widget>[
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'Connected wallet balance',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$_balance $nativeSymbol',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    _address!,
                    style: const TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (!hasConnectedWallet) ...<Widget>[
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                FilledButton.icon(
                  onPressed: _connectWallet,
                  icon: const Icon(Icons.account_balance_wallet),
                  label: const Text('Connect MetaMask'),
                  style: FilledButton.styleFrom(
                    side: BorderSide.none,
                    elevation: 0,
                    shadowColor: Colors.transparent,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _addPokoinNetwork,
                  icon: const Icon(Icons.add_link),
                  label: const Text('Add Pokoin network'),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide.none,
                    elevation: 0,
                    shadowColor: Colors.transparent,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
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
          icon: Icons.add_card_rounded,
          label: 'Top up',
          onTap: _openTopUpSheet,
        ),
        _QuickActionButton(
          icon: Icons.savings_outlined,
          label: 'Withdraw',
          onTap: _openWithdrawSheet,
        ),
        _QuickActionButton(
          icon: Icons.currency_exchange,
          label: 'Swap',
          onTap: _openWpknExchangeSheet,
        ),
        _QuickActionButton(
          icon: Icons.token_outlined,
          label: 'NFT',
          onTap: () => _openUrl('https://pokoin.com/nft'),
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
                subtitle: item.detail.isEmpty
                    ? null
                    : Text(
                        item.detail,
                        style: const TextStyle(decoration: TextDecoration.none),
                      ),
                trailing: Text(item.timestampLabel ?? _formatDate(item.at)),
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
    return _parseDecimalToWei(value);
  }

  static BigInt? _parseDecimalToWei(String value) {
    final clean = value.trim().replaceAll(',', '.');
    if (!RegExp(r'^\d+(\.\d{1,18})?$').hasMatch(clean)) {
      return null;
    }
    final parts = clean.split('.');
    final whole = BigInt.parse(parts[0]);
    final fraction = parts.length == 2 ? parts[1].padRight(18, '0') : '0' * 18;
    return whole * BigInt.from(10).pow(18) + BigInt.parse(fraction);
  }

  static String _formatQuoteNumber(num value) {
    if (!value.isFinite) {
      return '0';
    }
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value
        .toStringAsFixed(8)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  static String _formatDate(DateTime at) {
    final minute = at.minute.toString().padLeft(2, '0');
    final day = at.day.toString().padLeft(2, '0');
    final month = at.month.toString().padLeft(2, '0');
    return '$day/$month ${at.hour}:$minute';
  }

  static String _hexEncodeUtf8(String value) {
    final bytes = utf8.encode(value);
    final buffer = StringBuffer('0x');
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  void _openMarketplace() {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.go('/marketplace');
      return;
    }
    _openUrl('https://pokoin.com/marketplace');
  }

  static Future<void> _openUrl(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onOpenMarketplace});

  final VoidCallback onOpenMarketplace;

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
          onPressed: onOpenMarketplace,
          icon: const Icon(Icons.storefront, size: 18),
          label: const Text('Marketplace'),
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

enum RecipientSuggestionSource { recent, search }

class _RecipientSuggestions extends StatelessWidget {
  const _RecipientSuggestions({
    required this.loading,
    required this.hadQuery,
    required this.source,
    required this.suggestions,
    required this.onSelect,
  });

  final bool loading;
  final bool hadQuery;
  final RecipientSuggestionSource source;
  final List<String> suggestions;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Row(
        children: <Widget>[
          SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text(
            'Searching usernames...',
            style: TextStyle(color: Color(0xFFB8C4E6)),
          ),
        ],
      );
    }

    if (suggestions.isEmpty) {
      if (!hadQuery) {
        return const SizedBox.shrink();
      }
      return const Text(
        'No username found.',
        style: TextStyle(color: Color(0xFF93A4C8)),
      );
    }

    final isRecent = source == RecipientSuggestionSource.recent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          isRecent ? 'Recent recipients' : 'Username suggestions',
          style: const TextStyle(
            color: Color(0xFF93A4C8),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final recipient in suggestions)
              ActionChip(
                label: Text(recipient),
                avatar: Icon(
                  isRecent ? Icons.history : Icons.person_search_outlined,
                  size: 16,
                ),
                onPressed: () => onSelect(recipient),
              ),
          ],
        ),
      ],
    );
  }
}

class _SwapExchangeCard extends StatelessWidget {
  const _SwapExchangeCard({
    required this.poolsLoading,
    required this.poolError,
    required this.fromAsset,
    required this.toAsset,
    required this.amountController,
    required this.amountOut,
    required this.quoteLoading,
    required this.quote,
    required this.pool,
    required this.canSwap,
    required this.loading,
    required this.fromTokenSelector,
    required this.onAmountChanged,
    required this.onSwap,
    required this.onFlip,
    required this.toTokenSelector,
    required this.customTokenField,
    required this.statusLabel,
  });

  final bool poolsLoading;
  final String? poolError;
  final String fromAsset;
  final String toAsset;
  final TextEditingController amountController;
  final String amountOut;
  final bool quoteLoading;
  final Map<String, dynamic>? quote;
  final _SwapPoolSnapshot? pool;
  final bool canSwap;
  final bool loading;
  final Widget fromTokenSelector;
  final ValueChanged<String> onAmountChanged;
  final VoidCallback onSwap;
  final VoidCallback onFlip;
  final Widget toTokenSelector;
  final Widget? customTokenField;
  final String statusLabel;

  @override
  Widget build(BuildContext context) {
    final quote = this.quote;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xF20A1026),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF38BDF8).withValues(alpha: 0.08),
            blurRadius: 48,
            offset: const Offset(0, 24),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topRight,
                    radius: 1.1,
                    colors: [
                      const Color(0xFF7C3AED).withValues(alpha: 0.20),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Swap',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Spacer(),
                      _SwapStatusPill(
                        label: poolsLoading ? 'Syncing' : statusLabel,
                        accent: poolsLoading
                            ? const Color(0xFF38BDF8)
                            : const Color(0xFFFACC15),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _SwapAssetPanel(
                    label: 'Sell',
                    asset: fromAsset,
                    amountController: amountController,
                    readOnly: false,
                    onChanged: onAmountChanged,
                    trailing: fromTokenSelector,
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: _SwapFlipButton(onTap: onFlip),
                  ),
                  const SizedBox(height: 10),
                  _SwapAssetPanel(
                    label: 'Buy',
                    asset: toAsset,
                    amountText: quoteLoading ? '...' : amountOut,
                    readOnly: true,
                    trailing: toTokenSelector,
                  ),
                  if (customTokenField != null) ...[
                    const SizedBox(height: 10),
                    customTokenField!,
                  ],
                  const SizedBox(height: 14),
                  _SwapQuoteDetails(
                    quote: quote,
                    pool: pool,
                    loading: quoteLoading,
                    poolError: poolError,
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 54,
                    child: FilledButton(
                      onPressed: canSwap ? onSwap : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFFACC15),
                        foregroundColor: const Color(0xFF111827),
                        disabledBackgroundColor:
                            Colors.white.withValues(alpha: 0.08),
                        disabledForegroundColor:
                            Colors.white.withValues(alpha: 0.32),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: loading
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF111827),
                              ),
                            )
                          : Text(
                              canSwap ? 'Swap' : statusLabel,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
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

class _SwapAssetPanel extends StatelessWidget {
  const _SwapAssetPanel({
    required this.label,
    required this.asset,
    this.amountController,
    this.amountText,
    this.readOnly = false,
    this.onChanged,
    this.trailing,
  });

  final String label;
  final String asset;
  final TextEditingController? amountController;
  final String? amountText;
  final bool readOnly;
  final ValueChanged<String>? onChanged;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final amountStyle = TextStyle(
      color: amountText == null || amountText!.isEmpty
          ? const Color(0xFF64748B)
          : Colors.white,
      fontSize: 32,
      fontWeight: FontWeight.w900,
      letterSpacing: -1,
    );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF111936),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF93A4C8),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: readOnly
                    ? Text(
                        amountText == null || amountText!.isEmpty
                            ? '0'
                            : amountText!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: amountStyle,
                      )
                    : TextField(
                        controller: amountController,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        onChanged: onChanged,
                        style: amountStyle,
                        decoration: const InputDecoration(
                          hintText: '0',
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              trailing ?? _SwapTokenPill(symbol: asset),
            ],
          ),
        ],
      ),
    );
  }
}

class _SwapTokenPill extends StatelessWidget {
  const _SwapTokenPill({required this.symbol});

  final String symbol;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1024),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Text(
        symbol,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _SwapTokenSelector extends StatelessWidget {
  const _SwapTokenSelector({
    required this.token,
    required this.isAvailable,
    required this.onTap,
  });

  final _SwapTokenInfo token;
  final bool isAvailable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xFF0B1024),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isAvailable
                  ? Colors.white.withValues(alpha: 0.12)
                  : const Color(0xFFFBBF24).withValues(alpha: 0.34),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                token.symbol,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: isAvailable
                    ? const Color(0xFFFACC15)
                    : const Color(0xFFFBBF24),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SwapTokenPickerSheet extends StatefulWidget {
  const _SwapTokenPickerSheet({
    required this.tokens,
    required this.fixedAsset,
    required this.nativeSymbol,
    required this.availableAssets,
    required this.loading,
  });

  final List<_SwapTokenInfo> tokens;
  final String fixedAsset;
  final String nativeSymbol;
  final Set<String> availableAssets;
  final bool loading;

  @override
  State<_SwapTokenPickerSheet> createState() => _SwapTokenPickerSheetState();
}

class _SwapTokenPickerSheetState extends State<_SwapTokenPickerSheet> {
  final TextEditingController _queryController = TextEditingController();

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _queryController.text.trim().toLowerCase();
    final tokens = widget.tokens
        .where((token) {
          if (query.isEmpty) {
            return true;
          }
          return token.symbol.toLowerCase().contains(query) ||
              token.name.toLowerCase().contains(query) ||
              token.chainName.toLowerCase().contains(query) ||
              (token.address ?? '').toLowerCase().contains(query);
        })
        .take(80)
        .toList(growable: false);
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0B1020),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.fromLTRB(
            18,
            14,
            18,
            18 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Select token',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _queryController,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search ETH, USDT, PEPE, BNB...',
                ),
              ),
              if (widget.loading) ...[
                const SizedBox(height: 10),
                const LinearProgressIndicator(),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  itemCount: tokens.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final token = tokens[index];
                    final enabled = _isEnabled(token.symbol);
                    return ListTile(
                      enabled: enabled,
                      leading: _SwapTokenAvatar(token: token),
                      title: Text(
                        token.symbol,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      subtitle: Text(_subtitle(token, enabled)),
                      trailing: enabled
                          ? const Icon(Icons.chevron_right)
                          : const _SwapUnavailableChip(),
                      onTap: enabled
                          ? () => Navigator.of(context).pop(token.symbol)
                          : null,
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  bool _isEnabled(String symbol) {
    if (symbol == widget.fixedAsset) {
      return false;
    }
    if (symbol == widget.nativeSymbol) {
      return widget.fixedAsset != widget.nativeSymbol &&
          widget.availableAssets.contains(widget.fixedAsset);
    }
    return widget.fixedAsset == widget.nativeSymbol &&
        widget.availableAssets.contains(symbol);
  }

  String _subtitle(_SwapTokenInfo token, bool enabled) {
    final parts = <String>[
      token.name,
      if (token.chainName.isNotEmpty) token.chainName,
      if (token.address != null) _shortTokenAddress(token.address!),
    ];
    final suffix = enabled ? '' : ' - no PokoinSwap pool yet';
    return '${parts.join(' · ')}$suffix';
  }

  static String _shortTokenAddress(String address) {
    if (address.length <= 12) {
      return address;
    }
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
  }
}

class _SwapUnavailableChip extends StatelessWidget {
  const _SwapUnavailableChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFFBBF24).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'no pool',
        style: TextStyle(
          color: Color(0xFFFBBF24),
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _SwapTokenAvatar extends StatelessWidget {
  const _SwapTokenAvatar({required this.token});

  final _SwapTokenInfo token;

  @override
  Widget build(BuildContext context) {
    final logo = token.logoUri;
    return CircleAvatar(
      backgroundColor: const Color(0xFF111936),
      child: logo == null || logo.isEmpty
          ? Text(
              token.symbol.characters.take(2).toString(),
              style: const TextStyle(fontWeight: FontWeight.w900),
            )
          : ClipOval(
              child: Image.network(
                logo,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Text(
                  token.symbol.characters.take(2).toString(),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
    );
  }
}

class _SwapFlipButton extends StatelessWidget {
  const _SwapFlipButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF0B1024),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFFACC15), width: 2),
          ),
          child: const Icon(
            Icons.keyboard_arrow_down_rounded,
            color: Color(0xFFFACC15),
            size: 30,
          ),
        ),
      ),
    );
  }
}

class _SwapStatusPill extends StatelessWidget {
  const _SwapStatusPill({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.30)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: accent,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _SwapQuoteDetails extends StatelessWidget {
  const _SwapQuoteDetails({
    required this.quote,
    required this.pool,
    required this.loading,
    required this.poolError,
  });

  final Map<String, dynamic>? quote;
  final _SwapPoolSnapshot? pool;
  final bool loading;
  final String? poolError;

  @override
  Widget build(BuildContext context) {
    final quote = this.quote;
    if (loading) {
      return _SwapPoolPanel(
        pool: pool,
        child: const Row(
          children: [
            SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 10),
            Text(
              'Fetching quote',
              style: TextStyle(
                color: Color(0xFFB8C4E6),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }
    if (quote == null) {
      final quoteSourceLabel = pool == null ? 'Live market quote' : 'Live AMM quote';
      return _SwapPoolPanel(
        pool: pool,
        child: Text(
          poolError == null ? quoteSourceLabel : poolError!,
          style: TextStyle(
            color: poolError == null
                ? const Color(0xFF93A4C8)
                : const Color(0xFFFBBF24),
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    final source = (quote['source'] as String? ?? '').trim();
    final isExternalQuote = source == 'external_buy' ||
        source == 'external_sell' ||
        source == 'wpkn_market';
    final assetIn = quote['assetIn'] as String? ?? '';
    final assetOut = quote['assetOut'] as String? ?? '';
    return _SwapPoolPanel(
      pool: isExternalQuote ? null : pool,
      child: Column(
        children: [
          _SwapDetailRow(
            label: 'Rate',
            value:
                '${quote['amountIn']} $assetIn / ${quote['amountOut']} $assetOut',
          ),
          const SizedBox(height: 8),
          _SwapDetailRow(
            label: 'Fee',
            value: '${quote['feeBps']} bps',
          ),
          const SizedBox(height: 8),
          _SwapDetailRow(
            label: isExternalQuote ? 'Route' : 'Pool',
            value: '${quote['poolId']}',
          ),
          const SizedBox(height: 8),
          _SwapDetailRow(
            label: isExternalQuote ? 'Reference' : 'Reserves',
            value: '${quote['reserveIn']} / ${quote['reserveOut']}',
          ),
        ],
      ),
    );
  }
}

class _SwapPoolPanel extends StatelessWidget {
  const _SwapPoolPanel({required this.pool, required this.child});

  final _SwapPoolSnapshot? pool;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final pool = this.pool;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          child,
          if (pool != null) ...[
            const SizedBox(height: 14),
            _SwapPoolChart(pool: pool),
          ],
        ],
      ),
    );
  }
}

class _SwapPoolChart extends StatelessWidget {
  const _SwapPoolChart({required this.pool});

  final _SwapPoolSnapshot pool;

  @override
  Widget build(BuildContext context) {
    final total = math.max(1, pool.reservePkn + pool.reserveAsset);
    final pknShare = pool.reservePkn / total;
    final assetShare = pool.reserveAsset / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Text(
              'Pool reserves',
              style: TextStyle(
                color: Color(0xFF93A4C8),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            Text(
              pool.id,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Row(
            children: [
              Expanded(
                flex: math.max(1, (pknShare * 1000).round()),
                child: Container(height: 12, color: const Color(0xFFFACC15)),
              ),
              Expanded(
                flex: math.max(1, (assetShare * 1000).round()),
                child: Container(height: 12, color: const Color(0xFF38BDF8)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _SwapReserveChip(
              color: const Color(0xFFFACC15),
              label: '${pool.reservePkn} PKN',
            ),
            _SwapReserveChip(
              color: const Color(0xFF38BDF8),
              label: '${pool.reserveAsset} ${pool.asset}',
            ),
            _SwapReserveChip(
              color: const Color(0xFFA78BFA),
              label: '${pool.feeBps} bps fee',
            ),
          ],
        ),
      ],
    );
  }
}

class _SwapReserveChip extends StatelessWidget {
  const _SwapReserveChip({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _SwapDetailRow extends StatelessWidget {
  const _SwapDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF93A4C8),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
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

class _TokenListSource {
  const _TokenListSource({
    required this.name,
    required this.chainId,
    required this.explorerHost,
    required this.url,
  });

  final String name;
  final int chainId;
  final String explorerHost;
  final String url;
}

class _SwapTokenInfo {
  const _SwapTokenInfo({
    required this.symbol,
    required this.name,
    this.chainName = '',
    this.chainId,
    this.address,
    this.explorerUrl,
    this.logoUri,
  });

  final String symbol;
  final String name;
  final String chainName;
  final int? chainId;
  final String? address;
  final String? explorerUrl;
  final String? logoUri;
}

const _defaultSwapTokenCatalog = <_SwapTokenInfo>[
  _SwapTokenInfo(
      symbol: 'WPKN', name: 'Wrapped Pokoin', chainName: 'PokoinPoS'),
  _SwapTokenInfo(symbol: 'BTC', name: 'Bitcoin', chainName: 'Bitcoin'),
  _SwapTokenInfo(symbol: 'ETH', name: 'Ether', chainName: 'Ethereum'),
  _SwapTokenInfo(symbol: 'BNB', name: 'BNB', chainName: 'BNB Chain'),
  _SwapTokenInfo(symbol: 'EURC', name: 'Euro Coin', chainName: 'Ethereum'),
  _SwapTokenInfo(
      symbol: 'USDT', name: 'Tether USD', chainName: 'Ethereum / BNB Chain'),
  _SwapTokenInfo(
      symbol: 'USDC', name: 'USD Coin', chainName: 'Ethereum / BNB Chain'),
  _SwapTokenInfo(symbol: 'DAI', name: 'Dai Stablecoin', chainName: 'Ethereum'),
  _SwapTokenInfo(symbol: 'LINK', name: 'Chainlink', chainName: 'Ethereum'),
  _SwapTokenInfo(symbol: 'UNI', name: 'Uniswap', chainName: 'Ethereum'),
  _SwapTokenInfo(
      symbol: 'CAKE', name: 'PancakeSwap Token', chainName: 'BNB Chain'),
];

class _SwapPoolSnapshot {
  const _SwapPoolSnapshot({
    required this.id,
    required this.asset,
    required this.reservePkn,
    required this.reserveAsset,
    required this.feeBps,
  });

  factory _SwapPoolSnapshot.fromJson(Map<String, dynamic> json, String asset) {
    final assetA = (json['assetA'] as String? ?? '').toUpperCase();
    final reserveA = _WalletScreenState._readInt(json['reserveA']);
    final reserveB = _WalletScreenState._readInt(json['reserveB']);
    final pknIsA = assetA == _WalletScreenState.nativeSymbol;
    return _SwapPoolSnapshot(
      id: json['id'] as String? ?? '',
      asset: asset,
      reservePkn: pknIsA ? reserveA : reserveB,
      reserveAsset: pknIsA ? reserveB : reserveA,
      feeBps: _WalletScreenState._readInt(json['feeBps']),
    );
  }

  final String id;
  final String asset;
  final int reservePkn;
  final int reserveAsset;
  final int feeBps;
}

class ActivityItem {
  ActivityItem({
    required this.key,
    required this.title,
    required this.detail,
    required this.kind,
    required this.at,
    this.timestampLabel,
  });

  final String key;
  final String title;
  final String detail;
  final ActivityKind kind;
  final DateTime at;
  final String? timestampLabel;
}
