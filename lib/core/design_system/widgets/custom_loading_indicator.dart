import 'dart:async';

import 'package:flutter/material.dart';

import '../colors.dart';

class CustomLoadingIndicator {
  static bool _isGloballyShowing = false;
  static Timer? _safetyTimer;
  static OverlayEntry? _overlayEntry;

  final BuildContext _context;

  CustomLoadingIndicator._create(this._context);

  factory CustomLoadingIndicator.of(BuildContext context) {
    if (!context.mounted) throw StateError('Cannot create CustomLoadingIndicator with unmounted context');
    return CustomLoadingIndicator._create(context);
  }

  void show() {
    if (_isGloballyShowing) return;
    if (!_context.mounted) return;
    try {
      _isGloballyShowing = true;
      _safetyTimer?.cancel();
      _showOverlay();
      _safetyTimer = Timer(const Duration(seconds: 15), () {
        forceClose();
      });
    } catch (_) {
      _isGloballyShowing = false;
    }
  }

  void _showOverlay() {
    try {
      final overlay = Overlay.of(_context);
      _removeOverlay();
      _overlayEntry = OverlayEntry(builder: (context) => const _LoadingIndicator());
      overlay.insert(_overlayEntry!);
    } catch (_) {}
  }

  static void _removeOverlay() {
    try {
      _overlayEntry?.remove();
      _overlayEntry = null;
    } catch (_) {}
  }

  void hide() {
    _cancelSafetyTimer();
    if (_isGloballyShowing) {
      _removeOverlay();
      _isGloballyShowing = false;
    }
  }

  static void _cancelSafetyTimer() {
    _safetyTimer?.cancel();
    _safetyTimer = null;
  }

  bool get isShowing => _isGloballyShowing;

  static void reset() {
    _cancelSafetyTimer();
    _removeOverlay();
    _isGloballyShowing = false;
  }

  static void forceClose() {
    reset();
    WidgetsBinding.instance.addPostFrameCallback((_) => reset());
  }

  static Future<T> during<T>(BuildContext context, Future<T> operation) async {
    try {
      if (!context.mounted) return await operation;
      final indicator = CustomLoadingIndicator.of(context);
      indicator.show();
      try {
        return await operation;
      } finally {
        if (context.mounted) {
          indicator.hide();
        } else {
          forceClose();
        }
      }
    } catch (e) {
      rethrow;
    }
  }
}

class _LoadingIndicator extends StatelessWidget {
  const _LoadingIndicator();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Container(
        color: black.withValues(alpha: 120 / 255),
        child: const Center(
          child: Card(
            elevation: 4,
            shape: CircleBorder(),
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(customIndigoColor),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
