import 'package:flutter/material.dart';
import '../constants/cardex_artwork_constants.dart';

abstract final class CardexStyle {
  static const sleeve = Color(0xFF242C3B);
  static const seam = Color(0xFF111622);
  static const accent = Color(0xFFE9FF72);
  static const page = Color(0xFF3B4B65);
  static const pageEdge = Color(0xFF29364B);
  static const cardAspectRatio = CardexArtworkConstants.portraitAspectRatio;
  static const captionGradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0x00000000), Color(0xD9000000)]);
  static const grayscale = ColorFilter.matrix([
    .2126,
    .7152,
    .0722,
    0,
    0,
    .2126,
    .7152,
    .0722,
    0,
    0,
    .2126,
    .7152,
    .0722,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]);
}
