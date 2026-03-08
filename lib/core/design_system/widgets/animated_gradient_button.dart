import 'package:flutter/material.dart';

import '../colors.dart';
import 'custom_text.dart';

class AnimatedGradientButton extends StatelessWidget {
  const AnimatedGradientButton({
    super.key,
    required this.text,
    required this.onPressed,
    required this.isEnabled,
    this.textStyle,
    this.borderRadius = 24,
    this.height = 52,
    this.iconSize = 20,
    this.animationDuration = 400,
    this.trailingIcon = Icons.arrow_forward,
  });

  final String text;
  final VoidCallback? onPressed;
  final bool isEnabled;
  final TextStyle? textStyle;
  final double borderRadius;
  final double height;
  final double iconSize;
  final int animationDuration;
  final IconData trailingIcon;

  @override
  Widget build(BuildContext context) {
    final buttonTextStyle = textStyle ??
        const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 1.2, color: white);

    return Padding(
      padding: const EdgeInsets.all(28),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: isEnabled ? 1 : 0),
        duration: Duration(milliseconds: animationDuration),
        curve: Curves.easeInOut,
        builder: (context, value, _) {
          final startColor = Color.lerp(buttonGradientInactiveStart, buttonGradientActiveStart, value)!;
          final endColor = Color.lerp(buttonGradientInactiveEnd, buttonGradientActiveEnd, value)!;
          final shadowColor = customIndigoColor.withValues(alpha: 0.3 * value);
          final circleColor = Color.lerp(whiteWithOpacity10, whiteWithOpacity30, value)!;

          return Material(
            color: transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(borderRadius),
              splashColor: isEnabled ? whiteWithOpacity12 : transparent,
              highlightColor: isEnabled ? whiteWithOpacity10 : transparent,
              onTap: isEnabled ? onPressed : null,
              child: Container(
                width: double.infinity,
                height: height,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    stops: const [0.0, 0.4, 0.85, 1.0],
                    colors: [
                      startColor,
                      Color.lerp(startColor, endColor, 0.35)!,
                      Color.lerp(startColor, endColor, 0.7)!,
                      endColor,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(borderRadius),
                  boxShadow: [
                    BoxShadow(color: shadowColor, blurRadius: 8 * value, offset: Offset(0, 4 * value)),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    CustomText(text: text.toUpperCase(), style: buttonTextStyle, color: white),
                    Container(
                      height: 36,
                      width: 36,
                      decoration: BoxDecoration(color: circleColor, shape: BoxShape.circle),
                      child: Center(child: Icon(trailingIcon, color: white, size: iconSize)),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
