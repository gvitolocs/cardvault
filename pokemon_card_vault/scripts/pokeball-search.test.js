const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.join(__dirname, '..');
const homeScreenPath = path.join(root, 'lib', 'screens', 'home_screen.dart');
const pokeballPath = path.join(root, 'assets', 'icons', 'pokepalla.svg');

test('marketplace search uses the Poké Ball asset and spins it on tap', () => {
  const source = fs.readFileSync(homeScreenPath, 'utf8');

  assert.match(source, /import 'package:flutter_svg\/flutter_svg\.dart';/);
  assert.match(source, /with SingleTickerProviderStateMixin/);
  assert.match(source, /AnimationController\s+_pokeballController/);
  assert.match(source, /void _spinPokeball\(\)/);
  assert.match(source, /onTap:\s*\(\)\s*\{\s*_spinPokeball\(\);/s);
  assert.match(source, /Positioned\([\s\S]*Poké Ball search[\s\S]*RotationTransition\([\s\S]*assets\/icons\/pokepalla\.svg/);
});

test('Poké Ball SVG is bundled and contains only finite SVG values', () => {
  const svg = fs.readFileSync(pokeballPath, 'utf8');

  assert.match(svg, /^<svg\b/);
  assert.doesNotMatch(svg, /NaN|undefined/);
  assert.match(svg, /<radialGradient\b/);
  assert.match(svg, /<ellipse\b/);
});
