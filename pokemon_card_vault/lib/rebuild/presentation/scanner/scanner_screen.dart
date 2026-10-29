import 'dart:async';
import 'package:flutter/material.dart';
import '../../controller/scanner_controller.dart';
import '../../model/scanner.dart';
import '../../style/scanner_style.dart';
import 'component/scanner_camera.dart';
import 'component/scanned_cards_sheet.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen(
      {super.key,
      required this.controller,
      required this.onLogin,
      required this.onSaved,
      this.onOpenCard,
      this.cameraBuilder});
  final ScannerController controller;
  final VoidCallback onLogin, onSaved;
  final WidgetBuilder? cameraBuilder;
  final Future<void> Function(ScannedCard)? onOpenCard;
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  bool _openingSingle = false;
  String? _openedSingleId;
  @override
  void initState() {
    super.initState();
    widget.controller.leave();
    widget.controller.addListener(_watchSingle);
  }

  @override
  void didUpdateWidget(ScannerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_watchSingle);
      widget.controller.addListener(_watchSingle);
      _openedSingleId = null;
    }
  }

  void _watchSingle() {
    final id = widget.controller.singleCaptureId;
    if (id == null ||
        id == _openedSingleId ||
        _openingSingle ||
        widget.onOpenCard == null) {
      return;
    }
    _openedSingleId = id;
    _openingSingle = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (!mounted) return;
        final card =
            widget.controller.cards.where((c) => c.id == id).firstOrNull;
        if (card != null) await _openCard(card);
      } finally {
        _openingSingle = false;
      }
    });
  }

  Future<void> _openCard(ScannedCard card) async {
    final controller = widget.controller;
    controller.leave();
    await controller
        .review()
        .timeout(const Duration(seconds: 2), onTimeout: () {});
    if (!mounted) return;
    final reviewed = controller.cards.where((c) => c.id == card.id).firstOrNull;
    if (reviewed != null &&
        await controller.copyToClipboard(onlyId: card.id) &&
        mounted) {
      await widget.onOpenCard?.call(reviewed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_watchSingle);
    widget.controller.leave();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        return Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ScanMode>(
                      segments: const [
                        ButtonSegment(
                            value: ScanMode.single,
                            icon: Icon(Icons.crop_portrait),
                            label: Text('Single')),
                        ButtonSegment(
                            value: ScanMode.batch,
                            icon: Icon(Icons.layers_outlined),
                            label: Text('Batch')),
                      ],
                      selected: {
                        controller.mode
                      },
                      onSelectionChanged: controller.busy
                          ? null
                          : (values) => controller.selectMode(values.single)))),
          Expanded(
              child: Stack(children: [
            Positioned.fill(
                child: Padding(
                    padding: const EdgeInsets.only(bottom: 72),
                    child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: controller.activated
                            ? widget.cameraBuilder?.call(context) ??
                                ScannerCamera(controller: controller)
                            : Center(
                                child: SingleChildScrollView(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                              Icons.document_scanner_outlined,
                                              size: 72,
                                              color: ScannerStyle.accent),
                                          const SizedBox(height: 20),
                                          Text('Pronto a scansionare?',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .headlineSmall,
                                              textAlign: TextAlign.center),
                                          const SizedBox(height: 12),
                                          Text(
                                              controller.mode == ScanMode.single
                                                  ? 'Riconosci una carta e apri subito prezzo e listing. La scansione si ferma: riparti tu con Ready.'
                                                  : 'Inquadra le carte una dopo l’altra. Controllale nella linguetta e trasferiscile in Clipboard per listarle più tardi.',
                                              textAlign: TextAlign.center),
                                          const SizedBox(height: 24),
                                          FilledButton.icon(
                                              onPressed: controller.start,
                                              icon:
                                                  const Icon(Icons.play_arrow),
                                              label: const Text(
                                                  'Ready · Avvia scanner')),
                                        ])))))),
            if (controller.activated)
              Positioned(
                  top: 12,
                  left: 64,
                  right: 64,
                  child: IgnorePointer(
                      child: DecoratedBox(
                          decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: .7),
                              borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Text(
                                  controller.preparing
                                      ? 'Preparazione riconoscimento…'
                                      : controller.cameraPaused
                                          ? 'Scansione in pausa · revisione carte'
                                          : controller.mode == ScanMode.single
                                              ? 'Single · inquadra una carta'
                                              : 'Batch · cambia carta dopo il riconoscimento',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 12)))))),
            if (controller.cameraError != null && controller.activated)
              Positioned(
                  top: 80,
                  left: 24,
                  right: 24,
                  child: Material(
                      color: ScannerStyle.panel,
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                          padding: const EdgeInsets.all(12),
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                            Text(controller.cameraError!,
                                textAlign: TextAlign.center),
                            TextButton(
                                onPressed: controller.prepare,
                                child: const Text('Riprova riconoscimento')),
                          ])))),
            NotificationListener<DraggableScrollableNotification>(
                onNotification: (notification) {
                  controller.pauseCamera(notification.extent > .22);
                  return false;
                },
                child: ScannedCardsSheet(
                    controller: controller,
                    onSaved: widget.onSaved,
                    onOpenCard: widget.onOpenCard == null ? null : _openCard,
                    onLogin: widget.onLogin)),
          ])),
        ]);
      });
}
