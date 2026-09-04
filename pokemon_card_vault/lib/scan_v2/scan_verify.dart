import 'dart:math' as math;

import 'scan_engine.dart';

/// Portrait Pokémon card is 63:88 (~0.716). Landscape is the same card rotated.
const double pokeAspectMin = 0.58;
const double pokeAspectMax = 0.88;
const double pokeTargetAspect = 63 / 88;
const double pokeGuideFill = 0.92;

/// Live Single accept floor. Phone photos of real cards often land ~0.58–0.65.
const double liveAcceptScore = 0.60;

/// Overlay may follow a YOLO/Vision object from this conf. Decode stays 0.25.
/// Desk/paper false hits on this phone were 0.35; real cards are usually ≥ 0.70.
const double liveOverlayConf = 0.70;

/// High-confidence leftover AABB (inner-art guard). Overlay of a poke-size
/// Vision quad does not need this.
const double liveYoloLockConf = 0.90;

/// Live 480×640: inner artwork of a framed card is ~0.22 of the preview
/// (`231×292` opened as Noctowl 0.610). Outer Fearow was `256×334` ≈ 0.28.
const double liveMinCardArea = 0.25;

/// Multi: keep up to a 60-card page. A cell on a 4×4 is ~6%; on a 60-card
/// spread it is ~1.5%, so the Single live floor would drop every card.
const int maxMultiCards = 60;
const double multiMinCardArea = 0.006;

ScanBox? boxForHit(ScanResult result, ScanHit hit) {
  if (result.boxes.isEmpty) return null;
  if (hit.boxIndex >= 0 && hit.boxIndex < result.boxes.length) {
    return result.boxes[hit.boxIndex];
  }
  return result.boxes.first;
}

/// True when the box is a 63:88 card filling the middle of the frame.
/// Poke-size is the rectangle edges at any rotation, not the AABB.
bool yoloBoxFillsCenter(
  ScanBox box, {
  required int imgW,
  required int imgH,
  double maxCenterOffset = 0.28,
  double minAreaFraction = 0.12,
}) {
  if (imgW <= 0 || imgH <= 0) return false;
  final width = box.x2 - box.x1;
  final height = box.y2 - box.y1;
  if (width < 48 || height < 48) return false;
  if (!isPokeSizeBox(box)) return false;
  final cx = ((box.x1 + box.x2) / 2) / imgW;
  final cy = ((box.y1 + box.y2) / 2) / imgH;
  if ((cx - 0.5).abs() > maxCenterOffset || (cy - 0.5).abs() > maxCenterOffset) {
    return false;
  }
  return (width * height) / (imgW * imgH) >= minAreaFraction;
}

/// Axis-aligned box matches a Pokémon card: 63:88 or the same card on its side.
/// Official size is 63×88 mm (2.5×3.5 in, 5:7 ≈ 0.714).
bool isPokeSizeAspect(double width, double height) {
  if (width < 8 || height < 8) return false;
  final aspect = width / height;
  final portrait = aspect >= pokeAspectMin && aspect <= pokeAspectMax;
  final landscape =
      aspect >= 1 / pokeAspectMax && aspect <= 1 / pokeAspectMin;
  return portrait || landscape;
}

/// Keep the detection where it is, but force 63:88 (or 88:63 if the card is on its side).
ScanBox snapToPokeSize(ScanBox box, {required int imgW, required int imgH}) {
  final maxW = imgW.toDouble();
  final maxH = imgH.toDouble();
  if (maxW < 8 || maxH < 8) return box;
  final w = (box.x2 - box.x1).clamp(1.0, maxW);
  final h = (box.y2 - box.y1).clamp(1.0, maxH);
  final landscape = w >= h;
  final target = landscape ? 1 / pokeTargetAspect : pokeTargetAspect;
  var bw = w;
  var bh = h;
  if (w / h >= target) {
    bh = h;
    bw = bh * target;
  } else {
    bw = w;
    bh = bw / target;
  }
  if (bw > maxW) {
    bw = maxW;
    bh = bw / target;
  }
  if (bh > maxH) {
    bh = maxH;
    bw = bh * target;
  }
  var x1 = ((box.x1 + box.x2) / 2) - bw / 2;
  var y1 = ((box.y1 + box.y2) / 2) - bh / 2;
  x1 = x1.clamp(0, maxW - bw);
  y1 = y1.clamp(0, maxH - bh);
  return ScanBox(x1: x1, y1: y1, x2: x1 + bw, y2: y1 + bh, conf: box.conf);
}

