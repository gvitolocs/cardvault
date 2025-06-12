import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../models/card_model.dart';
import '../models/cart.dart';

class CardDetailPage extends StatefulWidget {
  final CardModel card;

  const CardDetailPage({super.key, required this.card});

  @override
  State<CardDetailPage> createState() => _CardDetailPageState();
}

class _CardDetailPageState extends State<CardDetailPage> {
  String selectedCondition = 'Near Mint';
  String selectedExpansion = 'Base Set';

  final List<String> conditions = [
    'Near Mint',
    'Lightly Played',
    'Moderately Played',
    'Heavily Played',
    'Damaged',
  ];

  final List<String> expansions = [
    'Base Set',
    'Jungle',
    'Fossil',
    'Team Rocket',
    'Neo Genesis',
  ];

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<Cart>(context, listen: false);
    final card = widget.card;

    return Scaffold(
      backgroundColor: const Color(0xFF0D47A1), // Blu scuro
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D47A1), // Blu scuro
        elevation: 0,
        title: Text(card.name),
      ),
      body: Column(
        children: [
          // Barra rossa alta come header sotto appbar
          Container(
            height: 60,
            color: Colors.red,
            alignment: Alignment.center,
            child: const Text(
              'Dettaglio Carta',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        card.imageUrl,
                        height: 200,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    card.name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Prezzo: \$${card.price.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 18,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Andamento prezzo (simulato):',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 200,
                    child: _buildChart(card),
                  ),
                  const SizedBox(height: 24),

                  // Dropdown Condizione con padding
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Condizione',
                          style: TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        DropdownButton<String>(
                          value: selectedCondition,
                          dropdownColor: Colors.blue[900],
                          isExpanded: true,
                          iconEnabledColor: Colors.white,
                          style: const TextStyle(color: Colors.white),
                          items: conditions.map((condition) {
                            return DropdownMenuItem(
                              value: condition,
                              child: Text(condition),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                selectedCondition = value;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ),

                  // Dropdown Espansione con padding
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Espansione',
                          style: TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        DropdownButton<String>(
                          value: selectedExpansion,
                          dropdownColor: Colors.blue[900],
                          isExpanded: true,
                          iconEnabledColor: Colors.white,
                          style: const TextStyle(color: Colors.white),
                          items: expansions.map((expansion) {
                            return DropdownMenuItem(
                              value: expansion,
                              child: Text(expansion),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                selectedExpansion = value;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  Center(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        cart.addItem(
                            card, selectedCondition, selectedExpansion);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                                '${card.name} aggiunta al carrello ($selectedCondition, $selectedExpansion)'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.add_shopping_cart_outlined),
                      label: const Text('Aggiungi al carrello'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(
                            vertical: 16, horizontal: 24),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChart(CardModel card) {
    return LineChart(
      LineChartData(
        lineBarsData: [
          LineChartBarData(
            spots: [
              FlSpot(0, card.price * 0.8),
              FlSpot(1, card.price * 0.9),
              FlSpot(2, card.price),
              FlSpot(3, card.price * 1.1),
              FlSpot(4, card.price * 1.2),
            ],
            isCurved: true,
            color: Colors.red,
            barWidth: 3,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.red.withOpacity(0.3),
            ),
          ),
        ],
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
      ),
    );
  }
}
