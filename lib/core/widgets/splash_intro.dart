import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import '../../app/theme.dart' show AppThemeColors;
import 'refresh_logo_mark.dart';

/// Анимированный сплэш поверх приложения.
///
/// Холодный старт: знак в цветах иконки лаунчера; цвет темы приложения
/// расходится круговой волной из-под знака (как капля чернил) и накрывает
/// цвет иконки, затем камера влетает внутрь левого кольца знака и оверлей
/// растворяется. Приложение строится в паузе между волной и зумом за
/// статичным оверлеем — его первая сборка не роняет кадры анимаций.
///
/// Возврат из фона: та же волна + растворение, без зума.
class SplashIntro extends StatefulWidget {
  const SplashIntro({super.key, required this.fromColors, required this.child});

  /// Цвета темы, чья иконка сейчас стоит в лаунчере.
  final AppThemeColors fromColors;

  final Widget child;

  @override
  State<SplashIntro> createState() => _SplashIntroState();
}

class _SplashIntroState extends State<SplashIntro>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const _logoWidth = 120.0;

  // Реплей показываем, только если приложение было в фоне дольше этого
  // (отсекает шторки/диалоги, но ловит реальные повторные входы).
  static const _replayAfterBackground = Duration(seconds: 2);

  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  late final AnimationController _zoom = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  );
  late final AnimationController _fadeOut = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  bool _showChild = false;
  bool _done = false;
  bool _replaying = false;
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _run();
  }

  Future<void> _run() async {
    // Держим нативный сплэш все первые статичные кадры и убираем его
    // ПЕРЕД самым стартом волны: возможный хитч от снятия нативного вью
    // приходится на неподвижную картинку, а волна стартует уже чистой.
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    FlutterNativeSplash.remove();
    await Future<void>.delayed(const Duration(milliseconds: 48));
    if (!mounted) return;
    // Пока идёт волна, приложение НЕ строится — дерево под оверлеем пустое,
    // и анимация не теряет кадры из-за тяжёлой первой сборки.
    await _wave.forward();
    if (!mounted) return;
    // Монтируем приложение за статичным непрозрачным оверлеем: вся его
    // первая сборка происходит в паузе, когда ничего не движется.
    setState(() => _showChild = true);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    await _zoom.forward();
    if (mounted) setState(() => _done = true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _pausedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final pausedAt = _pausedAt;
      _pausedAt = null;
      if (pausedAt == null || !_done || _replaying) return;
      if (DateTime.now().difference(pausedAt) < _replayAfterBackground) return;
      final theme = Theme.of(context);
      final sameColors =
          widget.fromColors.surface == theme.scaffoldBackgroundColor &&
              widget.fromColors.primary == theme.colorScheme.primary;
      if (sameColors) return;
      _replay();
    }
  }

  Future<void> _replay() async {
    setState(() {
      _done = false;
      _replaying = true;
    });
    _wave.value = 0;
    _fadeOut.value = 0;
    await _wave.animateTo(1.0, duration: const Duration(milliseconds: 400));
    if (!mounted) return;
    await _fadeOut.forward();
    if (!mounted) return;
    setState(() {
      _done = true;
      _replaying = false;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wave.dispose();
    _zoom.dispose();
    _fadeOut.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgFrom = widget.fromColors.surface;
    final fgFrom = widget.fromColors.primary;
    final bgTo = theme.scaffoldBackgroundColor;
    final fgTo = theme.colorScheme.primary;

    // Структура Stack не меняется на протяжении всей анимации и после неё —
    // иначе Flutter пересоздал бы HomePage (потеря state = мерцание в конце).
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_showChild)
          RepaintBoundary(child: widget.child)
        else
          const SizedBox.expand(),
        if (!_done)
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: Listenable.merge([_wave, _zoom, _fadeOut]),
              builder: (context, _) {
                final waveT = Curves.fastOutSlowIn.transform(_wave.value);

                final double opacity;
                double zoomT = 0;
                if (_replaying) {
                  opacity = 1.0 - Curves.easeOut.transform(_fadeOut.value);
                } else {
                  zoomT = Curves.easeInCubic.transform(_zoom.value);
                  opacity = _zoom.value < 0.75
                      ? 1.0
                      : 1.0 - ((_zoom.value - 0.75) / 0.25);
                }
                final a = opacity.clamp(0.0, 1.0);

                // Знак перекрашивается быстро, в первой трети волны — фронт
                // расходится из-под него, и он «первым» получает новый цвет.
                final fgT = (waveT / 0.35).clamp(0.0, 1.0);
                final fg =
                    Color.lerp(fgFrom, fgTo, fgT)!.withValues(alpha: a);

                // Камера влетает внутрь левого кольца знака.
                final ringShift = 147.5 * (_logoWidth / 615);
                final scale = 1.0 + zoomT * 26.0;

                return IgnorePointer(
                  child: CustomPaint(
                    painter: _RippleTintPainter(
                      from: bgFrom,
                      to: bgTo,
                      t: waveT,
                      alpha: a,
                    ),
                    child: Center(
                      child: Transform.translate(
                        offset: Offset(ringShift * zoomT * scale, 0),
                        child: Transform.scale(
                          scale: scale,
                          child: RefreshLogoMark(size: _logoWidth, color: fg),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// Фон сплэша: цвет [from], поверх которого из центра расходится круг
/// цвета [to] с мягкой кромкой. [t] — прогресс волны (0 — нет круга,
/// 1 — круг накрыл весь экран). [alpha] — общая прозрачность оверлея
/// на этапе растворения (без Opacity-виджета — дёшево для GPU).
class _RippleTintPainter extends CustomPainter {
  const _RippleTintPainter({
    required this.from,
    required this.to,
    required this.t,
    required this.alpha,
  });

  final Color from;
  final Color to;
  final double t;
  final double alpha;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = from.withValues(alpha: alpha));
    if (t <= 0) return;

    final center = size.center(Offset.zero);
    final maxR = math.sqrt(
      size.width * size.width / 4 + size.height * size.height / 4,
    );
    final r = maxR * t;
    // Сплошной круг без шейдеров: RadialGradient на каждом кадре давал
    // компиляцию/аллокацию шейдера и подёргивал волну. Мягкость кромки
    // дают два дешёвых полупрозрачных кольца поверх основного круга.
    final toA = to.withValues(alpha: alpha);
    canvas.drawCircle(center, r, Paint()..color = toA..isAntiAlias = true);
    canvas.drawCircle(
      center,
      r + maxR * 0.02,
      Paint()..color = toA.withValues(alpha: alpha * 0.35)..isAntiAlias = true,
    );
    canvas.drawCircle(
      center,
      r + maxR * 0.045,
      Paint()..color = toA.withValues(alpha: alpha * 0.12)..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_RippleTintPainter old) =>
      old.t != t || old.alpha != alpha || old.from != from || old.to != to;
}
