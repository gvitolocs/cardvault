import 'package:flutter/material.dart';

import 'card.dart';

// Dati locali del prototipo: queste carte non sono offerte acquistabili.
const demoExpansions = ['Scintille', '151', 'Evoluzioni'];
const demoCards = [
  DemoCard('demo-1', 'Pikachu ex', 'Scintille', '238/191', 24.90,
      Color(0xFFFFD76B), Icons.bolt_rounded),
  DemoCard('demo-2', 'Charizard ex', '151', '199/165', 39.50, Color(0xFFFF997A),
      Icons.local_fire_department_rounded),
  DemoCard('demo-3', 'Umbreon', 'Evoluzioni', '215/203', 18.00,
      Color(0xFFC3A5FF), Icons.nightlight_round),
  DemoCard('demo-4', 'Mew ex', '151', '205/165', 12.90, Color(0xFFFFB1D9),
      Icons.auto_awesome_rounded),
];