/// Overlay paint: the detector box, not a forced 63:88 viewfinder.
/// Snapping an upright AABB shifted the rectangle off the physical card
/// (Android YOLO). Identify may still snap the crop. Vision quads stay.
ScanBox overlayPaintBox(ScanBox box, {required int imgW, required int imgH}) {
  return box;
}

double pokeBoxArea(ScanBox box) =>
    (box.x2 - box.x1).clamp(0, double.infinity) *
    (box.y2 - box.y1).clamp(0, double.infinity);

double pokeBoxIou(ScanBox a, ScanBox b) {
  final ix1 = a.x1 > b.x1 ? a.x1 : b.x1;
  final iy1 = a.y1 > b.y1 ? a.y1 : b.y1;
  final ix2 = a.x2 < b.x2 ? a.x2 : b.x2;
  final iy2 = a.y2 < b.y2 ? a.y2 : b.y2;
  final inter = (ix2 - ix1).clamp(0, double.infinity) *
      (iy2 - iy1).clamp(0, double.infinity);
  if (inter <= 0) return 0;
  final aa = pokeBoxArea(a);
  final ba = pokeBoxArea(b);
  final denom = aa + ba - inter;
  return denom <= 0 ? 0 : inter / denom;
}

/// True when [inner] sits mostly inside [outer] (artwork panel inside the card).
bool pokeBoxContainedIn(ScanBox inner, ScanBox outer, {double minOverlap = 0.72}) {
  final innerArea = pokeBoxArea(inner);
  final outerArea = pokeBoxArea(outer);
  if (innerArea < 8 || outerArea <= innerArea * 1.15) return false;
  final ix1 = inner.x1 > outer.x1 ? inner.x1 : outer.x1;
  final iy1 = inner.y1 > outer.y1 ? inner.y1 : outer.y1;
  final ix2 = inner.x2 < outer.x2 ? inner.x2 : outer.x2;
  final iy2 = inner.y2 < outer.y2 ? inner.y2 : outer.y2;
  final inter = (ix2 - ix1).clamp(0, double.infinity) *
      (iy2 - iy1).clamp(0, double.infinity);
  return inter / innerArea >= minOverlap;
}

/// Fixed centered 63:88 viewfinder in the image. Same math as native Single.
ScanBox centerPokeBox({required int width, required int height}) {
  final w = width.toDouble();
  final h = height.toDouble();
  final frame = w / (h <= 0 ? 1 : h);
  final double bw;
  final double bh;
  if (frame >= pokeTargetAspect) {
    bh = h * pokeGuideFill;
    bw = bh * pokeTargetAspect;
  } else {
    bw = w * pokeGuideFill;
    bh = bw / pokeTargetAspect;
  }
  final x1 = (w - bw) / 2;
  final y1 = (h - bh) / 2;
  return ScanBox(x1: x1, y1: y1, x2: x1 + bw, y2: y1 + bh, conf: 1);
}

/// Edge lengths of a possibly rotated quad, not the upright bounding box.
bool isPokeSizeBox(ScanBox box) {
  final c = box.corners;
  if (c.length >= 8) {
    double len(int i, int j) {
      final dx = c[i] - c[j];
      final dy = c[i + 1] - c[j + 1];
      return math.sqrt(dx * dx + dy * dy);
    }

    final top = len(2, 0);
    final bot = len(4, 6);
    final left = len(6, 0);
    final right = len(4, 2);
    return isPokeSizeAspect((top + bot) / 2, (left + right) / 2);
  }
  return isPokeSizeAspect(box.x2 - box.x1, box.y2 - box.y1);
}

