import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class KeyboardDismissWrapper extends StatelessWidget {
  const KeyboardDismissWrapper({
    super.key,
    required this.child,
    this.enableDismissOnTap = true,
  });

  final Widget child;
  final bool enableDismissOnTap;

  @override
  Widget build(BuildContext context) {
    if (!enableDismissOnTap) return child;
    return GestureDetector(
      onTap: () => _dismissKeyboard(context),
      behavior: HitTestBehavior.translucent,
      child: child,
    );
  }

  void _dismissKeyboard(BuildContext context) {
    FocusScope.of(context).unfocus();
    if (Platform.isIOS) {
      try {
        SystemChannels.textInput.invokeMethod('TextInput.hide');
      } catch (_) {}
    }
  }
}
