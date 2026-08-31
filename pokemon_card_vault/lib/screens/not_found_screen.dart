import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../utils/public_home.dart';

class PokoinNotFoundScreen extends StatelessWidget {
  const PokoinNotFoundScreen({super.key, required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF050816),
      body: SafeArea(
        child: Stack(
          children: [
            const Positioned.fill(child: _NotFoundBackground()),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xF20B1020),
                      borderRadius: BorderRadius.circular(34),
                      border: Border.all(color: const Color(0x3DFACC15)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x8A000000),
                          blurRadius: 48,
                          offset: Offset(0, 28),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 34,
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth >= 680;
                          const visual = _WobbuffetNotFoundVisual();
                          final copy = _NotFoundCopy(location: location);

                          if (isWide) {
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Expanded(child: visual),
                                const SizedBox(width: 34),
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: copy,
                                  ),
                                ),
                              ],
                            );
                          }

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              visual,
                              const SizedBox(height: 28),
                              copy,
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotFoundCopy extends StatelessWidget {
  const _NotFoundCopy({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    final routeLabel = location.isEmpty ? 'this page' : location;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '404',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFFFACC15),
            fontSize: 72,
            fontWeight: FontWeight.w900,
            height: 0.9,
            letterSpacing: -3,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Wobba wobba... page not found',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w800,
            height: 1.08,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Even our blue buddy bounced off the route for $routeLabel. Head back to the marketplace and keep hunting.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFFCBD5E1),
            fontSize: 16,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 28),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: () => context.go('/marketplace'),
              icon: const Icon(Icons.storefront_rounded),
              label: const Text('Back to marketplace'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFACC15),
                foregroundColor: const Color(0xFF111827),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 16,
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => goPublicHome(context),
              icon: const Icon(Icons.home_rounded),
              label: const Text('Go home'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFF38BDF8)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _WobbuffetNotFoundVisual extends StatelessWidget {
  const _WobbuffetNotFoundVisual();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Friendly blue 404 mascot',
      child: SizedBox(
        width: 260,
        height: 330,
        child: Image.asset(
          'assets/images/wobbuffet_404.png',
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}

class _NotFoundBackground extends StatelessWidget {
  const _NotFoundBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF050816),
            Color(0xFF0B1020),
            Color(0xFF111827),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -70,
            left: -50,
            child: _glow(const Color(0x3338BDF8), 220),
          ),
          Positioned(
            right: -80,
            bottom: -100,
            child: _glow(const Color(0x33FACC15), 260),
          ),
        ],
      ),
    );
  }

  static Widget _glow(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color, blurRadius: 80, spreadRadius: 40),
        ],
      ),
    );
  }
}