/// How much of [box] sits inside the image. Edge-clipped fragments score lower.
double pokeCompleteness(ScanBox box, {required int imgW, required int imgH}) {
  if (imgW <= 0 || imgH <= 0) return 1;
  const m = 4.0;
  var s = 1.0;
  if (box.x1 <= m) s *= 0.45;
  if (box.y1 <= m) s *= 0.45;
  if (box.x2 >= imgW - m) s *= 0.45;
  if (box.y2 >= imgH - m) s *= 0.45;
  return s;
}

/// Area of the 63:88 rectangle itself (edge lengths), not the upright hull.
double pokeQuadArea(ScanBox box) {
  final c = box.corners;
  if (c.length >= 8) {
    double len(int i, int j) {
      final dx = c[i] - c[j];
      final dy = c[i + 1] - c[j + 1];
      return math.sqrt(dx * dx + dy * dy);
    }

    final top = len(2, 0);
    final bot = len(4, 6);
    final left = len(6, 0);
    final right = len(4, 2);
    return ((top + bot) / 2) * ((left + right) / 2);
  }
  return pokeBoxArea(box);
}

double _liveAreaFloor(int imgW, int imgH) {
  // Phone preview (~480×640). 400×400 geometry fixtures keep 6%.
  if (imgW * imgH < 480 * 600) return 0.06;
  final long = imgW > imgH ? imgW : imgH;
  final short = imgW > imgH ? imgH : imgW;
  // 16:9 Camera2 buffers. 3:4 iOS preview stays at 0.25.
  if (short > 0 && long / short >= 1.5) return 0.08;
  return liveMinCardArea;
}

/// Live overlay / identify: 63:88 filling at least [liveMinCardArea] of a
/// phone preview, not a 39×49 panel, inner art `231×292`, or the whole frame.
/// A rotated Vision quad can be a bit smaller than that AABB floor.
/// Multi uses [multiMinCardArea] so a 4×4 page (~6% per card) is kept.
bool isPlausibleLiveCard(
  ScanBox box, {
  required int imgW,
  required int imgH,
  bool multi = false,
}) {
  if (!isPokeSizeBox(box)) return false;
  if (imgW <= 0 || imgH <= 0) return true;
  final frame = imgW * imgH;
  final area = pokeQuadArea(box);
  final minArea = multi
      ? multiMinCardArea
      : (box.isRotated ? 0.12 : _liveAreaFloor(imgW, imgH));
  if (area < minArea * frame) return false;
  if (area > 0.72 * frame) return false;
  const m = 18.0;
  if (box.x1 <= m &&
      box.y1 <= m &&
      box.x2 >= imgW - m &&
      box.y2 >= imgH - m) {
    return false;
  }
  return true;
}

/// High-confidence YOLO object. AABB may be square (45° hull). Overlay may
/// follow this; identify still needs a poke-size / Vision crop.
bool isYoloLockObject(ScanBox box, {required int imgW, required int imgH}) {
  if (box.conf < liveYoloLockConf) return false;
  if (imgW <= 0 || imgH <= 0) return true;
  final frame = imgW * imgH;
  final area = pokeBoxArea(box);
  if (area < _liveAreaFloor(imgW, imgH) * frame) return false;
  if (area > 0.72 * frame) return false;
  const m = 18.0;
  if (box.x1 <= m &&
      box.y1 <= m &&
      box.x2 >= imgW - m &&
      box.y2 >= imgH - m) {
    return false;
  }
  return true;
}

/// How axis-aligned the 63:88 rectangle is (1 = upright, ~0.5 = 45° diamond).
double axisAlignment(ScanBox box) {
  final aabb = pokeBoxArea(box);
  if (aabb <= 1) return 1;
  final align = pokeQuadArea(box) / aabb;
  if (align < 0) return 0;
  if (align > 1) return 1;
  return align;
}

