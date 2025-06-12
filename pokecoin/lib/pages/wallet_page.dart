import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/wallet.dart';
import '../models/cart.dart';
import '../models/order.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wallet = Provider.of<Wallet>(context);
    final cart = Provider.of<Cart>(context);

    final pendingCards = cart.orders
        .where((order) => order.status == ShippingStatus.ordered)
        .expand((order) => order.items)
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0D47A1),
      appBar: AppBar(
        title: const Text('Portafoglio'),
        backgroundColor: const Color(0xFF0D47A1),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
        child: SingleChildScrollView(
          child: Column(
            children: [
              const Text(
                'Saldo Pokecoin',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${wallet.credit.toStringAsFixed(2)} POKE',
                style: const TextStyle(
                  fontSize: 54,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFD32F2F),
                ),
              ),
              if (pendingCards.isNotEmpty) ...[
                const SizedBox(height: 40),
                const Divider(thickness: 1.5, color: Colors.white54),
                const SizedBox(height: 20),
                const Text(
                  'Carte acquistate (in attesa di spedizione)',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: pendingCards.length,
                  itemBuilder: (context, index) {
                    final card = pendingCards[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${card.name} — ${card.expansion} (${card.condition})',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 40),
              const Divider(thickness: 1.5, color: Colors.white54),
              const SizedBox(height: 20),
              const Text(
                'Preleva Pokecoin in Euro sulla carta',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _amountController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Importo in Pokecoin da prelevare',
                        labelStyle: const TextStyle(color: Colors.white70),
                        filled: true,
                        fillColor: Colors.white10,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        prefixIcon: const Icon(Icons.currency_bitcoin,
                            color: Colors.white70),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Inserisci un importo';
                        }
                        final numValue =
                            double.tryParse(value.replaceAll(',', '.'));
                        if (numValue == null || numValue <= 0) {
                          return 'Importo non valido';
                        }
                        if (numValue > wallet.credit) {
                          return 'Saldo insufficiente';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () {
                        if (_formKey.currentState!.validate()) {
                          final amount = double.parse(
                              _amountController.text.replaceAll(',', '.'));
                          wallet.subtractCredit(amount);

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  'Hai prelevato ${amount.toStringAsFixed(2)} POKE (equivalenti a €${amount.toStringAsFixed(2)}) sulla tua carta.'),
                              backgroundColor: const Color(0xFFD32F2F),
                              duration: const Duration(seconds: 3),
                            ),
                          );
                          _amountController.clear();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD32F2F),
                        padding: const EdgeInsets.symmetric(
                            vertical: 16, horizontal: 40),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Preleva',
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
