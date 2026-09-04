import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'camera_pick.dart';
import 'pokoin_boot.dart';
import 'pokoin_card.dart';
import 'scan_debug_log.dart';
import 'scan_engine.dart';
import 'scan_overlay.dart';
import 'scan_verify.dart';
import 'vit_classifier.dart';

class CameraScanPage extends StatefulWidget {
  const CameraScanPage({super.key, this.onOpenMarketplaceUri});

  /// If set and returns true, skip external browser open.
  final bool Function(Uri uri)? onOpenMarketplaceUri;

  @override
  State<CameraScanPage> createState() => _CameraScanPageState();
}

typedef LiveScanPage = CameraScanPage;

class _CameraScanPageState extends State<CameraScanPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const _scanInterval = Duration(milliseconds: 280);
  static const _stableHitsNeeded = 2;
  static const _identifyMissesBeforeRetarget = 2;
  static const _maxFrames = 12;
  static const _acceptScore = liveAcceptScore;
  static const _galleryCertainScore = 0.55;
  static const _vitLiveTimeout = Duration(milliseconds: 1200);

  final ImagePicker _picker = ImagePicker();
  final PokoinCardLookup _lookup = PokoinCardLookup();
  final VitClassifier _vit = VitClassifier();
  final Map<String, _AggregatedMatch> _matches = {};

  CameraController? _controller;
  Timer? _timer;
  bool _initializing = true;
  bool _scanning = false;
  bool _sendingFrame = false;
  bool _detecting = false;
  bool _identifying = false;
  bool _identifyBusy = false;
  bool _opening = false;
  bool _handedOffToBrowser = false;
  bool _engineReady = false;
  bool _yoloLive = false;
  bool _switchingAccel = false;
  String _gpuOwner = 'yolo';
  bool _showBoot = true;
  String? _error;
  int _framesSent = 0;
  ScanMode _mode = ScanMode.fast;
  String _gallery = 'western';
  late final AnimationController _pulse;
  List<ScanBox> _boxes = const [];
  List<ScanHit> _listedCards = const [];
  int _imgW = 0;
  int _imgH = 0;
  int _captureEpoch = 0;
  bool _cameraInitInFlight = false;
  bool _appPaused = false;
  Uint8List? _lastJpeg;
  bool _torchOn = false;
  ScanBox? _lockedBox;
  double _lockedScore = 0;
  ScanBox? _followBox;
  int _identifyMisses = 0;
  int _boxMisses = 0;

  int get _sensorOrientation {
    final sensor = _controller?.description.sensorOrientation;
    if (sensor != null) return sensor;
    return Platform.isAndroid ? 90 : 0;
  }
  _FrozenFrame? _latestFrame;
  List<ScanBox> _latestIdentifyBoxes = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _pulse.dispose();
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      unawaited(() async {
        if (controller.value.isStreamingImages) {
          await controller.stopImageStream();
        }
        await controller.dispose();
      }());
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _appPaused = true;
      ScanDebugLog.i(
        'lifecycle $state opening=$_opening scanning=$_scanning',
      );
      _timer?.cancel();
      _captureEpoch++;
      _sendingFrame = false;
      _detecting = false;
      _identifying = false;
      _identifyBusy = false;
      if (_opening) _handedOffToBrowser = true;
      final controller = _controller;
      _controller = null;
      if (mounted) setState(() {});
      if (controller != null) {
        unawaited(_disposeController(controller));
      }
    } else if (state == AppLifecycleState.resumed) {
      _appPaused = false;
      final wasOpening = _opening || _handedOffToBrowser;
      _opening = false;
      _handedOffToBrowser = false;
      ScanDebugLog.i(
        'lifecycle resume wasOpening=$wasOpening '
        'initInFlight=$_cameraInitInFlight',
      );
      if (wasOpening) {
        _lockedBox = null;
        _lockedScore = 0;
        _followBox = null;
        _identifyMisses = 0;
        _boxMisses = 0;
        _boxes = const [];
      }
      if (_cameraInitInFlight) return;
      unawaited(_initializeCamera(start: true, force: true));
    }
  }

  Future<void> _disposeController(CameraController controller) async {
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {}
    try {
      await controller.dispose();
    } catch (_) {}
  }

  Future<void> _boot() async {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle == null || lifecycle == AppLifecycleState.resumed) {
      unawaited(_initializeCamera(start: false));
    } else {
      ScanDebugLog.i('camera wait lifecycle=$lifecycle');
    }
    unawaited(_hideBootMark());
    unawaited(_initEngine());
  }

  Future<void> _hideBootMark() async {
    await Future<void>.delayed(PokoinBootOverlay.duration);
    if (!mounted) return;
    setState(() => _showBoot = false);
  }

  Future<void> _initEngine() async {
    try {
      final lookup = _lookup.load();
      await ScanEngine.init();
      await lookup;
      if (!mounted) return;
      ScanDebugLog.i(
        'engine ready miloN=${ScanEngine.miloN} identity=${ScanEngine.identity} '
        'gallery=${ScanEngine.gallery} backend=${ScanEngine.miloBackend} '
        'yoloBackend=${ScanEngine.yoloBackend} gpuOwner=${ScanEngine.gpuOwner} '
        'warmupMs=${ScanEngine.warmupMs} predictMs=${ScanEngine.predictMs}',
      );
      setState(() {
        _engineReady = true;
        _gpuOwner = ScanEngine.gpuOwner;
      });
    } catch (error) {
      ScanDebugLog.i('engine init failed $error');
      if (!mounted) return;
      setState(() {
        _engineReady = false;
        _error = error.toString();
      });
    }
    _maybeStartScan();
  }

  void _maybeStartScan() {
    if (!mounted || !_engineReady || _opening || _switchingAccel) return;
    if (_controller?.value.isInitialized != true) return;
    if (_scanning) return;
    _startScan();
  }

  Future<void> _initializeCamera({bool start = false, bool force = false}) async {
    if (_appPaused) {
      ScanDebugLog.i('camera init skipped, app paused');
      return;
    }
    if (_cameraInitInFlight) {
      ScanDebugLog.i('camera init skipped, already in flight');
      return;
    }
    if (!force && _controller?.value.isInitialized == true) {
      if (start && _engineReady) _startScan();
      return;
    }
    _cameraInitInFlight = true;
    setState(() {
      _initializing = true;
      _error = null;
    });
    final previous = _controller;
    _controller = null;
    if (previous != null) {
      await _disposeController(previous);
    }
    try {
      final cameras = await availableCameras();
      if (_appPaused || !mounted) return;
      final pick = await ScanEngine.pickBackCamera();
      final preferredId = pick?['id']?.toString();
      ScanDebugLog.i(
        'cameras=${cameras.map((camera) => '${camera.name}:${camera.lensDirection.name}').join(' ')} '
        'pick=$pick',
      );
      // ignore: avoid_print
      print('pokoin.scan cameras pick=$pick');
      final selectedCamera = selectBackCamera(cameras, preferredId: preferredId);
      if (selectedCamera == null) {
        throw CameraException('no_camera', 'No camera is available.');
      }
      final controller = CameraController(
        selectedCamera,
        Platform.isAndroid ? ResolutionPreset.high : ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );
      _controller = controller;
      try {
        await controller.initialize();
      } catch (error) {
        if (!Platform.isAndroid || selectedCamera.name == '0') rethrow;
        ScanDebugLog.i('camera ${selectedCamera.name} failed $error, falling back to 0');
        await _disposeController(controller);
        final fallback = selectBackCamera(cameras, preferredId: '0') ?? selectedCamera;
        final retry = CameraController(
          fallback,
          Platform.isAndroid ? ResolutionPreset.high : ResolutionPreset.medium,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.yuv420,
        );
        _controller = retry;
        await retry.initialize();
      }
      final active = _controller;
      if (active == null) return;
      if (_appPaused || !mounted) {
        await _disposeController(active);
        if (_controller == active) _controller = null;
        return;
      }
      try {
        await active.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (error) {
        ScanDebugLog.i('lock orientation failed $error');
      }
      await _lockOneXZoom(active);
      await _applyFlashMode(active);
      if (!mounted || _appPaused) {
        await _disposeController(active);
        if (_controller == active) _controller = null;
        return;
      }
      setState(() => _initializing = false);
      ScanDebugLog.i(
        'camera ready ${active.description.name} '
        'sensor=${active.description.sensorOrientation} '
        'preview=${active.value.previewSize} torch=$_torchOn',
      );
      // ignore: avoid_print
      print('pokoin.scan camera ready ${active.description.name} preview=${active.value.previewSize}');
      // CameraX/Camera2 on Samsung often stays black if ImageAnalysis
      // binds before the preview surface is attached.
      await Future<void>.delayed(const Duration(milliseconds: 400));
    } catch (error) {
      ScanDebugLog.i('camera init failed $error');
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = _cameraErrorMessage(error);
      });
    } finally {
      _cameraInitInFlight = false;
      if (!_appPaused) _maybeStartScan();
    }
  }

  /// Logical rear cameras expose 0.5x–8x. 1.0 is the normal wide lens.
  /// Min zoom is ultrawide; >1.0 is tele / digital zoom.
  Future<void> _lockOneXZoom(CameraController controller) async {
    try {
      final minZoom = await controller.getMinZoomLevel();
      final maxZoom = await controller.getMaxZoomLevel();
      final oneX = 1.0.clamp(minZoom, maxZoom).toDouble();
      await controller.setZoomLevel(oneX);
      ScanDebugLog.i('camera zoom min=$minZoom max=$maxZoom set=$oneX');
    } catch (error) {
      ScanDebugLog.i('camera zoom failed $error');
    }
  }

  Future<void> _applyFlashMode([CameraController? controller]) async {
    final active = controller ?? _controller;
    if (active == null || !active.value.isInitialized) return;
    final mode = _torchOn ? FlashMode.torch : FlashMode.off;
    try {
      await active.setFlashMode(mode);
    } catch (error) {
      ScanDebugLog.i('flash set $mode failed $error');
    }
  }

  Future<void> _toggleTorch() async {
    if (_opening || _controller?.value.isInitialized != true) return;
    setState(() => _torchOn = !_torchOn);
    ScanDebugLog.i('torch ${_torchOn ? "on" : "off"}');
    await _applyFlashMode();
  }

  void _setMode(ScanMode mode) {
    if (mode == _mode) return;
    setState(() => _mode = mode);
    _startScan();
  }

  Future<void> _setGallery(String name) async {
    final next = _gallery == name ? 'western' : name;
    if (next == _gallery || _opening) return;
    _stopScan();
    setState(() => _gallery = next);
    try {
      await ScanEngine.setGallery(next);
    } catch (error) {
      ScanDebugLog.i('catalog switch failed $error');
      if (!mounted) return;
      setState(() => _error = error.toString());
      return;
    }
    if (!mounted) return;
    _startScan();
  }

  Future<void> _toggleGpuOwner() async {
    if (!Platform.isAndroid || _opening || _switchingAccel) return;
    final next = _gpuOwner == 'milo' ? 'yolo' : 'milo';
    _stopScan();
    setState(() {
      _switchingAccel = true;
      _gpuOwner = next;
      _yoloLive = false;
      _boxes = const [];
    });
    ScanDebugLog.i('gpu owner request $next (process restart)');
    try {
      await ScanEngine.setGpuOwner(next);
    } catch (error) {
      ScanDebugLog.i('gpu owner switch failed $error');
      if (!mounted) return;
      setState(() => _switchingAccel = false);
      _maybeStartScan();
    }
  }

  Widget _galleryFlag({
    required String gallery,
    required String emoji,
    required String tooltip,
  }) {
    final selected = _gallery == gallery;
    return IconButton.filledTonal(
      tooltip: tooltip,
      onPressed: !_engineReady || _opening ? null : () => unawaited(_setGallery(gallery)),
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        backgroundColor: selected ? const Color(0xFFFACC15) : null,
      ),
      icon: Text(emoji, style: const TextStyle(fontSize: 20, height: 1)),
    );
  }

  void _startScan() {
    if (_controller?.value.isInitialized != true || !_engineReady || _opening) {
      ScanDebugLog.i(
        'scan start skipped init=${_controller?.value.isInitialized} engine=$_engineReady opening=$_opening',
      );
      return;
    }
    _captureEpoch++;
    setState(() {
      _scanning = true;
      _sendingFrame = false;
      _detecting = false;
      _identifying = false;
      _identifyBusy = false;
      _error = null;
      _framesSent = 0;
      _matches.clear();
      _listedCards = const [];
      _boxes = const [];
    });
    _lockedBox = null;
    _lockedScore = 0;
    _followBox = null;
    _identifyMisses = 0;
    _latestFrame = null;
    _latestIdentifyBoxes = const [];
    ScanDebugLog.i('scan start mode=$_mode epoch=$_captureEpoch');
    _timer?.cancel();
    unawaited(_startCapturing());
  }

  void _stopScan() {
    _timer?.cancel();
    final controller = _controller;
    if (controller != null && controller.value.isStreamingImages) {
      unawaited(controller.stopImageStream());
    }
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _startCapturing() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      if (!controller.value.isStreamingImages) {
        await controller.startImageStream(_onStreamFrame);
      }
      ScanDebugLog.i('capture stream ${Platform.isIOS ? "bgra" : "yuv420"}');
    } catch (error) {
      ScanDebugLog.i('stream failed $error, stills');
      _captureAndClassify();
      _timer = Timer.periodic(_scanInterval, (_) => _captureAndClassify());
    }
  }

  void _onStreamFrame(CameraImage image) {
    if (!_scanning || _opening) return;
    if (_detecting) return;
    _detecting = true;
    final epoch = _captureEpoch;
    final frozen = _FrozenFrame.from(image);
    unawaited(_classifyDetect(frozen, epoch));
  }

  Future<void> _classifyDetect(_FrozenFrame frame, int epoch) async {
    final started = DateTime.now();
    try {
      final result = await ScanEngine.scanFrame(
        format: frame.format,
        width: frame.width,
        height: frame.height,
        topK: 5,
        mode: _mode,
        identify: false,
        bgra: frame.bgra,
        bgraStride: frame.bgraStride,
        y: frame.y,
        u: frame.u,
        v: frame.v,
        yStride: frame.yStride,
        uStride: frame.uStride,
        vStride: frame.vStride,
        uvPixelStride: frame.uvPixelStride,
        sensorOrientation: _sensorOrientation,
      );
      if (epoch != _captureEpoch || !mounted || !_scanning) return;
      _handleDetect(
        result,
        captureMs: DateTime.now().difference(started).inMilliseconds,
      );
      final ranked = selectPokeBoxes(
        result.boxes.where((box) => box.conf >= liveOverlayConf).toList(),
        multi: true,
        imgW: result.imgW,
        imgH: result.imgH,
      );
      final toIdentify = _mode == ScanMode.multi
          ? ranked
              .where(
                (box) => isPlausibleLiveCard(
                  box,
                  imgW: result.imgW,
                  imgH: result.imgH,
                  multi: true,
                ),
              )
              .toList()
          : ranked
              .take(1)
              .where(
                (box) => isLiveIdentifyCrop(
                  box,
                  imgW: result.imgW,
                  imgH: result.imgH,
                  others: ranked,
                ),
              )
              .toList();
      if (ranked.isNotEmpty && toIdentify.isEmpty) {
        ScanDebugLog.i(
          'identify skip ${_boxSummary(ranked.first)} '
          'overlap=${overlapWithOthers(ranked.first, ranked).toStringAsFixed(2)}',
        );
      }
      _latestFrame = frame;
      _latestIdentifyBoxes = toIdentify;
      if (toIdentify.isNotEmpty) {
        _kickIdentify(epoch);
      }
    } catch (error) {
      ScanDebugLog.i('detect error epoch=$epoch $error');
      if (!mounted || epoch != _captureEpoch) return;
      setState(() {
        _yoloLive = true;
        _error = error.toString();
      });
    } finally {
      if (epoch == _captureEpoch) {
        _detecting = false;
      }
    }
  }

  void _kickIdentify(int epoch) {
    if (_identifying || _opening || !_scanning) return;
    if (epoch != _captureEpoch) return;
    final frame = _latestFrame;
    final boxes = _latestIdentifyBoxes;
    if (frame == null || boxes.isEmpty) return;
    _identifying = true;
    _identifyBusy = true;
    ScanDebugLog.i('identify start ${_boxSummary(boxes.first)} backend=${ScanEngine.miloBackend}');
    unawaited(_classifyIdentify(frame, List<ScanBox>.from(boxes), epoch));
  }

  Future<void> _classifyIdentify(
    _FrozenFrame frame,
    List<ScanBox> boxes,
    int epoch,
  ) async {
    final started = DateTime.now();
    try {
      final result = await ScanEngine.identifyFrame(
        format: frame.format,
        width: frame.width,
        height: frame.height,
        boxes: boxes,
        topK: 5,
        mode: _mode,
        bgra: frame.bgra,
        bgraStride: frame.bgraStride,
        y: frame.y,
        u: frame.u,
        v: frame.v,
        yStride: frame.yStride,
        uStride: frame.uStride,
        vStride: frame.vStride,
        uvPixelStride: frame.uvPixelStride,
        sensorOrientation: _sensorOrientation,
      );
      if (epoch != _captureEpoch || !mounted || !_scanning) return;
      _lastJpeg = null;
      await _handleResult(
        result,
        epoch: epoch,
        captureMs: DateTime.now().difference(started).inMilliseconds,
        jpegBytes: 0,
        updateOverlay: false,
      );
    } catch (error) {
      ScanDebugLog.i('identify error epoch=$epoch $error');
      if (!mounted || epoch != _captureEpoch) return;
      setState(() => _error = error.toString());
    } finally {
      _identifyBusy = false;
      _identifying = false;
    }
  }

  Future<void> _captureAndClassify() async {
    final epoch = _captureEpoch;
    final controller = _controller;
    if (!_scanning ||
        _opening ||
        controller == null ||
        !controller.value.isInitialized) {
      return;
    }
    if (_sendingFrame || controller.value.isTakingPicture) {
      return;
    }
    _sendingFrame = true;
    final started = DateTime.now();
    try {
      final file = await controller.takePicture().timeout(const Duration(seconds: 5));
      if (controller.value.flashMode != (_torchOn ? FlashMode.torch : FlashMode.off)) {
        await _applyFlashMode(controller);
      }
      if (epoch != _captureEpoch) return;
      final bytes = await file.readAsBytes();
      final result = await ScanEngine.scan(bytes, topK: 5, mode: _mode);
      if (epoch != _captureEpoch || !mounted || !_scanning) return;
      _lastJpeg = bytes;
      await _handleResult(
        result,
        epoch: epoch,
        captureMs: DateTime.now().difference(started).inMilliseconds,
        jpegBytes: bytes.length,
      );
    } catch (error) {
      ScanDebugLog.i('frame error epoch=$epoch $error');
      if (!mounted || epoch != _captureEpoch) return;
      setState(() => _error = error.toString());
    } finally {
      if (epoch == _captureEpoch) {
        _sendingFrame = false;
      }
    }
  }

  void _handleDetect(ScanResult result, {required int captureMs}) {
    ScanDebugLog.i(
      'detect captureMs=$captureMs img=${result.imgW}x${result.imgH} '
      'yoloRaw=${result.yoloRaw} conf=${_yoloConfSummary(result)} '
      'vision=${result.visionBoxes} yolo=${result.yoloBoxes} '
      'rotated=${result.boxes.where((b) => b.isRotated).length} ${_debugBox(result)} '
      'yoloMs=${result.yoloMs} visionMs=${result.visionMs}',
    );
    if (!mounted) return;
    final ranked = selectPokeBoxes(
      result.boxes.where((box) => box.conf >= liveOverlayConf).toList(),
      multi: true,
      imgW: result.imgW,
      imgH: result.imgH,
    );
    final overlay = _overlayForLock(ranked, imgW: result.imgW, imgH: result.imgH);
    setState(() {
      _yoloLive = true;
      _imgW = result.imgW;
      _imgH = result.imgH;
      if (overlay.isNotEmpty) {
        _boxes = overlay;
        _boxMisses = 0;
      } else if (_boxes.isNotEmpty) {
        _boxMisses++;
        if (_boxMisses >= 8) {
          _boxes = const [];
          _followBox = null;
          _lockedBox = null;
          _boxMisses = 0;
        }
      }
    });
  }

  List<ScanBox> _overlayForLock(
    List<ScanBox> ranked, {
    required int imgW,
    required int imgH,
  }) {
    if (_mode == ScanMode.multi) {
      return _boxesForMode(ranked, imgW: imgW, imgH: imgH);
    }
    final follow = overlayFollowTarget(
      follow: _lockedBox ?? _followBox,
      detected: ranked,
      imgW: imgW,
      imgH: imgH,
    );
    if (!identical(follow, _lockedBox ?? _followBox)) {
      _lockedBox = null;
      _lockedScore = 0;
      _followBox = follow;
    }
    final picked = stickyOverlayBox(
      follow: follow,
      detected: ranked,
      current: _boxes,
    );
    if (picked == null) return _boxes;
    if (imgW > 0 &&
        !isPlausibleLiveCard(picked, imgW: imgW, imgH: imgH) &&
        !isYoloLockObject(picked, imgW: imgW, imgH: imgH)) {
      _followBox = null;
      _lockedBox = null;
      _lockedScore = 0;
      return const [];
    }
    _followBox = picked;
    return _boxesForMode([picked], imgW: imgW, imgH: imgH);
  }

  Future<void> _handleResult(
    ScanResult result, {
    required int epoch,
    required int captureMs,
    required int jpegBytes,
    bool updateOverlay = true,
  }) async {
    _recordFrame(result);
    var instant = false;
    final List<ScanHit> stable;
    if (_mode == ScanMode.fast) {
      final top = result.top;
      final live = !updateOverlay;
      if (live) {
        instant = shouldAcceptLive(result) &&
            top != null &&
            _lookup.hasLiveUrl(top, result.hits);
        stable = [
          if (instant && top != null) top,
        ];
      } else {
        final canOpen = top != null &&
            _cardFillsFrame(result) &&
            _lookup.hasLiveUrl(top, result.hits);
        instant = canOpen && shouldOpenImmediately(result);
        final hit = !canOpen
            ? null
            : (instant ? result.hits.first : _findStableMatch(result));
        stable = [
          if (hit != null && _lookup.hasLiveUrl(hit, result.hits)) hit,
        ];
      }
    } else {
      stable = const [];
    }
    final listed =
        _mode == ScanMode.multi ? rankedSeenCards(result.cards) : const <ScanHit>[];
    final reason = _debugReason(result, stable, instant: instant);
    ScanDebugLog.i(
      'frame=${_framesSent + 1} mode=$_mode jpeg=$jpegBytes captureMs=$captureMs '
      'img=${result.imgW}x${result.imgH} yoloRaw=${result.yoloRaw} vision=${result.visionBoxes} '
      'yolo=${result.yoloBoxes} rotated=${result.boxes.where((b) => b.isRotated).length} '
      '${_debugBox(result)} yoloMs=${result.yoloMs} visionMs=${result.visionMs} '
      'miloMs=${result.miloMs} preprocessMs=${result.preprocessMs} '
      'predictMs=${result.predictMs} searchMs=${result.searchMs} '
      'gemvMs=${result.gemvMs} topkMs=${result.topkMs} '
      'embeds=${result.embeds} totalMs=${result.totalMs} ${_debugHits(result)} '
      'reason=$reason',
    );
    setState(() {
      _framesSent++;
      if (updateOverlay && result.boxes.isNotEmpty) {
        _imgW = result.imgW;
        _imgH = result.imgH;
        _boxes = _boxesForMode(
          result.boxes,
          imgW: result.imgW,
          imgH: result.imgH,
        );
      }
      if (!updateOverlay) {
        final top = result.top;
        if (top != null && top.score >= liveAcceptScore) {
          _identifyMisses = 0;
          final box = boxForHit(result, top);
          if (box != null) {
            _lockedBox = box;
            _lockedScore = top.score;
          }
        } else {
          _identifyMisses++;
          if (top == null ||
              top.score < 0.45 ||
              _identifyMisses >= _identifyMissesBeforeRetarget) {
            _lockedBox = null;
            _lockedScore = 0;
            _followBox = null;
            _identifyMisses = 0;
            ScanDebugLog.i(
              'identify retarget after miss top=${top?.name ?? "-"} '
              'score=${top?.score.toStringAsFixed(3) ?? "-"}',
            );
          }
        }
      }
      _listedCards = listed;
    });
    if (_mode == ScanMode.multi) {
      return;
    }
    if (stable.isNotEmpty) {
      await _openHits(
        stable,
        alsoTry: result.hits,
        confirmWithVit: !instant && miloNeedsVit(result) && _lastJpeg != null,
        liveFast: true,
      );
    } else if (_framesSent >= _maxFrames) {
      ScanDebugLog.i('window reset after $_maxFrames frames');
      _matches.clear();
      _framesSent = 0;
    }
  }

  String _cardKey(ScanHit match) =>
      match.id.isNotEmpty ? match.id : match.title;

  List<ScanBox> _boxesForMode(
    List<ScanBox> boxes, {
    int? imgW,
    int? imgH,
  }) {
    final w = imgW ?? _imgW;
    final h = imgH ?? _imgH;
    final picked = selectPokeBoxes(
      boxes.where((box) => box.conf >= liveOverlayConf).toList(),
      multi: _mode == ScanMode.multi,
      imgW: w,
      imgH: h,
    );
    if (w <= 0 || h <= 0) return picked;
    return [
      for (final box in picked)
        overlayPaintBox(box, imgW: w, imgH: h),
    ];
  }

  void _recordFrame(ScanResult result) {
    final matches =
        _mode == ScanMode.multi ? result.cards : result.hits.take(5);
    for (final match in matches) {
      if (match.score < _acceptScore) continue;
      final key = _cardKey(match);
      final existing = _matches[key];
      if (existing == null) {
        _matches[key] = _AggregatedMatch(
          match: match,
          hits: 1,
          bestScore: match.score,
        );
      } else {
        existing.hits += 1;
        if (match.score > existing.bestScore) {
          existing.bestScore = match.score;
          existing.match = match;
        }
      }
    }
  }

  bool _cardFillsFrame(ScanResult result) {
    final top = result.top;
    if (top == null) return false;
    final box = boxForHit(result, top);
    if (box == null) return false;
    return yoloBoxFillsCenter(box, imgW: result.imgW, imgH: result.imgH);
  }

  ScanHit? _findStableMatch(ScanResult result) {
    if (shouldOpenImmediately(result)) return result.hits.first;
    final leaders = _matches.values.toList()
      ..sort((a, b) {
        final hits = b.hits.compareTo(a.hits);
        if (hits != 0) return hits;
        return b.bestScore.compareTo(a.bestScore);
      });
    if (leaders.isEmpty) return null;
    final leader = leaders.first;
    if (leader.bestScore < _acceptScore) return null;
    final top = result.top;
    if (top != null &&
        _cardKey(leader.match) != _cardKey(top) &&
        top.score >= leader.bestScore + 0.08) {
      return null;
    }
    if (leader.hits >= 2 && leader.bestScore >= _acceptScore) {
      return leader.match;
    }
    return null;
  }

  String _debugBox(ScanResult result) {
    if (result.boxes.isEmpty) return 'box=none';
    return _boxSummary(result.boxes.first);
  }

  String _boxSummary(ScanBox box) {
    return 'box=${(box.x2 - box.x1).round()}x${(box.y2 - box.y1).round()} '
        'at=${box.x1.round()},${box.y1.round()} conf=${box.conf.toStringAsFixed(2)}';
  }

  String _yoloConfSummary(ScanResult result) {
    if (result.yoloConfs.isEmpty) return '-';
    return result.yoloConfs
        .map((c) => c.toStringAsFixed(2))
        .join(',');
  }

  String _debugHits(ScanResult result) {
    if (result.hits.isEmpty) return 'hits=none';
    return result.hits.take(5).map((hit) {
      return 'id=${hit.id} name=${hit.name} score=${hit.score.toStringAsFixed(3)} yolo=${hit.yoloConf.toStringAsFixed(2)}';
    }).join(' | ');
  }

  String _debugReason(
    ScanResult result,
    List<ScanHit> stable, {
    bool instant = false,
  }) {
    if (stable.isNotEmpty) {
      final prefix = instant ? 'instant_open' : 'open';
      return '$prefix ${stable.map((h) => '${h.name}:${h.score.toStringAsFixed(3)}').join(',')}';
    }
    if (result.boxes.isEmpty) return 'no_yolo';
    final leader = _matches.values.fold<_AggregatedMatch?>(null, (best, item) {
      if (best == null) return item;
      if (item.hits != best.hits) return item.hits > best.hits ? item : best;
      return item.bestScore > best.bestScore ? item : best;
    });
    if (leader == null) {
      final top = result.top;
      return 'below_accept top=${top?.name ?? "-"} score=${top?.score.toStringAsFixed(3) ?? "-"}';
    }
    return 'wait_stable id=${leader.match.id} name=${leader.match.name} hits=${leader.hits}/$_stableHitsNeeded score=${leader.bestScore.toStringAsFixed(3)}';
  }

  Future<void> _openHits(
    List<ScanHit> hits, {
    List<ScanHit> alsoTry = const [],
    required bool confirmWithVit,
    required bool liveFast,
  }) async {
    if (hits.isEmpty || _opening) return;
    final extras = alsoTry.isEmpty ? hits : alsoTry;
    if (liveFast && !_lookup.hasLiveUrl(hits.first, extras)) {
      ScanDebugLog.i('open skipped unmapped ${hits.first.id} ${hits.first.name}');
      return;
    }
    _stopScan();
    setState(() {
      _opening = true;
    });
    ScanDebugLog.i('open ${hits.map((h) => '${h.id} ${h.name} ${h.score.toStringAsFixed(3)}').join(' | ')} vit=$confirmWithVit liveFast=$liveFast');
    try {
      final hit = hits.first;
      String? vitBlueprintId;
      final jpeg = _lastJpeg;
      if (confirmWithVit && jpeg != null && jpeg.isNotEmpty) {
        ScanDebugLog.i('vit check for ${hit.id} ${hit.name}');
        final vit = await _vit.classify(
          jpeg,
          timeout: liveFast ? _vitLiveTimeout : const Duration(seconds: 6),
          tryFallback: !liveFast,
        );
        if (vit != null) {
          if (!sameSpecies(vit.name, hit.name) && vit.id.isNotEmpty) {
            ScanDebugLog.i('vit replaced ${hit.name} with ${vit.name}');
            vitBlueprintId = vit.id;
          } else {
            ScanDebugLog.i('vit agreed species=${speciesToken(hit.name)}');
          }
        }
      } else {
        ScanDebugLog.i('vit skipped for ${hit.id} ${hit.name}');
      }
      final uri = await _lookup.urlForHit(
        hit,
        vitBlueprintId: vitBlueprintId,
        liveFast: liveFast,
        alsoTry: alsoTry.isEmpty ? hits : alsoTry,
      );
      if (!mounted) return;
      if (uri == null) {
        ScanDebugLog.i('open skipped no pokoin page for ${hit.id} ${hit.name}');
        setState(() => _opening = false);
        _startScan();
        return;
      }
      final inApp = widget.onOpenMarketplaceUri?.call(uri) == true;
      if (inApp) {
        ScanDebugLog.i('open in_app url=$uri');
        setState(() => _opening = false);
        return;
      }
      final launched = await ScanEngine.openInDefaultBrowser(uri).timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          ScanDebugLog.i('openUrl timeout assume browser');
          return true;
        },
      );
      ScanDebugLog.i('open default_browser url=$uri launched=$launched');
      if (!mounted) return;
      if (!launched) {
        setState(() {
          _opening = false;
          _error = 'Could not open $uri';
        });
        _startScan();
        return;
      }
      // Stay _opening until resume. If Chrome never backgrounded us, unwedge.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      if (!_handedOffToBrowser &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        ScanDebugLog.i('open still in app, continue scan');
        setState(() => _opening = false);
        _startScan();
      }
    } catch (error) {
      ScanDebugLog.i('open error $error');
      if (!mounted) return;
      if (_handedOffToBrowser) return;
      setState(() {
        _opening = false;
        _error = error.toString();
      });
      _startScan();
    }
  }

  Future<void> _pickFromGallery() async {
    if (_opening) return;
    _stopScan();
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 92,
        maxWidth: 1600,
      );
      if (image == null) {
        _startScan();
        return;
      }
      setState(() {
        _sendingFrame = true;
        _error = null;
      });
      final bytes = await image.readAsBytes();
      _lastJpeg = bytes;
      final result = await ScanEngine.scan(bytes, topK: 5, mode: _mode);
      ScanDebugLog.i(
        'gallery jpeg=${bytes.length} yolo=${result.yoloBoxes} yoloMs=${result.yoloMs} '
        'miloMs=${result.miloMs} predictMs=${result.predictMs} embeds=${result.embeds} '
        'totalMs=${result.totalMs} ${_debugHits(result)}',
      );
      await ScanDebugLog.flush();
      if (!mounted) return;
      setState(() {
        _sendingFrame = false;
        _imgW = result.imgW;
        _imgH = result.imgH;
        _boxes = _boxesForMode(
          result.boxes,
          imgW: result.imgW,
          imgH: result.imgH,
        );
        _listedCards =
            _mode == ScanMode.multi ? rankedSeenCards(result.cards) : const [];
      });
      if (_mode == ScanMode.multi) {
        _startScan();
        return;
      }
      final hits = result.hits.take(1).toList();
      final certain = hits.where((h) => h.score >= _galleryCertainScore).toList();
      final usable = certain.isNotEmpty
          ? certain
          : hits.where((h) => h.score >= _acceptScore).toList();
      if (usable.isEmpty) {
        _startScan();
        return;
      }
      await _openHits(
        usable,
        alsoTry: result.hits,
        confirmWithVit: miloNeedsVit(result),
        liveFast: false,
      );
    } catch (error) {
      ScanDebugLog.i('gallery error $error');
      if (!mounted) return;
      setState(() {
        _sendingFrame = false;
        _error = error.toString();
      });
      _startScan();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final ready = controller?.value.isInitialized == true;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (ready)
            _CameraSensorPreview(controller: controller!)
          else
            ColoredBox(
              color: Colors.black,
              child: Center(
                child: _initializing
                    ? const CircularProgressIndicator()
                    : Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _error ?? 'Camera not available.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFFCA5A5)),
                        ),
                      ),
              ),
            ),
          if (ready)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) {
                    final preview = controller?.value.previewSize;
                    final portrait =
                        MediaQuery.orientationOf(context) == Orientation.portrait;
                    final layout = preview == null
                        ? const Size(480, 640)
                        : previewLayoutSize(preview, portrait: portrait);
                    final imageSize = _imgW > 0 && _imgH > 0
                        ? Size(_imgW.toDouble(), _imgH.toDouble())
                        : layout;
                    final boxes = _boxes.isNotEmpty ? _boxes : const <ScanBox>[];
                    return CustomPaint(
                      painter: LiveCardBoxesPainter(
                        boxes: boxes,
                        imageSize: imageSize,
                        pulse: _pulse.value,
                        fit: BoxFit.contain,
                      ),
                      child: const SizedBox.expand(),
                    );
                  },
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_mode == ScanMode.multi && _listedCards.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xCC0B0B0B),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 280),
                          child: ListView.separated(
                            shrinkWrap: true,
                            physics: const ClampingScrollPhysics(),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            itemCount: _listedCards.length.clamp(0, maxMultiCards),
                            separatorBuilder: (context, index) => const Divider(
                              height: 8,
                              color: Color(0x33FACC15),
                            ),
                            itemBuilder: (context, index) {
                              final hit = _listedCards[index];
                              return Row(
                                children: [
                                  Text(
                                    '${(hit.score * 100).round()}%',
                                    style: const TextStyle(
                                      color: Color(0xFFFACC15),
                                      fontWeight: FontWeight.w700,
                                      fontFeatures: [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      hit.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                child: Row(
                  children: [
                    Flexible(
                      child: SegmentedButton<ScanMode>(
                        showSelectedIcon: false,
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: WidgetStatePropertyAll(
                            EdgeInsets.symmetric(horizontal: 10),
                          ),
                        ),
                        segments: const [
                          ButtonSegment(
                            value: ScanMode.fast,
                            label: Text(
                              'Single',
                              maxLines: 1,
                              softWrap: false,
                            ),
                          ),
                          ButtonSegment(
                            value: ScanMode.multi,
                            label: Text(
                              'Multi',
                              maxLines: 1,
                              softWrap: false,
                            ),
                          ),
                        ],
                        selected: {_mode},
                        onSelectionChanged: _opening
                            ? null
                            : (value) {
                                if (value.isNotEmpty) _setMode(value.first);
                              },
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: _torchOn ? 'Flash on' : 'Flash off',
                      onPressed: !ready || _opening ? null : _toggleTorch,
                      icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
                    ),
                    if (Platform.isAndroid)
                      IconButton.filledTonal(
                        tooltip: _gpuOwner == 'milo'
                            ? 'GPU: identify (MobileNet CNN). Overlay on CPU. Tap restarts.'
                            : 'GPU: overlay (YOLO) — tap restarts',
                        onPressed: !_engineReady || _opening || _switchingAccel
                            ? null
                            : () => unawaited(_toggleGpuOwner()),
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFFFACC15),
                        ),
                        icon: Text(
                          _gpuOwner == 'milo' ? 'MILO' : 'YOLO',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    IconButton.filledTonal(
                      tooltip: 'Gallery',
                      onPressed: _opening ? null : _pickFromGallery,
                      icon: const Icon(Icons.photo_library_outlined),
                    ),
                    _galleryFlag(
                      gallery: 'japanese',
                      emoji: '🇯🇵',
                      tooltip: 'Japanese catalog',
                    ),
                    _galleryFlag(
                      gallery: 'chinese',
                      emoji: '🇨🇳',
                      tooltip: 'Chinese catalog',
                    ),
                  ],
                ),
                  ),
                ],
              ),
            ),
            ),
          if (ready && !_yoloLive && !_showBoot)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Center(
                    child: Text(
                      'Warming up',
                      style: TextStyle(
                        color: Color(0xFFFACC15),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_showBoot)
            const Positioned.fill(
              child: IgnorePointer(
                child: PokoinBootOverlay(),
              ),
            ),
        ],
      ),
    );
  }
}

