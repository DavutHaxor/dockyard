import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    required this.color,
    this.height = 56,
    this.minY = 0,
    this.maxY = 100,
    this.strokeWidth = 2,
  });

  final List<double> values;
  final Color color;
  final double height;
  final double minY;
  final double maxY;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparklinePainter(
          values: values
              .where((value) => value.isFinite)
              .toList(growable: false),
          color: color,
          gridColor: scheme.outlineVariant.withValues(alpha: 0.45),
          minY: minY,
          maxY: maxY,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.values,
    required this.color,
    required this.gridColor,
    required this.minY,
    required this.maxY,
    required this.strokeWidth,
  });

  final List<double> values;
  final Color color;
  final Color gridColor;
  final double minY;
  final double maxY;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (values.isEmpty) return;

    final lower = minY;
    final upper = maxY <= minY ? minY + 1 : maxY;
    final range = upper - lower;

    double pointX(int index) => values.length == 1
        ? size.width / 2
        : size.width * index / (values.length - 1);
    double pointY(double value) =>
        size.height -
        ((value.clamp(lower, upper) - lower) / range) * size.height;

    final line = Path();
    for (var i = 0; i < values.length; i++) {
      final point = Offset(pointX(i), pointY(values[i]));
      if (i == 0) {
        line.moveTo(point.dx, point.dy);
      } else {
        line.lineTo(point.dx, point.dy);
      }
    }

    if (values.length == 1) {
      canvas.drawCircle(
        Offset(pointX(0), pointY(values.first)),
        strokeWidth + 1.5,
        Paint()..color = color,
      );
      return;
    }

    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SparklinePainter oldDelegate) =>
      !listEquals(oldDelegate.values, values) ||
      oldDelegate.color != color ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.minY != minY ||
      oldDelegate.maxY != maxY ||
      oldDelegate.strokeWidth != strokeWidth;
}
