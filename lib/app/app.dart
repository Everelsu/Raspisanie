import "package:flutter/material.dart";
import "package:flutter_localizations/flutter_localizations.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../core/services/analytics_service.dart";
import "../core/notifications/notification_service.dart";
import "../core/services/font_service.dart";
import "../core/services/app_icon_service.dart";
import "../core/widgets/splash_intro.dart";
import "../features/home/presentation/home_page.dart";
import "../features/schedule/presentation/schedule_controller.dart";
import "theme.dart";

class RaspiFlutterApp extends StatefulWidget {
  const RaspiFlutterApp({
    super.key,
    required this.prefs,
    required this.fontService,
  });
  final SharedPreferences prefs;
  final FontService fontService;

  @override
  State<RaspiFlutterApp> createState() => _RaspiFlutterAppState();
}

class _RaspiFlutterAppState extends State<RaspiFlutterApp>
    with WidgetsBindingObserver {
  late ScheduleController _controller;
  late String _themeKey;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = ScheduleController(prefs: widget.prefs);
    _themeKey = _controller.prefs.theme;
    _accentColorValue = _controller.prefs.accentColorForTheme(_themeKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.init();
      // Синхронизирует alias иконки и тему системного сплэша (API 33+)
      // со следующим запуском — идемпотентно.
      AppIconService.setIcon(_controller.prefs.effectiveAppIcon);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final inForeground = state == AppLifecycleState.resumed;
    NotificationService.appInForeground = inForeground;
    if (inForeground) {
      _controller.onAppResumed();
    }
  }

  void _onThemeChanged() {
    setState(() {
      _themeKey = _controller.prefs.theme;
      _accentColorValue = _controller.prefs.accentColorForTheme(_themeKey);
    });
  }

  int? _accentColorValue;

  @override
  Widget build(BuildContext context) {
    final textScale = _controller.prefs.fontSizeMultiplier;
    return ListenableBuilder(
      listenable: widget.fontService,
      builder: (context, _) {
        return MaterialApp(
          title: "RaspiFlutter",
          debugShowCheckedModeBanner: false,
          themeAnimationDuration: const Duration(milliseconds: 280),
          themeAnimationCurve: Curves.easeOutCubic,
          navigatorObservers: [
            if (AnalyticsService.instance.observer != null)
              AnalyticsService.instance.observer!,
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale("ru", "RU"),
            Locale("en", "US"),
          ],
          theme: AppThemes.forKey(
            _themeKey,
            textThemeBuilder: widget.fontService.applyTo,
            accentColorOverride: _accentColorValue != null ? Color(_accentColorValue!) : null,
          ),
          builder: (context, child) {
            final media = MediaQuery.of(context);
            // Учитываем системный масштаб шрифта и множитель из настроек.
            final system = media.textScaler.scale(1.0);
            final effective = (system * textScale).clamp(0.78, 1.85);
            return MediaQuery(
              data: media.copyWith(textScaler: TextScaler.linear(effective)),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: SplashIntro(
            // Сплэш стартует в цветах темы, чья иконка стоит в лаунчере,
            // и перетекает в выбранную тему.
            fromColors: AppThemes.colorsFor(_controller.prefs.effectiveAppIcon),
            child: HomePage(
              controller: _controller,
              onThemeChanged: _onThemeChanged,
              fontService: widget.fontService,
            ),
          ),
        );
      },
    );
  }
}
