import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/card_model.dart';

class CardDetailPage extends StatelessWidget {
  final CardModel card;

  const CardDetailPage({super.key, required this.card});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(card.name)),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Image.network(card.imageUrl, height: 200)),
            SizedBox(height: 16),
            Text(
              card.name,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text('Prezzo: \$${card.price.toStringAsFixed(2)}'),
            SizedBox(height: 24),
            Text('Andamento prezzo (simulato):',
                style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 200, child: _buildChart()),
          ],
        ),
      ),
    );
  }

  Widget _buildChart() {
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
            color: Colors.blue,
            barWidth: 3,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(show: false),
          ),
        ],
        gridData: FlGridData(show: false),
        titlesData: FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
      ),
    );
  }
}
