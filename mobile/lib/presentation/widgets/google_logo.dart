import 'package:flutter/material.dart';

class GoogleLogoWidget extends StatelessWidget {
  final double size;

  const GoogleLogoWidget({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _GoogleLogoPainter(),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final double cx = w / 2;
    final double cy = h / 2;
    final double radius = w / 2;
    final double strokeWidth = w * 0.22;

    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: radius - strokeWidth / 2);

    // Paints
    final paintRed = Paint()
      ..color = const Color(0xFFEA4335)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    final paintYellow = Paint()
      ..color = const Color(0xFFFBBC05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    final paintGreen = Paint()
      ..color = const Color(0xFF34A853)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    final paintBlue = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    // Google G arcs
    // Red: Top left to top right (~180 to 305 deg)
    canvas.drawArc(rect, 3.14159 * 1.15, 3.14159 * 0.65, false, paintRed);
    // Yellow: Bottom left (~130 to 180 deg)
    canvas.drawArc(rect, 3.14159 * 0.72, 3.14159 * 0.43, false, paintYellow);
    // Green: Bottom (~30 to 130 deg)
    canvas.drawArc(rect, 3.14159 * 0.15, 3.14159 * 0.57, false, paintGreen);
    // Blue: Right arc + middle bar
    canvas.drawArc(rect, -3.14159 * 0.20, 3.14159 * 0.35, false, paintBlue);

    // Middle horizontal bar of 'G'
    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;

    final barRect = Rect.fromLTRB(
      cx - strokeWidth * 0.2,
      cy - strokeWidth / 2,
      w,
      cy + strokeWidth / 2,
    );
    canvas.drawRect(barRect, barPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