/// Max AABB IoU with any other outer card (self ignored).
double overlapWithOthers(ScanBox box, List<ScanBox> others) {
  var best = 0.0;
  for (final other in others) {
    if (identical(other, box)) continue;
    if ((other.x1 - box.x1).abs() < 1 &&
        (other.y1 - box.y1).abs() < 1 &&
        (other.x2 - box.x2).abs() < 1 &&
        (other.y2 - box.y2).abs() < 1) {
      continue;
    }
    final iou = pokeBoxIou(box, other);
    if (iou > best) best = iou;
  }
  return best;
}

bool isIsolatedCard(
  ScanBox box,
  List<ScanBox> others, {
  double maxIou = 0.22,
}) {
  for (final other in others) {
    if (identical(other, box)) continue;
    if ((other.x1 - box.x1).abs() < 1 &&
        (other.y1 - box.y1).abs() < 1 &&
        (other.x2 - box.x2).abs() < 1 &&
        (other.y2 - box.y2).abs() < 1) {
      continue;
    }
    if (isInnerLivePanel(other, box) || isInnerLivePanel(box, other)) {
      continue;
    }
    if (pokeBoxIou(box, other) > maxIou) return false;
  }
  return true;
}

/// Milo crop: a poke-size outer card that is not sitting on another card.
/// Crossing diamonds (Fearow over Corphish) warp mixed pixels → merch ~0.53.
/// Isolated tilt is still allowed. Conf 0.90 is not required for Vision quads.
bool isLiveIdentifyCrop(
  ScanBox box, {
  required int imgW,
  required int imgH,
  List<ScanBox> others = const [],
  bool multi = false,
}) {
  if (!isPlausibleLiveCard(
    box,
    imgW: imgW,
    imgH: imgH,
    multi: multi,
  )) {
    return false;
  }
  if (others.isNotEmpty && !isIsolatedCard(box, others)) return false;
  return true;
}

/// A 2×2 (or larger) Vision/YOLO rectangle around several binder cards.
/// Each cell is ~25% of a 2×2 host; inner art of one card is a single child.
bool isMultiGroupHost(ScanBox host, List<ScanBox> sized) {
  final hostArea = pokeQuadArea(host);
  if (hostArea <= 1) return false;
  var n = 0;
  for (final other in sized) {
    if (identical(other, host)) continue;
    if (!pokeBoxContainedIn(other, host)) continue;
    if (pokeQuadArea(other) < 0.12 * hostArea) continue;
    n++;
    if (n >= 2) return true;
  }
  return false;
}

/// Inner artwork / text panel sitting inside a larger card object.
/// A 45° Vision diamond inside a YOLO hull is the card, not inner art.
bool isInnerLivePanel(ScanBox inner, ScanBox host) {
  if (isDiamondHull(inner) && !host.isRotated) return false;
  if (!pokeBoxContainedIn(inner, host)) return false;
  return pokeQuadArea(inner) < 0.55 * pokeBoxArea(host);
}

/// True when the quad is a rotated card inside its own AABB (45° diamond).
bool isDiamondHull(ScanBox box) {
  final aabb = pokeBoxArea(box);
  if (aabb <= 1) return false;
  return pokeQuadArea(box) < 0.78 * aabb;
}

