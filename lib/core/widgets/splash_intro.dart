import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme.dart' show AppThemeColors;
import '../motion.dart';
import 'refresh_logo_mark.dart';

/// Анимированный сплэш поверх приложения (только холодный старт).
///
/// Приложение строится в самом первом кадре, пока ещё висит нативный
/// сплэш, — тяжёлая первая сборка не роняет кадры анимации и не добавляет
/// паузу. Дальше: если иконка лаунчера другого цвета, цвет темы расходится
/// волной из-под знака; затем камера влетает в левое треугольное окно
/// знака, а сквозь окно уже видно приложение, которое мягко «подъезжает»
/// из глубины. Окно в конце больше экрана — оверлей просто кончается, без
/// растворения.
///
/// При «Уменьшении движения» — короткое растворение без полёта.
class SplashIntro extends StatefulWidget {
  const SplashIntro({super.key, required this.fromColors, required this.child});

  /// Цвета темы, чья иконка сейчас стоит в лаунчере.
  final AppThemeColors fromColors;

  final Widget child;

  @override
  State<SplashIntro> createState() => _SplashIntroState();
}

class _SplashIntroState extends State<SplashIntro>
    with TickerProviderStateMixin {
  late final AnimationController _wave;
  late final AnimationController _zoom;
  bool _done = false;
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    _wave = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 420));
    _zoom = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 720));
    _run();
  }

  Future<void> _run() async {
    // Два кадра: первый — сборка приложения, второй — гарантия, что он
    // дошёл до экрана. Всё это время пользователь видит нативный сплэш.
    await WidgetsBinding.instance.endOfFrame;
    // Шрифт темы (google_fonts) грузится асинхронно — ждём его под
    // нативным сплэшем, иначе после раскрытия весь текст перескочил бы
    // с запасного шрифта на нужный. Офлайн-первый запуск не держим долго.
    try {
      await GoogleFonts.pendingFonts()
          .timeout(const Duration(milliseconds: 700));
    } catch (_) {}
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    if (!kIsWeb) FlutterNativeSplash.remove();
    // Хитч от снятия нативного вью приходится на неподвижный кадр.
    await Future<void>.delayed(const Duration(milliseconds: 60));
    if (!mounted) return;

    if (AppMotion.reduced(context)) setState(() => _reduced = true);
    final theme = Theme.of(context);
    final needsWave = !_reduced &&
        (widget.fromColors.surface != theme.scaffoldBackgroundColor ||
            widget.fromColors.primary != theme.colorScheme.primary);
    if (needsWave) {
      await _wave.forward();
    } else {
      _wave.value = 1;
    }
    if (!mounted) return;
    if (_reduced) _zoom.duration = const Duration(milliseconds: 220);
    await _zoom.forward();
    if (mounted) setState(() => _done = true);
  }

  @override
  void dispose() {
    _wave.dispose();
    _zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Структура Stack не меняется на протяжении всей анимации и после неё —
    // иначе Flutter пересоздал бы HomePage (потеря state = мерцание в конце).
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedBuilder(
          animation: _zoom,
          child: RepaintBoundary(child: widget.child),
          builder: (context, child) {
            // Приложение «подъезжает» из глубины, пока камера пролетает
            // окно: трансформ поверх готового слоя — без перерисовки.
            final t = _reduced
                ? 1.0
                : Curves.easeOutCubic
                    .transform(((_zoom.value - 0.2) / 0.8).clamp(0.0, 1.0));
            return Transform.scale(scale: 1.08 - 0.08 * t, child: child);
          },
        ),
        if (!_done)
          IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                size: Size.infinite,
                painter: _SplashPainter(
                  wave: _wave,
                  zoom: _zoom,
                  reduced: _reduced,
                  bgFrom: widget.fromColors.surface,
                  fgFrom: widget.fromColors.primary,
                  bgTo: theme.scaffoldBackgroundColor,
                  fgTo: theme.colorScheme.primary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Весь оверлей одним painter'ом: фон с волной, окно-проём и знак.
/// Перерисовывается от анимаций напрямую (repaint), без пересборки виджетов.
class _SplashPainter extends CustomPainter {
  _SplashPainter({
    required this.wave,
    required this.zoom,
    required this.reduced,
    required this.bgFrom,
    required this.fgFrom,
    required this.bgTo,
    required this.fgTo,
  }) : super(repaint: Listenable.merge([wave, zoom]));

  final Animation<double> wave;
  final Animation<double> zoom;
  final bool reduced;
  final Color bgFrom, fgFrom, bgTo, fgTo;

  static const _logoWidth = 120.0;
  static const _unit = _logoWidth / 615;
  static const _logoCenter = Offset(307.5, 215.5);
  // Центр вписанной окружности левого окна и её радиус (в единицах знака):
  // туда летит камера, и по радиусу считаем, когда окно накроет экран.
  static const _holeCenter = Offset(131.4, 215.7);
  static const _holeInradius = 76.4;
  // Масштаб экспоненциальный (постоянная «скорость полёта» в восприятии),
  // поверх — мягкий ease-in-out: без долгого замирания и рывка в конце.
  static const _zoomCurve = Cubic(0.42, 0, 0.58, 1);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = size.center(Offset.zero);
    final waveT = Curves.fastOutSlowIn.transform(wave.value);
    final z = zoom.value;

    if (reduced) {
      final a = 1 - z;
      canvas.drawRect(rect, Paint()..color = bgTo.withValues(alpha: a));
      _drawLogo(canvas, _logoMatrix(center, 1, 0), fgTo.withValues(alpha: a));
      return;
    }

    // Масштаб растёт экспоненциально — равномерная «скорость полёта».
    // Конечный — такой, чтобы окно гарантированно накрыло экран.
    final halfDiag = size.shortestSide <= 0
        ? 0.0
        : math.sqrt(size.width * size.width + size.height * size.height) / 2;
    final maxScale = math.max(8.0, halfDiag / (_holeInradius * _unit) * 1.15);
    final e = _zoomCurve.transform(z);
    final scale = math.pow(maxScale, e).toDouble();
    final m = _logoMatrix(center, scale, e);

    final bg = Color.lerp(bgFrom, bgTo, waveT)!;
    final fgT = (waveT / 0.35).clamp(0.0, 1.0);
    final fg = Color.lerp(fgFrom, fgTo, fgT)!;

    if (z <= 0) {
      // Статичная фаза (и волна): сплошной фон, окно ещё «застеклено».
      _paintBackground(canvas, rect, size, center, waveT);
    } else {
      final hole = logoMarkLeftHole.transform(m.storage);
      canvas.save();
      canvas.clipPath(Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(rect)
        ..addPath(hole, Offset.zero));
      canvas.drawRect(rect, Paint()..color = bg);
      canvas.restore();
      // «Стекло» в окне тает в начале полёта — сквозь него видно приложение.
      final glass = 1 - (z / 0.35).clamp(0.0, 1.0);
      if (glass > 0) {
        canvas.drawPath(hole, Paint()..color = bg.withValues(alpha: glass));
      }
    }
    _drawLogo(canvas, m, fg);
  }

  /// Знак по центру экрана; по мере полёта [e] центр окна съезжает в центр.
  Matrix4 _logoMatrix(Offset center, double scale, double e) {
    final shift = (_holeCenter - _logoCenter) * _unit * scale * e;
    return Matrix4.translationValues(
        center.dx - shift.dx, center.dy - shift.dy, 0)
      ..scaleByDouble(_unit * scale, _unit * scale, 1, 1)
      ..translateByDouble(-_logoCenter.dx, -_logoCenter.dy, 0, 1);
  }

  void _drawLogo(Canvas canvas, Matrix4 m, Color color) {
    canvas.save();
    canvas.transform(m.storage);
    canvas.drawPath(logoMarkPath, Paint()..color = color);
    canvas.restore();
  }

  /// Цвет [bgFrom], поверх которого из центра расходится круг [bgTo] с
  /// мягкой кромкой. Без шейдеров: RadialGradient на каждом кадре давал
  /// компиляцию шейдера и подёргивал волну — кромку дают два кольца.
  void _paintBackground(
      Canvas canvas, Rect rect, Size size, Offset center, double t) {
    canvas.drawRect(rect, Paint()..color = bgFrom);
    if (t <= 0) return;
    final maxR = math.sqrt(
      size.width * size.width / 4 + size.height * size.height / 4,
    );
    final r = maxR * t;
    canvas.drawCircle(center, r, Paint()..color = bgTo);
    canvas.drawCircle(
        center, r + maxR * 0.02, Paint()..color = bgTo.withValues(alpha: 0.35));
    canvas.drawCircle(center, r + maxR * 0.045,
        Paint()..color = bgTo.withValues(alpha: 0.12));
  }

  @override
  bool shouldRepaint(_SplashPainter old) =>
      old.reduced != reduced ||
      old.bgFrom != bgFrom ||
      old.fgFrom != fgFrom ||
      old.bgTo != bgTo ||
      old.fgTo != fgTo;
}
