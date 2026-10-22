import 'package:flutter/widgets.dart';

/// Движение по Apple HIG (Motion): короткое, физичное, без «желе» и без
/// движения ради движения; при системном «Уменьшении движения» —
/// мгновенно.
abstract final class AppMotion {
  /// Пружина без отскока — листы, раскрытие, появление панелей.
  static final smooth = SpringDescription.withDurationAndBounce(
      duration: const Duration(milliseconds: 420));

  /// Пружина с лёгким отскоком — индикаторы выбора.
  static final snappy = SpringDescription.withDurationAndBounce(
      duration: const Duration(milliseconds: 380), bounce: 0.2);

  /// Кривая iOS-листа: резвый старт, долгое мягкое торможение.
  static const sheetCurve = Cubic(0.32, 0.72, 0, 1);

  /// Модальные шторки (`showModalBottomSheet(sheetAnimationStyle: …)`).
  static const sheet = AnimationStyle(
    duration: Duration(milliseconds: 440),
    reverseDuration: Duration(milliseconds: 260),
    curve: sheetCurve,
    reverseCurve: Curves.easeInCubic,
  );

  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}
