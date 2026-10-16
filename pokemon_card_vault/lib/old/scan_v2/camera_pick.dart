import 'package:camera/camera.dart';
import 'package:flutter/painting.dart';

/// Size of the FittedBox around [CameraPreview] in the current orientation.
///
/// `previewSize` is the sensor buffer (usually landscape). [CameraPreview]
/// uses `1 / aspectRatio` when the device is portrait, so the layout box
/// must swap width/height. Live YOLO is rotated to this same size so the
/// overlay contain-mapping matches the preview.
Size previewLayoutSize(Size preview, {required bool portrait}) {
  if (!portrait) return preview;
  return Size(preview.height, preview.width);
}

/// Pick the 1x wide back camera from [availableCameras].
///
/// [preferredId] comes from Android (`pickBackCamera`): a wide group that
/// does not include the telephoto, so Samsung will not auto-switch to 3x.
CameraDescription? selectBackCamera(
  List<CameraDescription> cameras, {
  String? preferredId,
}) {
  final back = cameras
      .where((camera) => camera.lensDirection == CameraLensDirection.back)
      .toList();
  if (back.isEmpty) return cameras.firstOrNull;

  CameraDescription? byId(String id) {
    for (final camera in back) {
      if (camera.name == id) return camera;
    }
    return null;
  }

  if (preferredId != null && preferredId.isNotEmpty) {
    final match = byId(preferredId);
    if (match != null) return match;
  }
  return byId('0') ??
      back.where((camera) => camera.name != '21' && camera.name != '52').firstOrNull ??
      back.firstOrNull;
}
