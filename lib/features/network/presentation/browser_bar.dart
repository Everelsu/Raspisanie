import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "../../../core/motion.dart";
import "../../../core/widgets/glass.dart";
import "../../../core/widgets/pressable.dart";

/// Действия браузерного меню (шторка «⋯»).
enum BrowserMenuAction {
  home,
  forward,
  reload,
  fullscreen,
  google,
  openExternal,
  copy,
  paste,
  editStartUrl,
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

  /// Как в Safari: в капсуле только домен, полный адрес — при редактировании.
  String get hostLabel {
    final uri = Uri.tryParse(_currentUrl.isEmpty ? addressLabel : _currentUrl);
    final host = uri?.host ?? "";
    if (host.isEmpty) return addressLabel;
    return host.startsWith("www.") ? host.substring(4) : host;
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
    if (_currentUrl == url) return;
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

/// Браузерный тулбар в стиле Safari: «Назад» (появляется, когда есть
/// куда), адрес-капсула с доменом и прогрессом загрузки по нижней кромке,
/// «⋯» открывает стеклянную шторку действий. Рисуется как `titleWidget`
/// единого AnimatedAppBar на вкладке «Сеть».
class BrowserToolbar extends StatelessWidget {
  const BrowserToolbar({super.key, required this.controller});

  final BrowserBarController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final duration = AppMotion.reduced(context)
        ? Duration.zero
        : const Duration(milliseconds: 260);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final showBack = controller.canGoBack && !controller.editing;
        return Row(
          children: [
            // Кнопка «Назад» выдвигается из-за капсулы, а не возникает.
            AnimatedSize(
              duration: duration,
              curve: AppMotion.sheetCurve,
              child: showBack
                  ? Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _CircleButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        tooltip: "Назад",
                        onTap: controller.onBack,
                      ),
                    )
                  : const SizedBox(height: 40),
            ),
            Expanded(child: _AddressCapsule(controller: controller)),
            const SizedBox(width: 8),
            AnimatedSwitcher(
              duration: duration,
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: ScaleTransition(scale: a, child: child),
              ),
              child: controller.editing
                  ? _TextAction(
                      key: const ValueKey("cancel"),
                      label: "Отмена",
                      color: theme.colorScheme.primary,
                      onTap: controller.stopEditing,
                    )
                  : _CircleButton(
                      key: const ValueKey("more"),
                      icon: Icons.more_horiz_rounded,
                      tooltip: "Ещё",
                      onTap: () => _showMenu(context),
                    ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showMenu(BuildContext context) async {
    HapticFeedback.selectionClick();
    final action = await showGlassSheet<BrowserMenuAction>(
      context,
      builder: (ctx) => _BrowserMenu(controller: controller),
    );
    if (action != null) controller.onMenuAction?.call(action);
  }
}

/// Капсула адреса: домен (полный URL — при редактировании), замок для
/// https, «обновить/стоп» справа и прогресс загрузки по нижней кромке.
class _AddressCapsule extends StatelessWidget {
  const _AddressCapsule({required this.controller});

  final BrowserBarController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final fill = cs.onSurface.withAlpha(16);
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(20),
    );
    if (controller.editing) {
      return SizedBox(
        height: 40,
        child: TextField(
          controller: controller.address,
          focusNode: controller.addressFocus,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.go,
          autocorrect: false,
          enableSuggestions: false,
          style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
          decoration: InputDecoration(
            hintText: "Адрес или поиск",
            isDense: true,
            filled: true,
            fillColor: fill,
            prefixIcon: Icon(Icons.search_rounded,
                size: 18, color: cs.onSurfaceVariant),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 36, minHeight: 36),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide(color: cs.primary, width: 1.2),
            ),
            suffixIcon: IconButton(
              icon: const Icon(Icons.cancel_rounded, size: 18),
              onPressed: controller.address.clear,
              tooltip: "Очистить",
              visualDensity: VisualDensity.compact,
            ),
          ),
          onSubmitted: (_) => controller.onSubmit?.call(),
        ),
      );
    }
    return Pressable(
      scale: 0.97,
      onTap: controller.startEditing,
      child: SizedBox(
        height: 40,
        child: DecoratedBox(
          decoration: ShapeDecoration(color: fill, shape: shape),
          child: ClipRSuperellipse(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                Row(
                  children: [
                    const SizedBox(width: 14),
                    Icon(
                      controller.isHttps
                          ? Icons.lock_rounded
                          : Icons.public_rounded,
                      size: 13,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        controller.hostLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    ValueListenableBuilder<int>(
                      valueListenable: controller.progress,
                      builder: (context, p, _) {
                        final loading = p > 0 && p < 100;
                        return IconButton(
                          tooltip: loading ? "Остановить" : "Обновить",
                          onPressed: controller.onReloadOrStop,
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            loading
                                ? Icons.close_rounded
                                : Icons.refresh_rounded,
                            size: 18,
                          ),
                        );
                      },
                    ),
                  ],
                ),
                // Прогресс — тонкая полоса по нижней кромке капсулы.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 2.5,
                  child: ValueListenableBuilder<int>(
                    valueListenable: controller.progress,
                    builder: (context, p, _) {
                      final loading = p > 0 && p < 100;
                      return AnimatedOpacity(
                        duration: const Duration(milliseconds: 220),
                        opacity: loading ? 1 : 0,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(end: p.clamp(0, 100) / 100),
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOut,
                          builder: (context, v, _) => FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: v,
                            child: ColoredBox(color: cs.primary),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Pressable(
        scale: 0.86,
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: Container(
          width: 40,
          height: 40,
          decoration: ShapeDecoration(
            color: cs.onSurface.withAlpha(16),
            shape: const CircleBorder(),
          ),
          child: Icon(icon, size: 18, color: cs.onSurface),
        ),
      ),
    );
  }
}

class _TextAction extends StatelessWidget {
  const _TextAction({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      scale: 0.92,
      onTap: onTap,
      child: SizedBox(
        height: 40,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Шторка действий браузера: шапка с текущим адресом и сетка плиток.
class _BrowserMenu extends StatelessWidget {
  const _BrowserMenu({required this.controller});

  final BrowserBarController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tiles = <(BrowserMenuAction, IconData, String)>[
      (BrowserMenuAction.home, Icons.home_rounded, "Домой"),
      if (controller.canGoForward)
        (BrowserMenuAction.forward, Icons.arrow_forward_ios_rounded, "Вперёд"),
      (BrowserMenuAction.reload, Icons.refresh_rounded, "Обновить"),
      (
        BrowserMenuAction.fullscreen,
        controller.immersive
            ? Icons.fullscreen_exit_rounded
            : Icons.fullscreen_rounded,
        controller.immersive ? "Свернуть" : "Во весь экран",
      ),
      (BrowserMenuAction.google, Icons.travel_explore_rounded, "Google"),
      (BrowserMenuAction.openExternal, Icons.open_in_new_rounded, "В браузере"),
      (BrowserMenuAction.copy, Icons.content_copy_rounded, "Копировать"),
      (BrowserMenuAction.paste, Icons.content_paste_go_rounded, "Вставить"),
      (BrowserMenuAction.editStartUrl, Icons.push_pin_outlined, "Стартовая"),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: cs.primary.withAlpha(30),
                  shape: RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Icon(
                  controller.isHttps
                      ? Icons.lock_rounded
                      : Icons.public_rounded,
                  size: 18,
                  color: cs.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      controller.hostLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      controller.addressLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.92,
            children: [
              for (final (action, icon, label) in tiles)
                Pressable(
                  scale: 0.9,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.pop(context, action);
                  },
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: cs.onSurface.withAlpha(14),
                      shape: RoundedSuperellipseBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(icon, size: 22, color: cs.primary),
                        const SizedBox(height: 6),
                        Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium
                              ?.copyWith(color: cs.onSurface),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