/// Single / Multi: outer poke-size rectangles. Drop nested art panels.
List<ScanBox> selectPokeBoxes(
  List<ScanBox> boxes, {
  required bool multi,
  int imgW = 0,
  int imgH = 0,
}) {
  var sized = boxes
      .where(
        (box) => imgW > 0 && imgH > 0
            ? isPlausibleLiveCard(
                  box,
                  imgW: imgW,
                  imgH: imgH,
                  multi: multi,
                ) ||
                isYoloLockObject(box, imgW: imgW, imgH: imgH)
            : isPokeSizeBox(box) || box.conf >= liveYoloLockConf,
      )
      .toList();
  if (multi) {
    final cells = sized.where((b) => !isMultiGroupHost(b, sized)).toList();
    if (cells.isNotEmpty) sized = cells;
    if (imgW > 0 && imgH > 0) {
      final inFrame = sized
          .where((b) => pokeCompleteness(b, imgW: imgW, imgH: imgH) >= 0.3)
          .toList();
      if (inFrame.isNotEmpty) sized = inFrame;
    }
  }
  final outer = sized
      .where(
        (box) => !sized.any(
          (host) => !identical(host, box) && isInnerLivePanel(box, host),
        ),
      )
      .toList()
    ..sort((a, b) {
      if (a.isRotated != b.isRotated && pokeBoxIou(a, b) > 0.25) {
        if (isInnerLivePanel(a, b)) return 1;
        if (isInnerLivePanel(b, a)) return -1;
        if (!isPokeSizeBox(a) || !isPokeSizeBox(b)) {
          return a.isRotated ? -1 : 1;
        }
        final unrot = a.isRotated ? b : a;
        final rot = a.isRotated ? a : b;
        if (pokeBoxArea(unrot) > pokeBoxArea(rot) * 1.6) {
          return a.isRotated ? -1 : 1;
        }
      }
      final align = axisAlignment(b).compareTo(axisAlignment(a));
      if (align != 0) return align;
      if (imgW > 0 && imgH > 0) {
        final complete = pokeCompleteness(b, imgW: imgW, imgH: imgH)
            .compareTo(pokeCompleteness(a, imgW: imgW, imgH: imgH));
        if (complete != 0) return complete;
      }
      return pokeQuadArea(b).compareTo(pokeQuadArea(a));
    });
  final kept = <ScanBox>[];
  for (final box in outer) {
    final nested = kept.any(
      (outer) =>
          pokeBoxIou(box, outer) > 0.45 ||
          pokeBoxContainedIn(box, outer) ||
          (multi && pokeBoxContainedIn(outer, box)),
    );
    if (nested) continue;
    kept.add(box);
    if (!multi) break;
    if (kept.length >= maxMultiCards) break;
  }
  return kept;
}

/// One overlay quad. After the first YOLO >0.9 lock, follow that object by
/// IoU. If we already have Vision corners, do not flash back to a snapped AABB.
ScanBox? stickyOverlayBox({
  ScanBox? follow,
  required List<ScanBox> detected,
  List<ScanBox> current = const [],
  double minIou = 0.40,
}) {
  if (detected.isEmpty) {
    return current.isNotEmpty ? current.first : follow;
  }
    if (follow == null) {
      final locks = [
        for (final box in detected)
          if (box.conf >= liveOverlayConf) box,
      ];
      if (locks.isEmpty) return null;
      locks.sort((a, b) {
        final align = axisAlignment(b).compareTo(axisAlignment(a));
        if (align != 0) return align;
        return pokeQuadArea(b).compareTo(pokeQuadArea(a));
      });
      return locks.first;
    }
    final same = [
      for (final box in detected)
        if (pokeBoxIou(box, follow) >= minIou && box.conf >= liveOverlayConf) box,
    ];
    if (follow.isRotated) {
      final rotated = [
        for (final box in same)
          if (box.isRotated) box,
      ]..sort((a, b) => pokeQuadArea(b).compareTo(pokeQuadArea(a)));
      if (rotated.isNotEmpty) return rotated.first;
      return current.isNotEmpty ? current.first : follow;
    }
    if (same.isNotEmpty) {
      same.sort((a, b) {
        final align = axisAlignment(b).compareTo(axisAlignment(a));
        if (align != 0) return align;
        return pokeQuadArea(b).compareTo(pokeQuadArea(a));
      });
      return same.first;
    }
    final retarget = [
      for (final box in detected)
        if (box.conf >= liveOverlayConf) box,
    ];
  if (retarget.isNotEmpty && pokeBoxIou(retarget.first, follow) < 0.15) {
    return retarget.first;
  }
  return current.isNotEmpty ? current.first : follow;
}

