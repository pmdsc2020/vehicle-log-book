import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/motion.dart';
import '../ui/theme.dart';

/// The opening animation. It starts as the phone's own launch screen ends (the logo on green,
/// at the same size and place), then brings the logo to life: the pin hops, the keyhole turns
/// and locks, the odometer drums roll up to their figures, and the name rises in.
/// Tap anywhere to skip.
class SplashScreen extends StatefulWidget {
  final VoidCallback onDone;
  const SplashScreen({super.key, required this.onDone});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  bool _done = false;
  Timer? _hold;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) _finish();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isAnimating || _c.isCompleted) return;
    if (Motion.reduced(context)) {
      // No travel: show the finished mark briefly, then go.
      _c.value = 1;
      _hold = Timer(const Duration(milliseconds: 500), _finish);
    } else {
      _c.forward();
    }
  }

  void _finish() {
    if (_done || !mounted) return;
    _done = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _hold?.cancel();
    _c.dispose();
    super.dispose();
  }

  /// [t] mapped into [a, b] and eased.
  double _seg(double a, double b, [Curve curve = Curves.easeOutCubic]) {
    final v = ((_c.value - a) / (b - a)).clamp(0.0, 1.0);
    return curve.transform(v);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AppColors.green,
      ),
      child: Semantics(
        button: true,
        label: 'Vehicle Log Book. Tap to skip the intro.',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _finish,
          child: ColoredBox(
            color: AppColors.green,
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final grow = _seg(0.0, 0.28, Curves.easeOutBack);
                final words = _seg(0.52, 0.78);
                final tag = _seg(0.62, 0.88);
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // A slow glow behind the mark.
                    Center(
                      child: Transform.translate(
                        offset: Offset(0, -56 * grow),
                        child: Opacity(
                          opacity: _seg(0.05, 0.4),
                          child: Container(
                            width: 320,
                            height: 320,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(colors: [Color(0x5563D3B0), Color(0x0063D3B0)]),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: Transform.translate(
                        offset: Offset(0, -56 * grow),
                        child: Transform.scale(
                          scale: 1 + 1.1 * grow,
                          child: SizedBox(
                            width: 108,
                            height: 108,
                            child: CustomPaint(
                              painter: _LogoPainter(
                                hop: _seg(0.12, 0.42, Curves.linear),
                                turn: _seg(0.26, 0.56, Curves.linear),
                                roll: _seg(0.22, 0.72, Curves.linear),
                                ring: _seg(0.40, 0.85, Curves.linear),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: const Alignment(0, 0.42),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Opacity(
                            opacity: words,
                            child: Transform.translate(
                              offset: Offset(0, 22 * (1 - words)),
                              child: Text(
                                'Vehicle Log Book',
                                style: tt.headlineMedium?.copyWith(color: Colors.white, letterSpacing: -0.4),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Opacity(
                            opacity: tag,
                            child: Transform.translate(
                              offset: Offset(0, 14 * (1 - tag)),
                              child: Text(
                                'Every trip, locked and sealed',
                                style: tt.bodyLarge?.copyWith(color: AppColors.onDrumMuted),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// The logo from brand/logo.svg, drawn on a 108 x 108 canvas so its parts can move.
class _LogoPainter extends CustomPainter {
  /// 0 to 1 over each part's own stretch of the timeline.
  final double hop;
  final double turn;
  final double roll;
  final double ring;

  _LogoPainter({required this.hop, required this.turn, required this.roll, required this.ring});

  static const _white = Colors.white;
  static const _hole = AppColors.green;
  static const _digits = [0, 4, 2, 6];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 108);

    // Rings spreading from the pin, like a location ping.
    for (var i = 0; i < 2; i++) {
      final r = (ring - i * 0.25).clamp(0.0, 1.0);
      if (r <= 0 || r >= 1) continue;
      canvas.drawCircle(
        const Offset(54, 41),
        16 + 34 * Curves.easeOut.transform(r),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6 * (1 - r) + 0.3
          ..color = Colors.white.withAlpha((150 * (1 - r)).round()),
      );
    }

    // The pin hops: up, then lands with a little squash.
    final up = math.sin(hop * math.pi);
    final land = hop > 0.8 ? math.sin((hop - 0.8) / 0.2 * math.pi) : 0.0;
    canvas.save();
    canvas.translate(54, 65);
    canvas.scale(1 + 0.06 * land, 1 - 0.08 * land);
    canvas.translate(-54, -65 - 9 * up);

    final pin = Path()
      ..moveTo(54, 65)
      ..cubicTo(54, 65, 38.5, 52, 38.5, 41)
      ..arcToPoint(const Offset(69.5, 41), radius: const Radius.circular(15.5), largeArc: true, clockwise: true)
      ..cubicTo(69.5, 52, 54, 65, 54, 65)
      ..close();
    canvas.drawPath(pin, Paint()..color = _white);

    // The keyhole turns a quarter and springs back: the entry locks.
    final angle = turn < 0.5
        ? Curves.easeInOut.transform(turn / 0.5) * math.pi / 2
        : (1 - Curves.elasticOut.transform((turn - 0.5) / 0.5)) * math.pi / 2;
    canvas.save();
    canvas.translate(54, 44);
    canvas.rotate(angle);
    canvas.translate(-54, -44);
    final hole = Paint()..color = _hole;
    canvas.drawCircle(const Offset(54, 39.2), 6, hole);
    canvas.drawPath(
      Path()
        ..moveTo(51.3, 42.5)
        ..lineTo(56.7, 42.5)
        ..lineTo(58.4, 51)
        ..quadraticBezierTo(58.5, 51.8, 57.7, 51.8)
        ..lineTo(50.3, 51.8)
        ..quadraticBezierTo(49.5, 51.8, 49.6, 51)
        ..close(),
      hole,
    );
    canvas.restore();
    canvas.restore();

    // The drums, each rolling up through the digits to its figure, one after the other.
    const x0 = 33.3, w = 9.0, gap = 1.8, y = 70.0, h = 11.0;
    for (var i = 0; i < 4; i++) {
      final x = x0 + i * (w + gap);
      final rect = RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), const Radius.circular(2.2));
      canvas.drawRRect(rect, Paint()..color = i == 3 ? AppColors.amber : _white);

      final local = ((roll - i * 0.12) / 0.64).clamp(0.0, 1.0);
      // One full turn from the figure back round to it, so the first frame matches the launch screen.
      final pos = _digits[i] + Curves.easeInOutCubic.transform(local) * 10;
      final shown = pos.floor();
      final frac = pos - shown;

      canvas.save();
      canvas.clipRRect(rect);
      for (final (d, dy) in [(shown % 10, -frac * h), ((shown + 1) % 10, (1 - frac) * h)]) {
        if (dy.abs() >= h) continue;
        final tp = TextPainter(
          text: TextSpan(
            text: '$d',
            style: const TextStyle(
              fontFamily: kFont,
              fontSize: 8.6,
              fontWeight: FontWeight.w700,
              color: _hole,
              height: 1,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x + (w - tp.width) / 2, y + (h - tp.height) / 2 + dy));
      }
      // Curve of the drum.
      canvas.drawRect(
        Rect.fromLTWH(x, y, w, h),
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x33000000), Color(0x00000000), Color(0x00000000), Color(0x33000000)],
            stops: [0, 0.3, 0.7, 1],
          ).createShader(Rect.fromLTWH(x, y, w, h)),
      );
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.hop != hop || old.turn != turn || old.roll != roll || old.ring != ring;
}
