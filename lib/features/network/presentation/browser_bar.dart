import "package:flutter/material.dart";

/// Пункты меню «⋯» браузерного тулбара.
enum BrowserMenuAction {
  home,
  editStartUrl,
  reload,
  google,
  openExternal,
  copy,
  paste,
}

/// Мост между единым AppBar (HomePage) и WebView-логикой (NetworkPage).
///
/// HomePage создаёт контроллер и рисует по нему [BrowserToolbar] внутри
/// своего единственного AnimatedAppBar — один бар на все вкладки, никаких
/// наложений при свайпе. NetworkPage подписывает обработчики действий и
/// обновляет состояние навигации/адреса/прогресса.
class BrowserBarController extends ChangeNotifier {
  final TextEditingController address = TextEditingController();
  final FocusNode addressFocus = FocusNode();

  /// Прогресс загрузки страницы 0–100. Отдельный notifier: тики onProgress
  /// перерисовывают только полоску и кнопку «обновить/стоп», не весь бар.
  final ValueNotifier<int> progress = ValueNotifier<int>(0);

  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _editing = false;
  bool _immersive = false;
  String _currentUrl = "";

  bool get canGoBack => _canGoBack;
  bool get canGoForward => _canGoForward;
  bool get editing => _editing;
  bool get immersive => _immersive;
  String get currentUrl => _currentUrl;

  String get addressLabel {
    final typed = address.text.trim();
    if (typed.isNotEmpty) return typed;
    return _currentUrl;
  }

  bool get isHttps => Uri.tryParse(addressLabel)?.scheme == "https";

  // Обработчики действий — назначает NetworkPage.
  VoidCallback? onBack;
  VoidCallback? onForward;
  VoidCallback? onSubmit;
  VoidCallback? onToggleImmersive;
  VoidCallback? onReloadOrStop;
  void Function(BrowserMenuAction action)? onMenuAction;

  void setNavState({required bool back, required bool forward}) {
    if (_canGoBack == back && _canGoForward == forward) return;
    _canGoBack = back;
    _canGoForward = forward;
    notifyListeners();
  }

  void setImmersive(bool value) {
    if (_immersive == value) return;
    _immersive = value;
    notifyListeners();
  }

  /// Текущий URL из WebView; синхронизирует адресную строку, если её
  /// сейчас не редактируют.
  void setCurrentUrl(String url) {
    _currentUrl = url;
    if (!addressFocus.hasFocus && address.text != url) {
      address.value = TextEditingValue(
        text: url,
        selection: TextSelection.collapsed(offset: url.length),
      );
    }
    notifyListeners();
  }

  void startEditing() {
    if (_editing) return;
    _editing = true;
    notifyListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      addressFocus.requestFocus();
      address.selection = TextSelection(
        baseOffset: 0,
        extentOffset: address.text.length,
      );
    });
  }

  void stopEditing({bool restoreUrl = true}) {
    if (restoreUrl && _currentUrl.isNotEmpty && address.text != _currentUrl) {
      address.value = TextEditingValue(
        text: _currentUrl,
        selection: TextSelection.collapsed(offset: _currentUrl.length),
      );
    }
    addressFocus.unfocus();
    if (!_editing) return;
    _editing = false;
    notifyListeners();
  }

  @override
  void dispose() {
    address.dispose();
    addressFocus.dispose();
    progress.dispose();
    super.dispose();
  }
}

/// Браузерный тулбар: назад/вперёд, адресная строка (чип ↔ редактор),
/// полноэкранный режим, обновление и меню «⋯». Рисуется как `titleWidget`
/// единого AnimatedAppBar на вкладке «Сеть».
class BrowserToolbar extends StatelessWidget {
  const BrowserToolbar({super.key, required this.controller});

  final BrowserBarController controller;

