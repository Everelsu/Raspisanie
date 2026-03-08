import 'package:flutter/material.dart';

import '../colors.dart';
import '../enums/button_size_enum.dart';
import '../enums/button_type_enum.dart';
import 'custom_text.dart';

class CustomButton extends StatelessWidget {
  const CustomButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.buttonSize = ButtonSizeEnum.medium,
    this.buttonType = ButtonTypeEnum.primary,
    this.isFullWidth = false,
    this.icon,
    this.isLoading = false,
    this.borderRadius,
  });

  final String text;
  final VoidCallback onPressed;
  final ButtonSizeEnum buttonSize;
  final ButtonTypeEnum buttonType;
  final bool isFullWidth;
  final Widget? icon;
  final bool isLoading;
  final double? borderRadius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    double height = switch (buttonSize) {
      ButtonSizeEnum.small => 36.0,
      ButtonSizeEnum.medium => 48.0,
      ButtonSizeEnum.large => 56.0,
    };
    ButtonStyle buttonStyle = switch (buttonType) {
      ButtonTypeEnum.primary => ElevatedButton.styleFrom(
          backgroundColor: theme.primaryColor,
          foregroundColor: white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(borderRadius ?? 24)),
        ),
      ButtonTypeEnum.secondary => ElevatedButton.styleFrom(
          backgroundColor: white,
          foregroundColor: theme.primaryColor,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(borderRadius ?? 24),
            side: BorderSide(color: theme.primaryColor),
          ),
        ),
      ButtonTypeEnum.text => TextButton.styleFrom(
          foregroundColor: theme.primaryColor,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(borderRadius ?? 24)),
        ),
    };
    Color textColor = switch (buttonType) {
      ButtonTypeEnum.primary => white,
      ButtonTypeEnum.secondary => theme.primaryColor,
      ButtonTypeEnum.text => theme.primaryColor,
    };
    Widget buttonChild = isLoading
        ? SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: textColor),
          )
        : (icon != null)
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  icon!,
                  const SizedBox(width: 8),
                  CustomText(text: text, color: textColor),
                ],
              )
            : CustomText(text: text, color: textColor);
    Widget buttonWidget = switch (buttonType) {
      ButtonTypeEnum.primary || ButtonTypeEnum.secondary => SizedBox(
          height: height,
          width: isFullWidth ? double.infinity : null,
          child: ElevatedButton(
            onPressed: isLoading ? null : onPressed,
            style: buttonStyle,
            child: buttonChild,
          ),
        ),
      ButtonTypeEnum.text => SizedBox(
          height: height,
          width: isFullWidth ? double.infinity : null,
          child: TextButton(
            onPressed: isLoading ? null : onPressed,
            style: buttonStyle,
            child: buttonChild,
          ),
        ),
    };
    return buttonWidget;
  }
}
