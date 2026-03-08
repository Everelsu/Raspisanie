import 'package:flutter/material.dart';

class CustomProgressIndicator extends StatelessWidget {
  const CustomProgressIndicator({
    super.key,
    this.progressIndicatorColor,
    this.size = 48.0,
    this.strokeWidth = 4.0,
    this.backgroundColor,
    this.padding = EdgeInsets.zero,
  });

  final Color? progressIndicatorColor;
  final double size;
  final double strokeWidth;
  final Color? backgroundColor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: padding,
        child: SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            color: progressIndicatorColor ?? theme.primaryColor,
            strokeWidth: strokeWidth,
            backgroundColor: backgroundColor,
          ),
        ),
      ),
    );
  }
}
