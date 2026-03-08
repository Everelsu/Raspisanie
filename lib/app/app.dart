import "package:flutter/material.dart";
import "package:flutter_localizations/flutter_localizations.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../core/services/font_service.dart";
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.init());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.onAppResumed();
    }
  }

  void _onThemeChanged() {
    setState(() {
      _themeKey = _controller.prefs.theme;
    });
  }

  @override
  Widget build(BuildContext context) {
    final textScale = _controller.prefs.fontSizeMultiplier;
    return ListenableBuilder(
      listenable: widget.fontService,
      builder: (context, _) {
        return MaterialApp(
          title: "RaspiFlutter",
          debugShowCheckedModeBanner: false,
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
          ),
          builder: (context, child) {
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(textScaler: TextScaler.linear(textScale)),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: HomePage(
            controller: _controller,
            onThemeChanged: _onThemeChanged,
            fontService: widget.fontService,
          ),
        );
      },
    );
  }
}
