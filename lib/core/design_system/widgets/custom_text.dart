import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../colors.dart';

class CustomText extends StatelessWidget {
  const CustomText({
    super.key,
    required this.text,
    this.color,
    this.fontWeight,
    this.fontSize,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.letterSpacing,
    this.height,
    this.textDecoration,
  });

  final String text;
  final Color? color;
  final FontWeight? fontWeight;
  final double? fontSize;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final double? letterSpacing;
  final double? height;
  final TextDecoration? textDecoration;

  @override
  Widget build(BuildContext context) {
    final TextStyle defaultStyle = GoogleFonts.roboto(
      color: color ?? black,
      fontWeight: fontWeight ?? FontWeight.w500,
      fontSize: fontSize ?? 14,
      letterSpacing: letterSpacing,
      height: height,
      decoration: textDecoration,
    );
    final TextStyle effectiveStyle = style ?? defaultStyle;
    return Text(
      text,
      style: effectiveStyle,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
