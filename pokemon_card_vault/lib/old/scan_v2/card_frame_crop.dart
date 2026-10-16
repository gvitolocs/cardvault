import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Standard Pokémon TCG card aspect ratio (width / height).
const double pokemonCardAspectRatio = 63 / 88;

/// Center crop scale relative to the largest inscribed card rectangle.
const double cardGuideCropScale = 0.90;

const double _artworkCropBottomFraction = 0.64;
const double _artworkCropTopInset = 0.02;
const double _artworkCropHorizontalInset = 0.05;
const int _maxUploadLongSide = 1800;
const int _jpegQuality = 92;

/// Crops a photo to the card frame (63:88) before TrainingAI classify upload.
class PreparedCardFrame {
  const PreparedCardFrame({
    required this.bytes,
    required this.artworkBytes,
    required this.cropped,
    required this.width,
    required this.height,
    required this.artworkWidth,
    required this.artworkHeight,
    required this.originalWidth,
    required this.originalHeight,
  });

  final Uint8List bytes;
  final Uint8List? artworkBytes;
  final bool cropped;
  final int width;
  final int height;
  final int artworkWidth;
  final int artworkHeight;
  final int originalWidth;
  final int originalHeight;

  String get label {
    if (!cropped) {
      return 'Full frame fallback: ${_formatBytes(bytes.length)}';
    }
    if (artworkBytes == null) {
      return 'Card frame crop: ${width}x$height, ${_formatBytes(bytes.length)}';
    }
    return 'Card + artwork crop: ${width}x$height + ${artworkWidth}x$artworkHeight';
  }
}

PreparedCardFrame prepareCardFrameForUpload(
  Uint8List originalBytes, {
  bool includeArtwork = false,
}) {
  try {
    final decoded = img.decodeImage(originalBytes);
    if (decoded == null) {
      return _fullFrameFallback(originalBytes);
    }

    final oriented = img.bakeOrientation(decoded);
    final crop = _centerCardCrop(oriented.width, oriented.height);
    final cropped = img.copyCrop(
      oriented,
      x: crop.x,
      y: crop.y,
      width: crop.width,
      height: crop.height,
    );

    Uint8List? artworkJpegBytes;
    var artworkWidth = 0;
    var artworkHeight = 0;
    if (includeArtwork) {
      final artworkCrop = _upperArtworkCrop(cropped.width, cropped.height);
      final artwork = img.copyCrop(
        cropped,
        x: artworkCrop.x,
        y: artworkCrop.y,
        width: artworkCrop.width,
        height: artworkCrop.height,
      );
      final artworkUploadImage = _resizeForUpload(artwork);
      artworkJpegBytes = Uint8List.fromList(
        img.encodeJpg(artworkUploadImage, quality: _jpegQuality),
      );
      artworkWidth = artworkUploadImage.width;
      artworkHeight = artworkUploadImage.height;
    }

    final uploadImage = _resizeForUpload(cropped);
    final jpegBytes = Uint8List.fromList(
      img.encodeJpg(uploadImage, quality: _jpegQuality),
    );

    return PreparedCardFrame(
      bytes: jpegBytes,
      artworkBytes: artworkJpegBytes,
      cropped: true,
      width: uploadImage.width,
      height: uploadImage.height,
      artworkWidth: artworkWidth,
      artworkHeight: artworkHeight,
      originalWidth: oriented.width,
      originalHeight: oriented.height,
    );
  } catch (_) {
    return _fullFrameFallback(originalBytes);
  }
}

PreparedCardFrame _fullFrameFallback(Uint8List bytes) {
  return PreparedCardFrame(
    bytes: bytes,
    artworkBytes: null,
    cropped: false,
    width: 0,
    height: 0,
    artworkWidth: 0,
    artworkHeight: 0,
    originalWidth: 0,
    originalHeight: 0,
  );
}

class _CropRect {
  const _CropRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final int x;
  final int y;
  final int width;
  final int height;
}

_CropRect _centerCardCrop(int imageWidth, int imageHeight) {
  var maxWidth = imageWidth;
  var maxHeight = (maxWidth / pokemonCardAspectRatio).round();
  if (maxHeight > imageHeight) {
    maxHeight = imageHeight;
    maxWidth = (maxHeight * pokemonCardAspectRatio).round();
  }

  final cropWidth = (maxWidth * cardGuideCropScale).round().clamp(1, imageWidth);
  final cropHeight = (maxHeight * cardGuideCropScale).round().clamp(
    1,
    imageHeight,
  );
  final x = ((imageWidth - cropWidth) / 2).round().clamp(0, imageWidth - 1);
  final y = ((imageHeight - cropHeight) / 2).round().clamp(0, imageHeight - 1);

  return _CropRect(
    x: x,
    y: y,
    width: math.min(cropWidth, imageWidth - x),
    height: math.min(cropHeight, imageHeight - y),
  );
}

_CropRect _upperArtworkCrop(int imageWidth, int imageHeight) {
  final horizontalInset = (imageWidth * _artworkCropHorizontalInset).round();
  final topInset = (imageHeight * _artworkCropTopInset).round();
  final bottom = (imageHeight * _artworkCropBottomFraction).round();
  final x = horizontalInset.clamp(0, imageWidth - 1);
  final y = topInset.clamp(0, imageHeight - 1);
  final right = (imageWidth - horizontalInset).clamp(x + 1, imageWidth);
  final clampedBottom = bottom.clamp(y + 1, imageHeight);

  return _CropRect(x: x, y: y, width: right - x, height: clampedBottom - y);
}

img.Image _resizeForUpload(img.Image image) {
  final longSide = math.max(image.width, image.height);
  if (longSide <= _maxUploadLongSide) {
    return image;
  }

  final scale = _maxUploadLongSide / longSide;
  return img.copyResize(
    image,
    width: (image.width * scale).round(),
    height: (image.height * scale).round(),
    interpolation: img.Interpolation.cubic,
  );
}

String _formatBytes(int byteCount) {
  if (byteCount >= 1024 * 1024) {
    return '${(byteCount / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(byteCount / 1024).round()} KB';
}
