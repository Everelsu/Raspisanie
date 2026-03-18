import 'package:flutter/material.dart';

/// Slider with overslide (stretchy) behavior at min/max, inspired by
/// https://www.sinasamaki.com/implementing-overslide-slider-interaction-in-jetpack-compose/
class OverslideSlider extends StatefulWidget {
  const OverslideSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.onChanged,
    this.onChangeEnd,
  });

  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  State<OverslideSlider> createState() => _OverslideSliderState();
}

class _OverslideSliderState extends State<OverslideSlider>
    with SingleTickerProviderStateMixin {
  static const double _maxOverslidePx = 56.0;
  static const double _overslideScaleFactor = 0.18;
  static const double _overslideTranslateFactor = 0.35;

  final GlobalKey _sliderKey = GlobalKey();
  double _overslidePx = 0;
  late AnimationController _overslideController;
  late Animation<double> _overslideAnimation;

  @override
  void initState() {
    super.initState();
    _overslideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _overslideAnimation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _overslideController, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _overslideController.dispose();
    super.dispose();
  }

  double get _normalized => (widget.value - widget.min) / (widget.max - widget.min);
  double get _range => widget.max - widget.min;

  void _onDragStart(DragStartDetails details, double trackWidth, double pad) {
    _overslideController.stop();
  }

  void _onDragUpdate(
    DragUpdateDetails details,
    double trackWidth,
    double pad,
    bool isLtr,
  ) {
    final norm = _normalized;
    final delta = details.delta.dx * (isLtr ? 1 : -1);

    if (norm <= 0 && delta < 0) {
      setState(() {
        _overslidePx = (_overslidePx + delta).clamp(-_maxOverslidePx, 0.0);
      });
      return;
    }
    if (norm >= 1 && delta > 0) {
      setState(() {
        _overslidePx = (_overslidePx + delta).clamp(0.0, _maxOverslidePx);
      });
      return;
    }

    final box = _sliderKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final localX = (box.globalToLocal(details.globalPosition).dx - pad).clamp(0.0, trackWidth);
    final div = widget.divisions;
    final double value;
    if (div == null) {
      value = (widget.min + (localX / trackWidth) * _range).clamp(widget.min, widget.max);
    } else {
      final index = (localX / trackWidth * div).round().clamp(0, div);
      value = widget.min + (index / div) * _range;
    }
    widget.onChanged(value);
  }

  void _onDragEnd(DragEndDetails details, double trackWidth, double pad) {
    if (_overslidePx == 0) {
      widget.onChangeEnd?.call(widget.value);
      return;
    }
    final start = _overslidePx;
    _overslideAnimation = Tween<double>(begin: start, end: 0).animate(
      CurvedAnimation(parent: _overslideController, curve: Curves.elasticOut),
    );
    void onStatus(AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        _overslideController.removeStatusListener(onStatus);
        setState(() => _overslidePx = 0);
        widget.onChangeEnd?.call(widget.value);
      }
    }
    _overslideController.addStatusListener(onStatus);
    _overslideController
      ..value = 0
      ..forward();
  }

  @override
  Widget build(BuildContext context) {
    final theme = SliderTheme.of(context);
    final trackHeight = theme.trackHeight ?? 4.0;
    final thumbRadius = theme.thumbShape is RoundSliderThumbShape
        ? (theme.thumbShape! as RoundSliderThumbShape).enabledThumbRadius
        : 10.0;
    final activeColor = theme.activeTrackColor ?? theme.thumbColor ?? Theme.of(context).colorScheme.primary;
    final inactiveColor = theme.inactiveTrackColor ?? activeColor.withAlpha(102);
    final thumbColor = theme.thumbColor ?? activeColor;
    final isLtr = Directionality.of(context) == TextDirection.ltr;
    final norm = _normalized;

    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth - thumbRadius * 2;
        final pad = thumbRadius;

        return ListenableBuilder(
          listenable: _overslideAnimation,
          builder: (context, _) {
            final overslide = _overslideController.isAnimating
                ? _overslideAnimation.value
                : _overslidePx;

            final transformOrigin = norm < 0.5
                ? Alignment(isLtr ? 1 : -1, 0.5)
                : Alignment(isLtr ? -1 : 1, 0.5);
            final scaleX = 1 - (overslide.abs() / _maxOverslidePx) * _overslideScaleFactor;
            final scaleY = 1 + (overslide.abs() / _maxOverslidePx) * _overslideScaleFactor;
            final translateX = overslide * _overslideTranslateFactor;

            return Transform(
              transform: Matrix4.identity()
                ..translateByDouble(translateX, 0, 0, 1)
                ..scaleByDouble(scaleX, scaleY, 1, 1),
              alignment: transformOrigin,
              child: GestureDetector(
                key: _sliderKey,
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (d) => _onDragStart(d, trackWidth, pad),
                onHorizontalDragUpdate: (d) =>
                    _onDragUpdate(d, trackWidth, pad, isLtr),
                onHorizontalDragEnd: (d) => _onDragEnd(d, trackWidth, pad),
                child: CustomPaint(
                  size: Size(constraints.maxWidth, thumbRadius * 2),
                  painter: _SliderTrackPainter(
                    value: norm,
                    trackHeight: trackHeight,
                    thumbRadius: thumbRadius,
                    activeColor: activeColor,
                    inactiveColor: inactiveColor,
                    thumbColor: thumbColor,
                    isLtr: isLtr,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _SliderTrackPainter extends CustomPainter {
  _SliderTrackPainter({
    required this.value,
    required this.trackHeight,
    required this.thumbRadius,
    required this.activeColor,
    required this.inactiveColor,
    required this.thumbColor,
    required this.isLtr,
  });

  final double value;
  final double trackHeight;
  final double thumbRadius;
  final Color activeColor;
  final Color inactiveColor;
  final Color thumbColor;
  final bool isLtr;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final left = thumbRadius;
    final right = size.width - thumbRadius;
    final trackWidth = right - left;
    final t = isLtr ? value.clamp(0.0, 1.0) : (1 - value).clamp(0.0, 1.0);
    final split = left + trackWidth * t;

    final trackR = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, centerY - trackHeight / 2, trackWidth, trackHeight),
      Radius.circular(trackHeight / 2),
    );
    canvas.drawRRect(trackR, Paint()..color = inactiveColor);
    final activeR = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, centerY - trackHeight / 2, (split - left).clamp(0.0, trackWidth), trackHeight),
      Radius.circular(trackHeight / 2),
    );
    canvas.drawRRect(activeR, Paint()..color = activeColor);

    final thumbCenter = Offset(left + trackWidth * t, centerY);
    canvas.drawCircle(thumbCenter, thumbRadius, Paint()..color = thumbColor);
  }

  @override
  bool shouldRepaint(covariant _SliderTrackPainter old) {
    return old.value != value ||
        old.trackHeight != trackHeight ||
        old.thumbRadius != thumbRadius ||
        old.activeColor != activeColor ||
        old.inactiveColor != inactiveColor ||
        old.thumbColor != thumbColor ||
        old.isLtr != isLtr;
  }
}
