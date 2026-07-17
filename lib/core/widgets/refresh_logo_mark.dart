import 'package:flutter/material.dart';

/// The app's Union logo mark, rendered as a vector path so it can be sized,
/// tinted with the current theme accent, and spun as a loading indicator.
class RefreshLogoMark extends StatefulWidget {
  const RefreshLogoMark({
    super.key,
    required this.color,
    this.size = 22,
    this.spinning = false,
  });

  final Color color;
  final double size;
  final bool spinning;

  @override
  State<RefreshLogoMark> createState() => _RefreshLogoMarkState();
}

class _RefreshLogoMarkState extends State<RefreshLogoMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    if (widget.spinning) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant RefreshLogoMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.spinning && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!widget.spinning && _ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = widget.size * _kLogoAspect;
    final mark = CustomPaint(
      size: Size(widget.size, height),
      painter: _LogoPainter(color: widget.color),
    );
    if (!widget.spinning) return mark;
    return RotationTransition(turns: _ctrl, child: mark);
  }
}

const double _kLogoAspect = 431 / 615;

class _LogoPainter extends CustomPainter {
  _LogoPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 615;
    canvas.save();
    canvas.scale(scale, scale);
    canvas.drawPath(_logoPath, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.color != color;
}

final Path _logoPath = Path()
  ..moveTo(55, 0.300781)
  ..cubicTo(55.0429, 0.240718, 55.0858, 0.180066, 55.1289, 0.120117)
  ..lineTo(307.613, 181.841)
  ..lineTo(560, 0.191406)
  ..lineTo(560, 0)
  ..lineTo(615, 0)
  ..lineTo(615, 431)
  ..lineTo(560.331, 431)
  ..cubicTo(560.254, 431.109, 560.177, 431.218, 560.099, 431.326)
  ..lineTo(307.613, 249.605)
  ..lineTo(55.1289, 431.326)
  ..cubicTo(55.0509, 431.218, 54.9736, 431.109, 54.8965, 431)
  ..lineTo(0, 431)
  ..lineTo(0, 0)
  ..lineTo(55, 0)
  ..close()
  ..moveTo(55, 367.223)
  ..cubicTo(58.4014, 362.461, 62.6267, 358.166, 67.6396, 354.558)
  ..lineTo(260.537, 215.723)
  ..lineTo(67.6396, 76.8896)
  ..cubicTo(62.6264, 73.2815, 58.4015, 68.9853, 55, 64.2236)
  ..close()
  ..moveTo(560, 64.5381)
  ..cubicTo(556.638, 69.1742, 552.49, 73.3612, 547.588, 76.8896)
  ..lineTo(354.689, 215.723)
  ..lineTo(547.588, 354.558)
  ..cubicTo(552.49, 358.086, 556.638, 362.272, 560, 366.908)
  ..close();
