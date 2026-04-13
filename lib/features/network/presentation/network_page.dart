import "dart:async";
import "dart:io";
import "dart:ui" show lerpDouble;

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:url_launcher/url_launcher.dart";
import "package:webview_flutter/webview_flutter.dart";

import "../../../app/theme.dart" show contentBottomPadding;
import "../../../core/widgets/animated_app_bar.dart";
import "../../schedule/presentation/schedule_controller.dart";

const _browserAppBarHeight = 56.0;

enum _BrowserMenuAction {
  login,
  editStartUrl,
  reload,
  google,
  openExternal,
  copy,
  paste,
}

class NetworkPage extends StatefulWidget {
  const NetworkPage({
    super.key,
    required this.scheduleController,
    required this.parentImmersiveNotifier,
    this.isActive = false,
    this.onImmersiveChanged,
  });

  /// Used for сохранения стартового URL (см. [ScheduleController.prefs]).
  /// Имя [scheduleController], чтобы не путать с [WebViewController] в State.
  final ScheduleController scheduleController;

  /// Parent sets `false` when leaving the tab to exit fullscreen.
  final ValueNotifier<bool> parentImmersiveNotifier;

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
  final TextEditingController _addressController = TextEditingController();
  final FocusNode _addressFocusNode = FocusNode();
  final GlobalKey _moreMenuButtonKey = GlobalKey();

  WebViewController? _controller;
  bool _initialLoadDone = false;
  int _progress = 0;
  bool _canGoBack = false;
  bool _canGoForward = false;
  String? _currentUrl;
  bool _urlBarEditing = false;

  /// Hides in-app browser chrome + bottom nav (via parent) for more WebView space.
  bool _immersive = false;

  /// Ошибка загрузки основного фрейма (показываем оверлей с «Повторить»).
  String? _pageLoadError;

  bool get _webViewSupported =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  bool get _isLoading => _progress > 0 && _progress < 100;

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
    _addressFocusNode.addListener(_onAddressFocusChanged);
    _addressController.text = _resolvedStartUri.toString();

    if (_webViewSupported) {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.transparent)
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (progress) {
              if (!mounted) return;
              setState(() => _progress = progress);
            },
            onPageStarted: (url) {
              if (!mounted) return;
              setState(() {
                _progress = 8;
                _currentUrl = url;
                _pageLoadError = null;
              });
              _syncAddressBar(url);
            },
            onUrlChange: (change) {
              final url = change.url;
              if (url == null || !mounted) return;
              setState(() => _currentUrl = url);
              _syncAddressBar(url);
            },
            onPageFinished: (url) async {
              await _refreshNavigationState();
              if (!mounted) return;
              setState(() {
                _progress = 100;
                _currentUrl = url;
              });
              _syncAddressBar(url);
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

  void _triggerInitialLoad() {
    if (_initialLoadDone) return;
    _initialLoadDone = true;
    _controller?.loadRequest(_resolvedStartUri);
  }

  @override
  void didUpdateWidget(NetworkPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive) {
      _triggerInitialLoad();
    }
  }

  @override
  void dispose() {
    _immersiveCtrl.dispose();
    widget.parentImmersiveNotifier.removeListener(_onParentImmersiveNotifier);
    _addressFocusNode.removeListener(_onAddressFocusChanged);
    _addressController.dispose();
    _addressFocusNode.dispose();
    super.dispose();
  }

  void _onParentImmersiveNotifier() {
    if (!mounted) return;
    final parentWants = widget.parentImmersiveNotifier.value;
    if (!parentWants && _immersive) {
      setState(() => _immersive = false);
      _immersiveCtrl.reverse();
    }
  }

