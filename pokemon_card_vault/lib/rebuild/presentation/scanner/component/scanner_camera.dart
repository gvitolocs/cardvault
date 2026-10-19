import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../../../controller/scanner_controller.dart';
import '../../../model/scanner.dart';
import '../../../style/scanner_style.dart';

class ScannerCamera extends StatefulWidget {
  const ScannerCamera({super.key, required this.controller});
  final ScannerController controller;
  @override
  State<ScannerCamera> createState() => _ScannerCameraState();
}

class _ScannerCameraState extends State<ScannerCamera>
    with WidgetsBindingObserver {
  CameraController? _camera;
  Future<void> _closing = Future.value();
  int _generation = 0;
  bool _opening = false, _active = true, _torch = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_open());
  }

  Future<void> _close() {
    ++_generation;
    final camera = _camera;
    _camera = null;
    _torch = false;
    _closing = _closing.then((_) async {
      try {
        await camera?.dispose();
      } catch (_) {}
    });
    return _closing;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _active = false;
    unawaited(_close());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _active = true;
      unawaited(_open());
    } else {
      _active = false;
      unawaited(_close());
      if (mounted) setState(() {});
    }
  }

  Future<void> _open() async {
    if (_opening || !_active || !mounted) return;
    _opening = true;
    await _close();
    final generation = _generation;
    bool current() => mounted && _active && generation == _generation;
    CameraController? camera;
    try {
      if (mounted) setState(() => _error = null);
      unawaited(widget.controller.prepare());
      final cameras = await availableCameras();
      if (!current()) return;
      final back = cameras
          .where((camera) => camera.lensDirection == CameraLensDirection.back);
      final description =
          back.where((camera) => camera.name == '0').firstOrNull ??
              back.firstOrNull ??
              cameras.firstOrNull;
      if (description == null) throw StateError('No camera');
      camera = CameraController(description, ResolutionPreset.medium,
          enableAudio: false,
          imageFormatGroup: Platform.isIOS
              ? ImageFormatGroup.bgra8888
              : ImageFormatGroup.yuv420);
      await camera.initialize();
      if (!current()) {
        await camera.dispose();
        return;
      }
      _camera = camera;
      await camera.startImageStream((image) {
        final controller = widget.controller;
        if (!current() || !controller.acceptsFrame) return;
        final bgra = image.format.group == ImageFormatGroup.bgra8888;
        if (image.planes.length < (bgra ? 1 : 3)) return;
        unawaited(controller.recognize(ScannerFrame(
            width: image.width,
            height: image.height,
            orientation: description.sensorOrientation,
            bgra: bgra,
            planes: image.planes
                .map((plane) => Uint8List.fromList(plane.bytes))
                .toList(),
            strides: image.planes.map((plane) => plane.bytesPerRow).toList(),
            pixelStride: bgra ? 1 : image.planes[1].bytesPerPixel ?? 1)));
      });
      if (current()) setState(() {});
    } on CameraException catch (error) {
      if (current()) {
        setState(() => _error = error.code.contains('Access')
            ? 'Consenti l’accesso alla fotocamera nelle impostazioni del telefono.'
            : 'Fotocamera non disponibile. Riprova.');
      }
      if (_camera == null) await camera?.dispose();
    } catch (_) {
      if (current()) {
        setState(() => _error = 'Fotocamera non disponibile. Riprova.');
      }
      if (_camera == null) await camera?.dispose();
    } finally {
      _opening = false;
      // Resume can arrive while an obsolete initialization is still finishing.
      if (mounted && _active && generation != _generation) unawaited(_open());
    }
  }

  Future<void> _toggleTorch() async {
    try {
      await _camera?.setFlashMode(_torch ? FlashMode.off : FlashMode.torch);
      if (mounted) setState(() => _torch = !_torch);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Torcia non disponibile.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    return ColoredBox(
        color: Colors.black,
        child: Stack(fit: StackFit.expand, children: [
          if (camera?.value.isInitialized == true)
            Center(child: CameraPreview(camera!))
          else
            Center(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      if (_error == null)
                        const CircularProgressIndicator()
                      else
                        const Icon(Icons.no_photography_outlined, size: 40),
                      const SizedBox(height: 16),
                      Text(_error ?? 'Avvio fotocamera…',
                          textAlign: TextAlign.center),
                      if (_error != null)
                        TextButton(
                            onPressed: _open, child: const Text('Riprova')),
                    ]))),
          if (camera?.value.isInitialized == true) ...[
            const IgnorePointer(
                child: Center(
                    child: FractionallySizedBox(
                        widthFactor: .72,
                        heightFactor: .76,
                        child: DecoratedBox(
                            decoration: BoxDecoration(
                                border: Border.fromBorderSide(BorderSide(
                                    color: ScannerStyle.accent, width: 2)),
                                borderRadius:
                                    BorderRadius.all(Radius.circular(18))))))),
            Positioned(
                top: 12,
                right: 12,
                child: IconButton.filledTonal(
                    tooltip: _torch ? 'Spegni torcia' : 'Accendi torcia',
                    onPressed: _toggleTorch,
                    icon: Icon(_torch ? Icons.flash_on : Icons.flash_off))),
            Positioned(
                top: 12,
                left: 12,
                child: IconButton.filledTonal(
                    tooltip: 'Riavvia fotocamera',
                    onPressed: _open,
                    icon: const Icon(Icons.refresh))),
          ],
        ]));
  }
}