/// Drop a leftover first-lock when a real identify crop is now in the frame.
/// Sticky IoU ≥ 0.40 otherwise keeps a landscape inner panel forever
/// (Fearow: leftover `231×192` vs outer `256×334`, IoU ~0.51).
ScanBox? overlayFollowTarget({
  ScanBox? follow,
  required List<ScanBox> detected,
  required int imgW,
  required int imgH,
}) {
  if (follow == null) return null;
  if (isLiveIdentifyCrop(follow, imgW: imgW, imgH: imgH, others: detected)) {
    return follow;
  }
  if (isPlausibleLiveCard(follow, imgW: imgW, imgH: imgH)) {
    return follow;
  }
  for (final box in detected) {
    if (identical(box, follow)) continue;
    if (isPlausibleLiveCard(box, imgW: imgW, imgH: imgH)) return null;
  }
  return follow;
}

/// Multi: cards already cropped from poke-size boxes, highest Milo first.
List<ScanHit> rankedSeenCards(List<ScanHit> cards, {double minScore = 0.40}) {
  final ranked = cards.where((h) => h.score >= minScore).toList()
    ..sort((a, b) => b.score.compareTo(a.score));
  return ranked;
}

/// Live Single: first cosine ≥ [liveAcceptScore] is a match. No extra
/// stable-hit wait — retry a fresh frame instead.
bool shouldAcceptLive(ScanResult result, {double minScore = liveAcceptScore}) {
  final top = result.top;
  return top != null && top.score >= minScore;
}

/// Identify must not freeze on the first flicker. Overlay can jump from a
/// small inner/partial square to the outer card while Milo is still busy
/// (~1.5 s) on the old pixels. Ready after [need] consecutive detects with
/// IoU ≥ [minIou] on the same object.
class IdentifyStability {
  ScanBox? _box;
  int _hits = 0;

  ScanBox? get box => _box;
  int get hits => _hits;

  void reset() {
    _box = null;
    _hits = 0;
  }

  bool ready(ScanBox box, {double minIou = 0.70, int need = 2}) {
    final prev = _box;
    if (prev != null && pokeBoxIou(prev, box) >= minIou) {
      _hits += 1;
    } else {
      _hits = 1;
    }
    _box = box;
    return _hits >= need;
  }
}

/// First-frame open: unique high Milo score and a card filling the frame.
bool shouldOpenImmediately(ScanResult result, {double minScore = 0.80}) {
  final top = result.top;
  if (top == null || top.score < minScore) return false;
  if (miloNeedsVit(result)) return false;
  final box = boxForHit(result, top);
  if (box == null) return false;
  return yoloBoxFillsCenter(box, imgW: result.imgW, imgH: result.imgH);
}

String speciesToken(String name) {
  final cleaned = name
      .toLowerCase()
      .replaceAll(RegExp(r'\s*\(.*?\)\s*'), ' ')
      .replaceAll(RegExp(r'\s+-\s+.*$'), '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
  if (cleaned.isEmpty) return '';
  final parts = cleaned.split(' ');
  final skip = {'ex', 'gx', 'v', 'vmax', 'vstar', 'lvx', 'mega'};
  for (final part in parts) {
    if (part.isEmpty || skip.contains(part)) continue;
    return part;
  }
  return parts.first;
}

bool relatedLine(String a, String b) {
  if (a.isEmpty || b.isEmpty || a == b) return false;
  final n = a.length < b.length ? a.length : b.length;
  if (n < 6) return false;
  return a.substring(0, 6) == b.substring(0, 6);
}

bool miloNeedsVit(ScanResult result) {
  final hits = result.hits;
  if (hits.isEmpty) return true;
  final top = hits.first;
  if (top.score < 0.70) return true;
  if (hits.length >= 2 &&
      top.score - hits[1].score < 0.08 &&
      !sameSpecies(top.name, hits[1].name)) {
    return true;
  }
  final tokens = hits.take(5).map((h) => speciesToken(h.name)).where((t) => t.isNotEmpty).toList();
  for (var i = 0; i < tokens.length; i++) {
    for (var j = i + 1; j < tokens.length; j++) {
      if (relatedLine(tokens[i], tokens[j])) return true;
    }
  }
  return false;
}

bool sameSpecies(String a, String b) {
  final left = speciesToken(a);
  final right = speciesToken(b);
  return left.isNotEmpty && left == right;
}