  void _setImmersive(bool value) {
    if (_immersive == value) return;
    setState(() => _immersive = value);
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

  void _syncAddressBar(String url) {
    if (_addressFocusNode.hasFocus) return;
    if (_addressController.text == url) return;
    _addressController.value = TextEditingValue(
      text: url,
      selection: TextSelection.collapsed(offset: url.length),
    );
  }

  void _onAddressFocusChanged() {
    if (_addressFocusNode.hasFocus || !_urlBarEditing || !mounted) return;
    setState(() => _urlBarEditing = false);
  }

  Future<void> _refreshNavigationState() async {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final canGoBack = await controller.canGoBack();
    final canGoForward = await controller.canGoForward();
    if (!mounted) return;
    setState(() {
      _canGoBack = canGoBack;
      _canGoForward = canGoForward;
    });
  }

  Future<void> _goBack() async {
    final controller = _controller;
    if (controller == null || !_canGoBack) return;
    await controller.goBack();
    await _refreshNavigationState();
  }

  Future<void> _goForward() async {
    final controller = _controller;
    if (controller == null || !_canGoForward) return;
    await controller.goForward();
    await _refreshNavigationState();
  }

  Future<void> _navigateToInput() async {
    final controller = _controller;
    if (controller == null) return;

    final input = _addressController.text.trim();
    final uri = _normalizeInputToUri(input);
    if (uri == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text("Введите корректную ссылку")),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _progress = 12;
      _urlBarEditing = false;
    });
    await controller.loadRequest(uri);
  }

  Future<void> _openGoogleInWebView() async {
    final controller = _controller;
    if (controller == null) {
      await _openGoogleExternally();
      return;
    }

    FocusScope.of(context).unfocus();
    _addressController.text = NetworkPage.googleUri.toString();
    if (mounted) {
      setState(() {
        _progress = 12;
        _urlBarEditing = false;
      });
    }
    await controller.loadRequest(NetworkPage.googleUri);
  }

  String _currentAddressLabel() {
    final typed = _addressController.text.trim();
    if (typed.isNotEmpty) return typed;
    final current = (_currentUrl ?? "").trim();
    if (current.isNotEmpty) return current;
    return _resolvedStartUri.toString();
  }

  void _openUrlBarEditor() {
    final sync = _currentUrl;
    if (sync != null) _syncAddressBar(sync);

    setState(() => _urlBarEditing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _addressFocusNode.requestFocus();
      _addressController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _addressController.text.length,
      );
    });
  }

  void _cancelUrlBarEditor() {
    final sync = _currentUrl;
    if (sync != null) _syncAddressBar(sync);
    _addressFocusNode.unfocus();
    setState(() => _urlBarEditing = false);
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
    setState(() => _progress = 12);
    await c.loadRequest(_resolvedStartUri);
    if (!mounted) return;
    _addressController.text = _resolvedStartUri.toString();
  }

  PopupMenuItem<_BrowserMenuAction> _menuItem({
    required _BrowserMenuAction value,
    required IconData icon,
    required String label,
    required ThemeData theme,
  }) {
    return PopupMenuItem<_BrowserMenuAction>(
      value: value,
      height: 44,
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.onSurface),
          const SizedBox(width: 10),
          Text(label, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }

  Future<void> _showBrowserMoreMenu() async {
    final controller = _controller;
    if (controller == null) return;

    final buttonContext = _moreMenuButtonKey.currentContext;
    if (buttonContext == null) return;

    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final button = buttonContext.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    final theme = Theme.of(context);
    final action = await showMenu<_BrowserMenuAction>(
      context: context,
      color: theme.cardTheme.color ?? theme.cardColor,
      elevation: 14,
      position: position,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      items: [
        PopupMenuItem<_BrowserMenuAction>(
          enabled: false,
          height: 56,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "Текущая ссылка",
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _currentAddressLabel(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
        _menuItem(
          value: _BrowserMenuAction.login,
          icon: Icons.home_rounded,
          label: "Стартовая страница",
          theme: theme,
        ),
        _menuItem(
          value: _BrowserMenuAction.editStartUrl,
          icon: Icons.home_work_outlined,
          label: "Адрес при открытии вкладки…",
          theme: theme,
        ),
        _menuItem(
          value: _BrowserMenuAction.reload,
          icon: Icons.refresh_rounded,
          label: "Обновить страницу",
          theme: theme,
        ),
        _menuItem(
          value: _BrowserMenuAction.google,
          icon: Icons.travel_explore_rounded,
          label: "Открыть Google",
          theme: theme,
        ),
        const PopupMenuDivider(height: 8),
        _menuItem(
          value: _BrowserMenuAction.openExternal,
          icon: Icons.open_in_new_rounded,
          label: "Открыть в браузере",
          theme: theme,
        ),
        _menuItem(
          value: _BrowserMenuAction.copy,
          icon: Icons.content_copy_rounded,
          label: "Копировать ссылку",
          theme: theme,
        ),
        _menuItem(
          value: _BrowserMenuAction.paste,
          icon: Icons.content_paste_rounded,
          label: "Вставить и перейти",
          theme: theme,
        ),
      ],
    );

    if (!mounted || action == null) return;

    switch (action) {
      case _BrowserMenuAction.login:
        unawaited(controller.loadRequest(_resolvedStartUri));
        break;
      case _BrowserMenuAction.editStartUrl:
        await _showEditStartUrlDialog();
        break;
      case _BrowserMenuAction.reload:
        await _reloadPage();
        break;
      case _BrowserMenuAction.google:
        unawaited(_openGoogleInWebView());
        break;
      case _BrowserMenuAction.openExternal:
        unawaited(_openExternally());
        break;
      case _BrowserMenuAction.copy:
        await Clipboard.setData(
          ClipboardData(text: _addressController.text.trim()),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Ссылка скопирована")),
        );
        break;
      case _BrowserMenuAction.paste:
        final data = await Clipboard.getData("text/plain");
        final pasted = (data?.text ?? "").trim();
        if (pasted.isEmpty) return;
        _addressController.text = pasted;
        await _navigateToInput();
        break;
    }
  }

  Widget _browserToolbarIcon({
    Key? buttonKey,
    required IconData icon,
    required String tooltip,
    VoidCallback? onPressed,
    double size = 20,
  }) {
    return IconButton(
      key: buttonKey,
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: size),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      splashRadius: 18,
    );
  }

  Widget _buildLeadingNavControls() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SizeTransition(
            sizeFactor: animation,
            axis: Axis.horizontal,
            child: child,
          ),
        );
      },
      child: _urlBarEditing
          ? const SizedBox(key: ValueKey("leading_empty"))
          : Row(
              key: const ValueKey("leading_nav"),
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _browserToolbarIcon(
                    icon: Icons.arrow_back_ios_new_rounded,
                    tooltip: "Назад",
                    onPressed: _canGoBack ? () => unawaited(_goBack()) : null,
                    size: 18,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _browserToolbarIcon(
                    icon: Icons.arrow_forward_ios_rounded,
                    tooltip: "Вперёд",
                    onPressed:
                        _canGoForward ? () => unawaited(_goForward()) : null,
                    size: 18,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildAddressSwitcher(ThemeData theme, {required bool isHttps}) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 230),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final slide = Tween<Offset>(
          begin: const Offset(0.0, 0.08),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: slide, child: child),
        );
      },
      child: _urlBarEditing
          ? TextField(
              key: const ValueKey("url_editor"),
              controller: _addressController,
              focusNode: _addressFocusNode,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              autocorrect: false,
              enableSuggestions: false,
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13.5),
              decoration: InputDecoration(
                hintText: "https://...",
                isDense: true,
                filled: true,
                fillColor:
                    theme.colorScheme.surfaceContainerHighest.withAlpha(130),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                  borderSide: BorderSide(
                    color: theme.colorScheme.outline.withAlpha(100),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                  borderSide: BorderSide(
                    color: theme.colorScheme.outline.withAlpha(100),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                  borderSide: BorderSide(
                    color: theme.colorScheme.primary,
                    width: 1.4,
                  ),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  onPressed: _addressController.clear,
                  tooltip: "Очистить",
                  visualDensity: VisualDensity.compact,
                ),
              ),
              onSubmitted: (_) => unawaited(_navigateToInput()),
            )
          : Material(
              key: const ValueKey("url_chip"),
              color: theme.colorScheme.surfaceContainerHighest.withAlpha(90),
              borderRadius: BorderRadius.circular(11),
              child: InkWell(
                onTap: _openUrlBarEditor,
                borderRadius: BorderRadius.circular(11),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        isHttps
                            ? Icons.lock_outline_rounded
                            : Icons.link_rounded,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _currentAddressLabel(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildTrailingActions(WebViewController controller) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 190),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: animation, child: child),
      ),
      child: _urlBarEditing
          ? Row(
              key: const ValueKey("edit_actions"),
              mainAxisSize: MainAxisSize.min,
              children: [
                _browserToolbarIcon(
                  icon: Icons.close_rounded,
                  tooltip: "Отмена",
                  onPressed: _cancelUrlBarEditor,
                ),
                _browserToolbarIcon(
                  icon: Icons.check_rounded,
                  tooltip: "Перейти",
                  onPressed: () => unawaited(_navigateToInput()),
                ),
              ],
            )
          : Row(
              key: const ValueKey("normal_actions"),
              mainAxisSize: MainAxisSize.min,
              children: [
                _browserToolbarIcon(
                  icon: _immersive
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  tooltip: _immersive ? "Показать панель" : "Полный экран",
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    _setImmersive(!_immersive);
                  },
                ),
                _browserToolbarIcon(
                  icon:
                      _isLoading ? Icons.close_rounded : Icons.refresh_rounded,
                  tooltip: _isLoading ? "Остановить загрузку" : "Обновить",
                  onPressed: () async {
                    if (_isLoading) {
                      await controller.runJavaScript("window.stop();");
                      if (!mounted) return;
                      setState(() => _progress = 100);
                      return;
                    }
                    setState(() => _progress = 12);
                    await controller.reload();
                  },
                ),
                _browserToolbarIcon(
                  buttonKey: _moreMenuButtonKey,
                  icon: Icons.more_vert_rounded,
                  tooltip: "Ещё",
                  onPressed: () => unawaited(_showBrowserMoreMenu()),
                ),
              ],
            ),
    );
  }

  AnimatedAppBar _buildWebAppBar(
    WebViewController controller, {
    required bool isHttps,
  }) {
    final theme = Theme.of(context);
    return AnimatedAppBar(
      title: "",
      subtitle: null,
      tabIndex: 2,
      height: _browserAppBarHeight,
      blurSigma: 0,
      bottomRadius: 16,
      actions: const [],
      titleWidget: Row(
        children: [
          _buildLeadingNavControls(),
          Expanded(
            child: _buildAddressSwitcher(theme, isHttps: isHttps),
          ),
          const SizedBox(width: 4),
          _buildTrailingActions(controller),
        ],
      ),
    );
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
    final typed = _normalizeInputToUri(_addressController.text.trim());
    final current = Uri.tryParse(_currentUrl ?? "");
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
      return Scaffold(
        backgroundColor: theme.colorScheme.surface,
        extendBodyBehindAppBar: true,
        appBar: const AnimatedAppBar(
          title: "Сеть",
          subtitle: null,
          tabIndex: 2,
          height: _browserAppBarHeight,
          blurSigma: 0,
          bottomRadius: 16,
        ),
        body: _UnsupportedBrowserView(
          topPadding: _contentTopInset(context),
          addressController: _addressController,
          onSubmit: _openExternally,
          onOpenGoogle: _openGoogleExternally,
        ),
      );
    }

    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();

    final progressValue =
        _progress >= 100 ? null : _progress.clamp(0, 100) / 100.0;
    final barUrl =
        Uri.tryParse((_currentUrl ?? _addressController.text).trim());
    final isHttps = barUrl?.scheme == "https";

    final curve = Curves.easeOutCubic;
    final bottomSafe = MediaQuery.viewPaddingOf(context).bottom;

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
        extendBodyBehindAppBar: true,
        appBar: null,
        body: AnimatedBuilder(
          animation: _immersiveCtrl,
          builder: (context, _) {
            final t = curve.transform(_immersiveCtrl.value.clamp(0.0, 1.0));
            final topSpacer = _topSpacer(context, t);
            final bottomPad = _webviewBottomPadding(t);
            final barHiddenFactor = t;

            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Column(
                  children: [
                    SizedBox(height: topSpacer),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 180),
                        opacity: progressValue == null ? 0 : 1,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: LinearProgressIndicator(
                            value: progressValue,
                            minHeight: 3,
                            backgroundColor:
                                theme.colorScheme.outlineVariant.withAlpha(60),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(12, 10, 12, bottomPad),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: ColoredBox(
                            color: theme.cardTheme.color ?? theme.cardColor,
                            child: WebViewWidget(controller: controller),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                // AnimatedAppBar already includes status bar + toolbar (see animated_app_bar.dart).
                // Do not wrap in a fixed 56px box — that clipped the bar.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: ClipRect(
                    child: Align(
                      alignment: Alignment.topCenter,
                      heightFactor: (1 - barHiddenFactor).clamp(0.0, 1.0),
                      child: _buildWebAppBar(controller, isHttps: isHttps),
                    ),
                  ),
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
      padding: EdgeInsets.fromLTRB(20, topPadding, 20, contentBottomPadding(context)),
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
