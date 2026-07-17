import "dart:async";
import "dart:io";
import "dart:ui" show lerpDouble;

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:url_launcher/url_launcher.dart";
import "package:webview_flutter/webview_flutter.dart";

import "../../../app/theme.dart" show contentBottomPadding;
import "../../schedule/presentation/schedule_controller.dart";
import "browser_bar.dart";

/// Высота браузерной части единого AppBar (совпадает с kToolbarHeight).
const _browserAppBarHeight = 56.0;

/// Вкладка «Сеть»: WebView без собственного AppBar. Браузерный тулбар
/// рисуется единым AppBar в HomePage через [BrowserBarController] —
/// здесь только контент, обработчики действий и полноэкранный режим.
class NetworkPage extends StatefulWidget {
  const NetworkPage({
    super.key,
    required this.scheduleController,
    required this.parentImmersiveNotifier,
    required this.barController,
    this.isActive = false,
    this.onImmersiveChanged,
  });

  /// Used for сохранения стартового URL (см. [ScheduleController.prefs]).
  /// Имя [scheduleController], чтобы не путать с [WebViewController] в State.
  final ScheduleController scheduleController;

  /// Parent sets `false` when leaving the tab to exit fullscreen.
  final ValueNotifier<bool> parentImmersiveNotifier;

  /// Общий контроллер браузерного тулбара (владеет HomePage).
  final BrowserBarController barController;

  /// True while this tab is the active page. First time it becomes true,
  /// the WebView fires its initial [loadRequest].
  final bool isActive;

  final ValueChanged<bool>? onImmersiveChanged;

  static final Uri initialUri = Uri.parse(
    "https://poo.zabedu.ru/security/#/login",
  );
  static final Uri googleUri = Uri.parse("https://www.google.com");

  @override
  State<NetworkPage> createState() => _NetworkPageState();
}

