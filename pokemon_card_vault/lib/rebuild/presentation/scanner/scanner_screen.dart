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
      this.cameraBuilder});
  final ScannerController controller;
  final VoidCallback onLogin, onSaved;
  final WidgetBuilder? cameraBuilder;
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.leave();
  }

  @override
  void dispose() {
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
                  child: SegmentedButton<ScanDestination>(
                      segments: const [
                        ButtonSegment(
                            value: ScanDestination.collection,
                            icon: Icon(Icons.collections_bookmark_outlined),
                            label: Text('Collezione')),
                        ButtonSegment(
                            value: ScanDestination.listing,
                            icon: Icon(Icons.sell_outlined),
                            label: Text('Listing')),
                      ],
                      selected: {
                        controller.destination
                      },
                      onSelectionChanged: controller.busy ||
                              controller.confirmationPending
                          ? null
                          : (values) =>
                              controller.selectDestination(values.single)))),
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
                                          const Text(
                                              'Inquadra le carte una dopo l’altra. Apri la linguetta per scegliere i risultati e confermare il salvataggio.',
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
                                      : controller.confirmationPending
                                          ? 'Verifica il salvataggio nella linguetta'
                                          : controller.cameraPaused
                                              ? 'Scansione in pausa · revisione carte'
                                              : 'Scansiona · cambia carta dopo il riconoscimento',
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
                    onLogin: widget.onLogin)),
          ])),
        ]);
      });
}