class _AggregatedMatch {
  _AggregatedMatch({
    required this.match,
    required this.hits,
    required this.bestScore,
  });

  ScanHit match;
  int hits;
  double bestScore;
}

class _FrozenFrame {
  const _FrozenFrame({
    required this.format,
    required this.width,
    required this.height,
    this.bgra,
    this.bgraStride = 0,
    this.y,
    this.u,
    this.v,
    this.yStride = 0,
    this.uStride = 0,
    this.vStride = 0,
    this.uvPixelStride = 1,
  });

  final String format;
  final int width;
  final int height;
  final Uint8List? bgra;
  final int bgraStride;
  final Uint8List? y;
  final Uint8List? u;
  final Uint8List? v;
  final int yStride;
  final int uStride;
  final int vStride;
  final int uvPixelStride;

  factory _FrozenFrame.from(CameraImage image) {
    if (image.planes.length == 1) {
      final plane = image.planes.first;
      return _FrozenFrame(
        format: 'bgra',
        width: image.width,
        height: image.height,
        bgra: Uint8List.fromList(plane.bytes),
        bgraStride: plane.bytesPerRow,
      );
    }
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    return _FrozenFrame(
      format: 'yuv420',
      width: image.width,
      height: image.height,
      y: Uint8List.fromList(yPlane.bytes),
      u: Uint8List.fromList(uPlane.bytes),
      v: Uint8List.fromList(vPlane.bytes),
      yStride: yPlane.bytesPerRow,
      uStride: uPlane.bytesPerRow,
      vStride: vPlane.bytesPerRow,
      uvPixelStride: uPlane.bytesPerPixel ?? 1,
    );
  }
}

class _CameraSensorPreview extends StatelessWidget {
  const _CameraSensorPreview({required this.controller});

  final CameraController controller;

  @override
  Widget build(BuildContext context) {
    final preview = controller.value.previewSize;
    if (preview == null) {
      return const ColoredBox(color: Colors.black);
    }
    // CameraPreview uses 1/aspectRatio in portrait. Swap so the FittedBox
    // matches that widget. Live YOLO is rotated to this same Size.
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    final layout = previewLayoutSize(preview, portrait: portrait);
    return ColoredBox(
      color: Colors.black,
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox(
          width: layout.width,
          height: layout.height,
          child: CameraPreview(controller),
        ),
      ),
    );
  }
}

String _cameraErrorMessage(Object error) {
  if (error is CameraException) {
    return error.description ?? error.code;
  }
  return error.toString();
}