  Widget _icon({
    required IconData icon,
    required String tooltip,
    VoidCallback? onPressed,
    double size = 20,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: size),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      splashRadius: 18,
    );
  }

  PopupMenuItem<BrowserMenuAction> _menuItem({
    required BrowserMenuAction value,
    required IconData icon,
    required String label,
    required ThemeData theme,
  }) {
    return PopupMenuItem<BrowserMenuAction>(
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

  Widget _leading() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          // SizeTransition с горизонтальной осью прижимает контент к верху
          // (внутренний Align top-aligned) — Center возвращает стрелки на
          // одну линию с адресной строкой и остальными кнопками.
          child: SizeTransition(
            sizeFactor: animation,
            axis: Axis.horizontal,
            child: Center(child: child),
          ),
        );
      },
      child: controller.editing
          ? const SizedBox(key: ValueKey("leading_empty"))
          : Row(
              key: const ValueKey("leading_nav"),
              mainAxisSize: MainAxisSize.min,
              children: [
                _icon(
                  icon: Icons.arrow_back_ios_new_rounded,
                  tooltip: "Назад",
                  onPressed: controller.canGoBack ? controller.onBack : null,
                  size: 18,
                ),
                _icon(
                  icon: Icons.arrow_forward_ios_rounded,
                  tooltip: "Вперёд",
                  onPressed:
                      controller.canGoForward ? controller.onForward : null,
                  size: 18,
                ),
              ],
            ),
    );
  }

  Widget _address(ThemeData theme) {
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
      child: controller.editing
          ? TextField(
              key: const ValueKey("url_editor"),
              controller: controller.address,
              focusNode: controller.addressFocus,
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
                  onPressed: controller.address.clear,
                  tooltip: "Очистить",
                  visualDensity: VisualDensity.compact,
                ),
              ),
              onSubmitted: (_) => controller.onSubmit?.call(),
            )
          : Material(
              key: const ValueKey("url_chip"),
              color: theme.colorScheme.surfaceContainerHighest.withAlpha(90),
              borderRadius: BorderRadius.circular(11),
              child: InkWell(
                onTap: controller.startEditing,
                borderRadius: BorderRadius.circular(11),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        controller.isHttps
                            ? Icons.lock_outline_rounded
                            : Icons.link_rounded,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          controller.addressLabel,
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

  Widget _trailing(ThemeData theme) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 190),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: animation, child: child),
      ),
      child: controller.editing
          ? Row(
              key: const ValueKey("edit_actions"),
              mainAxisSize: MainAxisSize.min,
              children: [
                _icon(
                  icon: Icons.close_rounded,
                  tooltip: "Отмена",
                  onPressed: controller.stopEditing,
                ),
                _icon(
                  icon: Icons.check_rounded,
                  tooltip: "Перейти",
                  onPressed: controller.onSubmit,
                ),
              ],
            )
          : Row(
              key: const ValueKey("normal_actions"),
              mainAxisSize: MainAxisSize.min,
              children: [
                _icon(
                  icon: controller.immersive
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  tooltip: controller.immersive
                      ? "Показать панель"
                      : "Полный экран",
                  onPressed: controller.onToggleImmersive,
                ),
                ValueListenableBuilder<int>(
                  valueListenable: controller.progress,
                  builder: (context, p, _) {
                    final loading = p > 0 && p < 100;
                    return _icon(
                      icon: loading
                          ? Icons.close_rounded
                          : Icons.refresh_rounded,
                      tooltip: loading ? "Остановить загрузку" : "Обновить",
                      onPressed: controller.onReloadOrStop,
                    );
                  },
                ),
                SizedBox(
                  width: 40,
                  height: 40,
                  child: PopupMenuButton<BrowserMenuAction>(
                  tooltip: "Ещё",
                  color: theme.cardTheme.color ?? theme.cardColor,
                  elevation: 14,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  icon: const Icon(Icons.more_vert_rounded, size: 20),
                  padding: EdgeInsets.zero,
                  onSelected: (a) => controller.onMenuAction?.call(a),
                  itemBuilder: (_) => [
                    PopupMenuItem<BrowserMenuAction>(
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
                            controller.addressLabel,
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
                      value: BrowserMenuAction.home,
                      icon: Icons.home_rounded,
                      label: "Стартовая страница",
                      theme: theme,
                    ),
                    _menuItem(
                      value: BrowserMenuAction.editStartUrl,
                      icon: Icons.home_work_outlined,
                      label: "Адрес при открытии вкладки…",
                      theme: theme,
                    ),
                    _menuItem(
                      value: BrowserMenuAction.reload,
                      icon: Icons.refresh_rounded,
                      label: "Обновить страницу",
                      theme: theme,
                    ),
                    _menuItem(
                      value: BrowserMenuAction.google,
                      icon: Icons.travel_explore_rounded,
                      label: "Открыть Google",
                      theme: theme,
                    ),
                    const PopupMenuDivider(height: 8),
                    _menuItem(
                      value: BrowserMenuAction.openExternal,
                      icon: Icons.open_in_new_rounded,
                      label: "Открыть в браузере",
                      theme: theme,
                    ),
                    _menuItem(
                      value: BrowserMenuAction.copy,
                      icon: Icons.content_copy_rounded,
                      label: "Копировать ссылку",
                      theme: theme,
                    ),
                    _menuItem(
                      value: BrowserMenuAction.paste,
                      icon: Icons.content_paste_rounded,
                      label: "Вставить и перейти",
                      theme: theme,
                    ),
                  ],
                  ),
                ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Row(
          children: [
            _leading(),
            Expanded(child: _address(theme)),
            const SizedBox(width: 4),
            _trailing(theme),
          ],
        );
      },
    );
  }
}
