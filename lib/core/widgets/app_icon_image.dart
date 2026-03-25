import "package:flutter/material.dart";

import "../constants/app_assets.dart";

/// Renders the app launcher artwork from [AppAssets.appIconPng] (circle crop).
class AppIconImage extends StatelessWidget {
  const AppIconImage({
    super.key,
    this.size = 48,
    this.fit = BoxFit.cover,
  });

  final double size;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Image.asset(
          AppAssets.appIconPng,
          fit: fit,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
        ),
      ),
    );
  }
}