class _NetworkPageState extends State<NetworkPage>
    with SingleTickerProviderStateMixin {
  /// 0 = normal chrome, 1 = fullscreen WebView.
  late final AnimationController _immersiveCtrl;

  WebViewController? _controller;
  bool _initialLoadDone = false;

  /// Hides browser chrome + bottom nav (via parent) for more WebView space.
  bool _immersive = false;

  /// Ошибка загрузки основного фрейма (показываем оверлей с «Повторить»).
  String? _pageLoadError;

  BrowserBarController get _bar => widget.barController;

  bool get _webViewSupported =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  /// Built-in URL if custom start URL is empty or invalid.
  Uri get _resolvedStartUri {
    final custom = widget.scheduleController.prefs.networkStartUrl.trim();
    if (custom.isEmpty) return NetworkPage.initialUri;
    final u = _normalizeInputToUri(custom);
    return u ?? NetworkPage.initialUri;
  }

  @override
  void initState() {
    super.initState();
    _immersiveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      reverseDuration: const Duration(milliseconds: 320),
    );
    widget.parentImmersiveNotifier.addListener(_onParentImmersiveNotifier);
    _wireBarController();

    if (_webViewSupported) {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.transparent)
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (progress) {
              if (!mounted) return;
              _bar.progress.value = progress;
            },
            onPageStarted: (url) {
              if (!mounted) return;
              _bar.progress.value = 8;
              _bar.setCurrentUrl(url);
              setState(() => _pageLoadError = null);
            },
            onUrlChange: (change) {
              final url = change.url;
              if (url == null || !mounted) return;
              _bar.setCurrentUrl(url);
            },
            onPageFinished: (url) async {
              await _refreshNavigationState();
              if (!mounted) return;
              _bar.progress.value = 100;
              _bar.setCurrentUrl(url);
            },
            onWebResourceError: (WebResourceError error) {
              if (!mounted) return;
              if (error.isForMainFrame != true) return;
              final msg = _describeWebResourceError(error);
              setState(() => _pageLoadError = msg);
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                SnackBar(
                  content: Text(msg),
                  action: SnackBarAction(
                    label: "Повторить",
                    onPressed: _retryPageLoad,
                  ),
                ),
              );
            },
          ),
        );
      if (widget.isActive) _triggerInitialLoad();
    }
  }

  /// Подписывает обработчики действий тулбара на этот State.
  void _wireBarController() {
    final bar = _bar;
    if (bar.address.text.trim().isEmpty) {
      bar.address.text = _resolvedStartUri.toString();
    }
    bar.onBack = () => unawaited(_goBack());
    bar.onForward = () => unawaited(_goForward());
    bar.onSubmit = () => unawaited(_navigateToInput());
    bar.onToggleImmersive = () {
      HapticFeedback.selectionClick();
      _setImmersive(!_immersive);
    };
    bar.onReloadOrStop = () => unawaited(_reloadOrStop());
    bar.onMenuAction = (a) => unawaited(_handleMenuAction(a));
  }

  void _triggerInitialLoad() {
    if (_initialLoadDone) return;
    _initialLoadDone = true;
    _controller?.loadRequest(_resolvedStartUri);
  }

  @override
  void didUpdateWidget(NetworkPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.barController != widget.barController) {
      _wireBarController();
    }
    if (!oldWidget.isActive && widget.isActive) {
      _triggerInitialLoad();
    }
  }

  @override
  void dispose() {
    _immersiveCtrl.dispose();
    widget.parentImmersiveNotifier.removeListener(_onParentImmersiveNotifier);
    // Контроллер бара живёт в HomePage — снимаем только свои обработчики.
    _bar
      ..onBack = null
      ..onForward = null
      ..onSubmit = null
      ..onToggleImmersive = null
      ..onReloadOrStop = null
      ..onMenuAction = null;
    super.dispose();
  }

  void _onParentImmersiveNotifier() {
    if (!mounted) return;
    final parentWants = widget.parentImmersiveNotifier.value;
    if (!parentWants && _immersive) {
      setState(() => _immersive = false);
      _bar.setImmersive(false);
      _immersiveCtrl.reverse();
    }
  }

  void _setImmersive(bool value) {
    if (_immersive == value) return;
    setState(() => _immersive = value);
    _bar.setImmersive(value);
    if (value) {
      _immersiveCtrl.forward();
    } else {
      _immersiveCtrl.reverse();
    }
    widget.onImmersiveChanged?.call(value);
  }

  double _topSpacer(BuildContext context, double t) {
    final top = MediaQuery.viewPaddingOf(context).top;
    return top + (1 - t) * (_browserAppBarHeight + 10);
  }

  double _webviewBottomPadding(double t) =>
      lerpDouble(104, 12, t.clamp(0.0, 1.0))!;

  double _contentTopInset(BuildContext context) {
    return MediaQuery.viewPaddingOf(context).top + _browserAppBarHeight + 10;
  }

  String _describeWebResourceError(WebResourceError e) {
    final d = e.description.trim();
    if (d.isNotEmpty) {
      return d.length > 180 ? "${d.substring(0, 177)}…" : d;
    }
    return "Не удалось загрузить страницу (код ${e.errorCode})";
  }

  void _retryPageLoad() {
    if (!mounted) return;
    setState(() => _pageLoadError = null);
    final c = _controller;
    if (c == null) return;
    unawaited(c.reload());
  }

  Future<void> _reloadPage() async {
    final c = _controller;
    if (c == null) return;
    if (!mounted) return;
    setState(() => _pageLoadError = null);
    await c.reload();
  }

  Future<void> _reloadOrStop() async {
    final c = _controller;
    if (c == null) return;
    final p = _bar.progress;
    if (p.value > 0 && p.value < 100) {
      await c.runJavaScript("window.stop();");
      p.value = 100;
      return;
    }
    p.value = 12;
    await _reloadPage();
  }

  Future<void> _refreshNavigationState() async {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final canGoBack = await controller.canGoBack();
    final canGoForward = await controller.canGoForward();
    if (!mounted) return;
    _bar.setNavState(back: canGoBack, forward: canGoForward);
  }

  Future<void> _goBack() async {
    final controller = _controller;
    if (controller == null || !_bar.canGoBack) return;
    await controller.goBack();
    await _refreshNavigationState();
  }

  Future<void> _goForward() async {
    final controller = _controller;
    if (controller == null || !_bar.canGoForward) return;
    await controller.goForward();
    await _refreshNavigationState();
  }

  Future<void> _navigateToInput() async {
    final controller = _controller;
    if (controller == null) return;

    final input = _bar.address.text.trim();
    final uri = _normalizeInputToUri(input);
    if (uri == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text("Введите корректную ссылку")),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    _bar.progress.value = 12;
    _bar.stopEditing(restoreUrl: false);
    await controller.loadRequest(uri);
  }

  Future<void> _openGoogleInWebView() async {
    final controller = _controller;
    if (controller == null) {
      await _openGoogleExternally();
      return;
    }

    FocusScope.of(context).unfocus();
    _bar.address.text = NetworkPage.googleUri.toString();
    _bar.progress.value = 12;
    _bar.stopEditing(restoreUrl: false);
    await controller.loadRequest(NetworkPage.googleUri);
  }

  Future<void> _handleMenuAction(BrowserMenuAction action) async {
    final controller = _controller;
    if (controller == null) return;

    switch (action) {
      case BrowserMenuAction.home:
        _bar.progress.value = 12;
        unawaited(controller.loadRequest(_resolvedStartUri));
        break;
      case BrowserMenuAction.editStartUrl:
        await _showEditStartUrlDialog();
        break;
      case BrowserMenuAction.reload:
        await _reloadPage();
        break;
      case BrowserMenuAction.google:
        unawaited(_openGoogleInWebView());
        break;
      case BrowserMenuAction.openExternal:
        unawaited(_openExternally());
        break;
      case BrowserMenuAction.copy:
        await Clipboard.setData(
          ClipboardData(text: _bar.address.text.trim()),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Ссылка скопирована")),
        );
        break;
      case BrowserMenuAction.paste:
        final data = await Clipboard.getData("text/plain");
        final pasted = (data?.text ?? "").trim();
        if (pasted.isEmpty) return;
        _bar.address.text = pasted;
        await _navigateToInput();
        break;
    }
  }

  Future<void> _showEditStartUrlDialog() async {
    final theme = Theme.of(context);
    final saved = widget.scheduleController.prefs.networkStartUrl.trim();
    final textCtrl = TextEditingController(
      text: saved.isEmpty ? NetworkPage.initialUri.toString() : saved,
    );
    bool? apply;
    try {
      apply = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Адрес при открытии вкладки «Сеть»"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "Эта страница открывается при первом заходе на вкладку и по кнопке «Домой» в меню (⋯). "
                  "Можно вставить свою форму входа или другой сайт (https).",
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: textCtrl,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: "URL",
                    hintText: "https://example.com/…",
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("Отмена"),
            ),
            TextButton(
              onPressed: () {
                widget.scheduleController.prefs.networkStartUrl = "";
                Navigator.pop(ctx, true);
              },
              child: const Text("Сбросить"),
            ),
            FilledButton(
              onPressed: () {
                final uri = _normalizeInputToUri(textCtrl.text.trim());
                if (uri == null) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text("Некорректная ссылка")),
                  );
                  return;
                }
                widget.scheduleController.prefs.networkStartUrl =
                    uri.toString();
                Navigator.pop(ctx, true);
              },
              child: const Text("Сохранить"),
            ),
          ],
        ),
      );
    } finally {
      // Нельзя dispose сразу после pop: маршрут диалога ещё анимирует закрытие,
      // TextField/AnimatedSwitcher дергают controller — «used after being disposed».
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          textCtrl.dispose();
        });
      });
    }
    if (apply != true || !mounted) return;
    final c = _controller;
    if (c == null) return;
    _bar.progress.value = 12;
    await c.loadRequest(_resolvedStartUri);
    if (!mounted) return;
    _bar.address.text = _resolvedStartUri.toString();
  }

  Uri? _normalizeInputToUri(String input) {
    if (input.isEmpty) return null;
    final prepared = input.contains("://") ? input : "https://$input";
    final uri = Uri.tryParse(prepared);
    if (uri == null || uri.host.isEmpty) return null;
    if (!(uri.scheme == "http" || uri.scheme == "https")) return null;
    return uri;
  }

  Future<void> _openExternally() async {
    final typed = _normalizeInputToUri(_bar.address.text.trim());
    final current = Uri.tryParse(_bar.currentUrl);
    final uri = typed ?? current ?? _resolvedStartUri;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openGoogleExternally() async {
    await launchUrl(
      NetworkPage.googleUri,
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!_webViewSupported) {
      return _UnsupportedBrowserView(
        topPadding: _contentTopInset(context),
        addressController: _bar.address,
        onSubmit: _openExternally,
        onOpenGoogle: _openGoogleExternally,
      );
    }

    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();

    final curve = Curves.easeOutCubic;
    final bottomSafe = MediaQuery.viewPaddingOf(context).bottom;

    // Полоска прогресса на своём ValueListenableBuilder — тики onProgress
    // не перестраивают остальной экран. Когда не грузимся, индикатор
    // снимается из дерева (indeterminate-анимация не крутится зря).
    final progressBar = ValueListenableBuilder<int>(
      valueListenable: _bar.progress,
      builder: (context, p, _) {
        final loading = p > 0 && p < 100;
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: loading ? 1 : 0,
          child: SizedBox(
            height: 3,
            child: loading
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: p.clamp(0, 100) / 100.0,
                      minHeight: 3,
                      backgroundColor:
                          theme.colorScheme.outlineVariant.withAlpha(60),
                    ),
                  )
                : null,
          ),
        );
      },
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_immersive) {
          _setImmersive(false);
          return;
        }
        final c = _controller;
        if (c != null && await c.canGoBack()) {
          await _goBack();
          return;
        }
        if (context.mounted) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: AnimatedBuilder(
          animation: _immersiveCtrl,
          // WebView — child, а не часть builder: platform view не
          // пересоздаётся на каждый кадр анимации перехода в fullscreen.
          child: RepaintBoundary(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: ColoredBox(
                color: theme.cardTheme.color ?? theme.cardColor,
                child: WebViewWidget(controller: controller),
              ),
            ),
          ),
          builder: (context, webView) {
            final t = curve.transform(_immersiveCtrl.value.clamp(0.0, 1.0));
            final topSpacer = _topSpacer(context, t);
            final bottomPad = _webviewBottomPadding(t);

            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Column(
                  children: [
                    SizedBox(height: topSpacer),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: progressBar,
                    ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(12, 10, 12, bottomPad),
                        child: webView!,
                      ),
                    ),
                  ],
                ),
                if (_pageLoadError != null)
                  Positioned.fill(
                    child: Material(
                      color: theme.colorScheme.surface.withAlpha(242),
                      child: SafeArea(
                        child: Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.cloud_off_outlined,
                                  size: 52,
                                  color: theme.colorScheme.error,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  _pageLoadError!,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyLarge,
                                ),
                                const SizedBox(height: 20),
                                FilledButton.icon(
                                  onPressed: _retryPageLoad,
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text("Повторить"),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  right: 12,
                  bottom: 12 + bottomSafe,
                  child: FadeTransition(
                    opacity: CurvedAnimation(
                      parent: _immersiveCtrl,
                      curve: const Interval(0.25, 0.85, curve: Curves.easeOut),
                    ),
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.86, end: 1.0).animate(
                        CurvedAnimation(
                          parent: _immersiveCtrl,
                          curve: const Interval(0.2, 0.95,
                              curve: Curves.easeOutBack),
                        ),
                      ),
                      child: IgnorePointer(
                        ignoring: t < 0.15,
                        child: Material(
                          elevation: 8,
                          shadowColor: Colors.black54,
                          shape: const CircleBorder(),
                          color: theme.colorScheme.surfaceContainerHigh,
                          child: IconButton(
                            tooltip: "Показать панель",
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              _setImmersive(false);
                            },
                            icon: const Icon(Icons.fullscreen_exit_rounded),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _UnsupportedBrowserView extends StatelessWidget {
  const _UnsupportedBrowserView({
    required this.topPadding,
    required this.addressController,
    required this.onSubmit,
    required this.onOpenGoogle,
  });

  final double topPadding;
  final TextEditingController addressController;
  final Future<void> Function() onSubmit;
  final Future<void> Function() onOpenGoogle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding:
          EdgeInsets.fromLTRB(20, topPadding, 20, contentBottomPadding(context)),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.cardTheme.color ?? theme.cardColor,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: theme.colorScheme.primary.withAlpha(28),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Встроенный браузер", style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                  "На этой платформе WebView не поддерживается. "
                  "Откроем ссылку в системном браузере.",
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: addressController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    hintText: "https://poo.zabedu.ru/security/#/login",
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: onSubmit,
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text("Открыть в браузере"),
                    ),
                    OutlinedButton.icon(
                      onPressed: onOpenGoogle,
                      icon: const Icon(Icons.travel_explore_rounded),
                      label: const Text("Открыть Google"),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
