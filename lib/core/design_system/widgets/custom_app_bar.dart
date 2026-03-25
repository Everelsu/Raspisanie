import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../colors.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  CustomAppBar({
    super.key,
    this.title,
    this.backgroundColor,
    this.leading,
    this.isTitleCentered = true,
    this.titleColor = black,
    this.titleFontSize = 20,
    this.titleFontWeight = FontWeight.w600,
    this.actions,
    this.elevation = 0,
    this.extraHeight = 8,
    this.bottom,
    this.systemOverlayStyle,
    this.showBackButton = false,
    this.onBackPressed,
  }) : preferredSize = Size.fromHeight(kToolbarHeight + extraHeight + (bottom?.preferredSize.height ?? 0));

  @override
  final Size preferredSize;

  final bool isTitleCentered;
  final String? title;
  final Color? backgroundColor;
  final Color titleColor;
  final double titleFontSize;
  final FontWeight titleFontWeight;
  final Widget? leading;
  final List<Widget>? actions;
  final double elevation;
  final double extraHeight;
  final PreferredSizeWidget? bottom;
  final SystemUiOverlayStyle? systemOverlayStyle;
  final bool showBackButton;
  final VoidCallback? onBackPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget? leadingWidget = leading;
    if (showBackButton && leadingWidget == null) {
      leadingWidget = IconButton(
        icon: const Icon(Icons.arrow_back, color: black),
        onPressed: onBackPressed ?? () => Navigator.of(context).pop(),
      );
    }
    final Widget? appBarTitle = title != null
        ? Text(
            title!,
            style: theme.textTheme.titleLarge?.copyWith(
                  color: titleColor,
                  fontSize: titleFontSize,
                  fontWeight: titleFontWeight,
                ) ??
                TextStyle(
                  color: titleColor,
                  fontSize: titleFontSize,
                  fontWeight: titleFontWeight,
                ),
          )
        : null;
    final effectiveSystemOverlayStyle = systemOverlayStyle ??
        SystemUiOverlayStyle(
          statusBarColor: transparent,
          statusBarIconBrightness:
              _isLightColor(backgroundColor ?? theme.scaffoldBackgroundColor) ? Brightness.dark : Brightness.light,
          statusBarBrightness:
              _isLightColor(backgroundColor ?? theme.scaffoldBackgroundColor) ? Brightness.light : Brightness.dark,
        );
    return AppBar(
      centerTitle: isTitleCentered,
      backgroundColor: backgroundColor ?? theme.scaffoldBackgroundColor,
      toolbarHeight: kToolbarHeight + extraHeight,
      elevation: elevation,
      leadingWidth: 56,
      leading: leadingWidget,
      actions: actions,
      surfaceTintColor: backgroundColor,
      shadowColor: transparent,
      title: appBarTitle,
      bottom: bottom,
      systemOverlayStyle: effectiveSystemOverlayStyle,
      scrolledUnderElevation: 0.5,
    );
  }

  bool _isLightColor(Color color) {
    final r = color.r;
    final g = color.g;
    final b = color.b;
    final brightness = 0.299 * r + 0.587 * g + 0.114 * b;
    return brightness > 0.5;
  }
}
