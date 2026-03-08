import 'package:flutter/material.dart';

import 'keyboard_dismiss_wrapper.dart';

class PopScopeScaffold extends StatelessWidget {
  const PopScopeScaffold({
    super.key,
    this.bottomNavigationBar,
    this.body,
    this.floatingActionButton,
    this.appBar,
    this.backgroundColor,
    this.resizeToAvoidBottomInset = true,
    this.onPopInvokedWithResult,
    this.enableKeyboardDismiss = true,
    this.primary = true,
  });

  final Widget? bottomNavigationBar;
  final Widget? body;
  final Widget? floatingActionButton;
  final PreferredSizeWidget? appBar;
  final Color? backgroundColor;
  final bool resizeToAvoidBottomInset;
  final void Function(bool, Object?)? onPopInvokedWithResult;
  final bool enableKeyboardDismiss;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wrappedBody = enableKeyboardDismiss && body != null
        ? KeyboardDismissWrapper(child: body!)
        : body;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: onPopInvokedWithResult ?? (_, __) {},
      child: Scaffold(
        primary: primary,
        bottomNavigationBar: bottomNavigationBar,
        body: wrappedBody,
        appBar: appBar,
        floatingActionButton: floatingActionButton,
        backgroundColor: backgroundColor ?? theme.scaffoldBackgroundColor,
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      ),
    );
  }
}
