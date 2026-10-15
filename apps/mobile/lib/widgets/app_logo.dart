import 'package:flutter/material.dart';

/// The HuanHermes brand mark (same artwork as the Android launcher icon).
///
/// Falls back to a gradient tile with a terminal glyph if the asset is ever
/// missing, so a packaging mistake can never crash a screen.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 32});

  static const asset = 'assets/brand/app_icon.png';
  static const gradientStart = Color(0xFF4F46E5);
  static const gradientEnd = Color(0xFF9333EA);

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'HuanHermes',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: Image.asset(
          asset,
          width: size,
          height: size,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stack) => _fallback(),
        ),
      ),
    );
  }

  Widget _fallback() {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.2237),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [gradientStart, gradientEnd],
        ),
      ),
      child: Icon(Icons.terminal_rounded,
          size: size * 0.6, color: Colors.white),
    );
  }
}
