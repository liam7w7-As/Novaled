import 'package:flutter/material.dart';

class NovaledThickIcon extends StatelessWidget {
  final String assetPath;
  final double size;
  final Color color;
  final IconData? fallbackIcon;
  final double strokeOffset;

  const NovaledThickIcon({
    super.key,
    required this.assetPath,
    this.size = 24.0,
    required this.color,
    this.fallbackIcon,
    this.strokeOffset = 0.35,
  });

  @override
  Widget build(BuildContext context) {
    final double offset = strokeOffset;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Image.asset(
            assetPath,
            width: size,
            height: size,
            color: color,
            filterQuality: FilterQuality.high,
            errorBuilder: (context, error, stackTrace) => Icon(fallbackIcon ?? Icons.arrow_back_rounded, color: color, size: size),
          ),
          Transform.translate(
            offset: Offset(offset, 0),
            child: Image.asset(
              assetPath,
              width: size,
              height: size,
              color: color,
              filterQuality: FilterQuality.high,
              errorBuilder: (context, error, stackTrace) => const SizedBox(),
            ),
          ),
          Transform.translate(
            offset: Offset(-offset, 0),
            child: Image.asset(
              assetPath,
              width: size,
              height: size,
              color: color,
              filterQuality: FilterQuality.high,
              errorBuilder: (context, error, stackTrace) => const SizedBox(),
            ),
          ),
          Transform.translate(
            offset: Offset(0, offset),
            child: Image.asset(
              assetPath,
              width: size,
              height: size,
              color: color,
              filterQuality: FilterQuality.high,
              errorBuilder: (context, error, stackTrace) => const SizedBox(),
            ),
          ),
          Transform.translate(
            offset: Offset(0, -offset),
            child: Image.asset(
              assetPath,
              width: size,
              height: size,
              color: color,
              filterQuality: FilterQuality.high,
              errorBuilder: (context, error, stackTrace) => const SizedBox(),
            ),
          ),
          Transform.translate(
            offset: Offset(offset * 0.7, offset * 0.7),
            child: Image.asset(
              assetPath,
              width: size,
              height: size,
              color: color,
              filterQuality: FilterQuality.high,
              errorBuilder: (context, error, stackTrace) => const SizedBox(),
            ),
          ),
          Transform.translate(
            offset: Offset(-offset * 0.7, -offset * 0.7),
            child: Image.asset(
              assetPath,
              width: size,
              height: size,
              color: color,
              filterQuality: FilterQuality.high,
              errorBuilder: (context, error, stackTrace) => const SizedBox(),
            ),
          ),
        ],
      ),
    );
  }
}
