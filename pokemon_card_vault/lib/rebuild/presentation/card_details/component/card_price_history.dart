import 'package:flutter/material.dart';
import '../../../style/card_details_style.dart';
import '../atomics/card_details_panel.dart';
import '../atomics/detail_dropdown.dart';

/// Serie dimostrativa locale; non riceve né richiede prezzi dal backend.
class CardPriceHistory extends StatefulWidget {
  const CardPriceHistory({super.key});

  @override
  State<CardPriceHistory> createState() => _CardPriceHistoryState();
}

class _CardPriceHistoryState extends State<CardPriceHistory> {
  String _condition = 'Tutte', _language = 'IT';

  @override
  Widget build(BuildContext context) => CardDetailsPanel(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Andamento prezzi',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text('Dati di esempio · PKN',
              style: TextStyle(color: CardDetailsStyle.muted)),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, constraints) {
            final stacked = constraints.maxWidth < 360 ||
                MediaQuery.textScalerOf(context).scale(14) > 20;
            final condition = DetailDropdown(
                label: 'Condizione',
                value: _condition,
                values: const ['Tutte', 'PO', 'PL', 'MP', 'SP', 'NM'],
                onChanged: (value) => setState(() => _condition = value));
            final language = DetailDropdown(
                label: 'Lingua',
                value: _language,
                values: const ['IT', 'EN', 'FR', 'DE', 'ES', 'PT'],
                onChanged: (value) => setState(() => _language = value));
            return stacked
                ? Column(
                    children: [condition, const SizedBox(height: 12), language])
                : Row(children: [
                    Expanded(child: condition),
                    const SizedBox(width: 12),
                    Expanded(child: language),
                  ]);
          }),
          const SizedBox(height: 20),
          Semantics(
              label:
                  'Grafico dimostrativo: 60, 160, 80 e 190 PKN. Nessun prezzo reale.',
              child: SizedBox(
                  height: 128,
                  child: CustomPaint(
                      painter: _PriceHistoryPainter(
                          Theme.of(context).colorScheme.outlineVariant)))),
          const SizedBox(height: 8),
          const Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 20,
              runSpacing: 8,
              children: [
                Text('14/09'),
                Text('10 unità · demo'),
                Text('05/10')
              ]),
        ]),
      );
}

class _PriceHistoryPainter extends CustomPainter {
  const _PriceHistoryPainter(this.gridColor);
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i < 5; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    const values = [60.0, 160.0, 80.0, 190.0];
    final points = [
      for (var i = 0; i < values.length; i++)
        Offset(3 + (size.width - 6) * i / (values.length - 1),
            size.height * (1 - values[i] / 500)),
    ];
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      line.lineTo(point.dx, point.dy);
    }
    final fill = Path.from(line)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = Colors.white.withValues(alpha: .12));
    canvas.drawPath(
        line,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    for (final point in points) {
      canvas.drawCircle(point, 2.5, Paint()..color = CardDetailsStyle.yellow);
    }
  }

  @override
  bool shouldRepaint(_PriceHistoryPainter oldDelegate) =>
      gridColor != oldDelegate.gridColor;
}
