import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import '../../app/theme.dart' show AppThemeColors;
import 'refresh_logo_mark.dart';

/// Анимированный сплэш поверх приложения.
///
/// Холодный старт: стартует в цветах темы, соответствующей иконке лаунчера
/// ([fromColors]), плавно перетекает в выбранную тему, затем камера влетает
/// внутрь левого кольца знака и оверлей растворяется.
///
/// Возврат из фона: если цвет иконки не совпадает с темой, короткий реплей —
/// знак на фоне цвета иконки перетекает в тему и растворяется (без зума).
/// Убирает диссонанс «нажал красную иконку — открылось фиолетовое».
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

  late final AnimationController _tint = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
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
    // Первый кадр оверлея идентичен нативному сплэшу — только после него
    // убираем нативный, без анимации системы: знак не «переезжает».
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
    });
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    await _tint.forward();
    if (!mounted) return;
    // Монтируем приложение за непрозрачным оверлеем: его первая сборка
    // (самая дорогая) происходит, пока на экране ничего не анимируется.
    setState(() => _showChild = true);
    await Future<void>.delayed(const Duration(milliseconds: 180));
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
    _tint.value = 0;
    _fadeOut.value = 0;
    // Реплей короче холодного старта — вход должен ощущаться быстрым.
    await _tint.animateTo(1.0, duration: const Duration(milliseconds: 450));
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
    _tint.dispose();
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
              animation: Listenable.merge([_tint, _zoom, _fadeOut]),
              builder: (context, _) {
                final tintT = Curves.easeInOutCubic.transform(_tint.value);
                final bg = Color.lerp(bgFrom, bgTo, tintT)!;
                final fg = Color.lerp(fgFrom, fgTo, tintT)!;

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

                // Камера влетает внутрь левого кольца знака.
                final ringShift = 147.5 * (_logoWidth / 615);
                final scale = 1.0 + zoomT * 26.0;

                return IgnorePointer(
                  child: Opacity(
                    opacity: opacity.clamp(0.0, 1.0),
                    child: Container(
                      color: bg,
                      alignment: Alignment.center,
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
