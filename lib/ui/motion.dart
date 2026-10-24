import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Motion tokens. Every animation in the app picks one of these so the app moves as one.
class Motion {
  static const fast = Duration(milliseconds: 140);
  static const medium = Duration(milliseconds: 260);
  static const slow = Duration(milliseconds: 520);
  static const emphasized = Curves.easeOutCubic;
  static const spring = Curves.easeOutBack;

  /// True when the phone asks for reduced motion (or a test does).
  /// Looping and decorative animations stop; state changes still show, just without the travel.
  static bool reduced(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

// ------------------------------------------------------------------ pressable

/// Hover lift, press squash, a focus ring and a light haptic, for any tappable card.
/// Keyboard and screen readers get the same action: it is an InkWell underneath.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BorderRadius borderRadius;
  final String? semanticLabel;
  final double pressedScale;
  final double hoverLift;
  final Color? glow;

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.semanticLabel,
    this.pressedScale = 0.975,
    this.hoverLift = 3,
    this.glow,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _hover = false;
  bool _pressed = false;
  bool _focus = false;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduced = Motion.reduced(context);
    final glow = widget.glow ?? cs.primary;
    final lift = _enabled && _hover && !_pressed && !reduced ? widget.hoverLift : 0.0;
    final scale = _enabled && _pressed && !reduced ? widget.pressedScale : 1.0;

    Widget child = Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: widget.borderRadius,
        onTap: widget.onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                widget.onTap!();
              },
        onLongPress: widget.onLongPress,
        onHover: (v) => setState(() => _hover = v),
        onHighlightChanged: (v) => setState(() => _pressed = v),
        onFocusChange: (v) => setState(() => _focus = v),
        splashColor: glow.withAlpha(30),
        highlightColor: glow.withAlpha(14),
        hoverColor: glow.withAlpha(10),
        child: widget.child,
      ),
    );

    child = AnimatedContainer(
      duration: Motion.medium,
      curve: Motion.emphasized,
      transform: Matrix4.translationValues(0, -lift, 0),
      decoration: BoxDecoration(
        borderRadius: widget.borderRadius,
        boxShadow: [
          if (lift > 0)
            BoxShadow(color: glow.withAlpha(46), blurRadius: 24, spreadRadius: -4, offset: const Offset(0, 10)),
        ],
      ),
      foregroundDecoration: _focus
          ? BoxDecoration(borderRadius: widget.borderRadius, border: Border.all(color: cs.primary, width: 2.5))
          : null,
      child: child,
    );

    child = AnimatedScale(scale: scale, duration: Motion.fast, curve: Curves.easeOut, child: child);
    if (widget.semanticLabel != null) {
      child = Semantics(button: true, label: widget.semanticLabel, child: child);
    }
    return child;
  }
}

// ------------------------------------------------------------------ cards

/// The standard card: frosted glass over the aurora, with a hairline highlight on the top edge.
/// Give it [onTap] and it lifts on hover and squashes on press.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double radius;
  final Color? tint;
  final Color? borderColor;
  final double borderWidth;
  final String? semanticLabel;

  /// Real backdrop blur. Costly, so only for panels that float over moving content.
  final bool blur;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.onLongPress,
    this.radius = 20,
    this.tint,
    this.borderColor,
    this.borderWidth = 1,
    this.semanticLabel,
    this.blur = false,
  });

  @override
  Widget build(BuildContext context) {
    final g = GlassColors.of(context);
    final br = BorderRadius.circular(radius);
    Widget body = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: br,
        color: tint ?? g.fill,
        gradient: tint == null
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [g.fillHigh, g.fill],
              )
            : null,
        // No drop shadow: it would show through the frosted fill.
        border: Border.all(color: borderColor ?? g.stroke, width: borderWidth),
      ),
      child: Pressable(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: br,
        semanticLabel: semanticLabel,
        hoverLift: 0,
        child: Padding(padding: padding, child: child),
      ),
    );
    if (blur) {
      body = ClipRRect(
        borderRadius: br,
        child: BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18), child: body),
      );
    }
    if (onTap == null && onLongPress == null) return body;
    // The lift and shadow live outside the card so the whole card rises, not just its content.
    return _HoverLift(radius: br, child: body);
  }
}

/// Lifts its child a few pixels while the pointer is over it.
class _HoverLift extends StatefulWidget {
  final Widget child;
  final BorderRadius radius;
  const _HoverLift({required this.child, required this.radius});

  @override
  State<_HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<_HoverLift> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final on = _hover && !Motion.reduced(context);
    final glow = Theme.of(context).colorScheme.primary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: Motion.medium,
        curve: Motion.emphasized,
        transform: Matrix4.translationValues(0, on ? -3 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: widget.radius,
          boxShadow: [
            if (on) BoxShadow(color: glow.withAlpha(40), blurRadius: 28, spreadRadius: -6, offset: const Offset(0, 14))
          ],
        ),
        child: widget.child,
      ),
    );
  }
}

/// Frosted panel with real backdrop blur, for bars that float over scrolling content.
class GlassBar extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;

  const GlassBar({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(28)),
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final g = GlassColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [BoxShadow(color: g.shadow, blurRadius: 30, offset: const Offset(0, 10), spreadRadius: -8)],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              color: g.bar,
              border: Border.all(color: g.stroke),
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ aurora

/// Soft drifting colour behind the whole app, so the glass has something to frost.
/// It holds still when the phone asks for reduced motion.
class AuroraBackground extends StatefulWidget {
  final Widget child;
  const AuroraBackground({super.key, required this.child});

  @override
  State<AuroraBackground> createState() => _AuroraBackgroundState();
}

class _AuroraBackgroundState extends State<AuroraBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 24));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = GlassColors.of(context);
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return DecoratedBox(
      decoration: BoxDecoration(color: bg),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => CustomPaint(painter: _AuroraPainter(_c.value, g.aurora)),
              ),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  final double t;
  final List<Color> colors;
  _AuroraPainter(this.t, this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    final a = t * 2 * math.pi;
    final blobs = <(Offset, double, Color)>[
      (
        Offset(size.width * (0.15 + 0.08 * math.sin(a)), size.height * (0.10 + 0.04 * math.cos(a))),
        size.width * 0.75,
        colors[0]
      ),
      (
        Offset(size.width * (0.95 + 0.06 * math.cos(a)), size.height * (0.30 + 0.05 * math.sin(a))),
        size.width * 0.65,
        colors[1]
      ),
      (
        Offset(size.width * (0.30 + 0.10 * math.cos(a + 1)), size.height * (0.85 + 0.04 * math.sin(a + 1))),
        size.width * 0.8,
        colors[2]
      ),
    ];
    for (final (c, r, col) in blobs) {
      final p = Paint()
        ..shader = RadialGradient(colors: [col, col.withAlpha(0)]).createShader(Rect.fromCircle(center: c, radius: r));
      canvas.drawCircle(c, r, p);
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => old.t != t || old.colors != colors;
}

// ------------------------------------------------------------------ entrance

/// Fades and slides its child up into place, [delay] after it first builds.
/// Lists pass a growing delay so their items arrive one after another.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final double offset;

  const FadeSlideIn({super.key, required this.child, this.delay = Duration.zero, this.offset = 18});

  /// Delay for the [i]th item of a list, capped so long lists do not keep the user waiting.
  static Duration stagger(int i) => Duration(milliseconds: 45 * math.min(i, 8));

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Motion.slow);
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: Motion.emphasized);
  Timer? _wait;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (Motion.reduced(context)) {
      _c.value = 1;
    } else if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      _wait = Timer(widget.delay, _c.forward);
    }
  }

  @override
  void dispose() {
    _wait?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _t,
        child: widget.child,
        builder: (context, child) => Opacity(
          opacity: _t.value,
          child: Transform.translate(offset: Offset(0, widget.offset * (1 - _t.value)), child: child),
        ),
      );
}

// ------------------------------------------------------------------ buttons

/// The main call to action: a brand gradient that squashes on press, glows on hover
/// and sends a light sweep across itself when it appears and when hovered.
class GlowButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool busy;

  /// Amber for "finish what is open", green for everything else.
  final bool amber;

  const GlowButton({super.key, required this.label, this.icon, this.onPressed, this.busy = false, this.amber = false});

  @override
  State<GlowButton> createState() => _GlowButtonState();
}

class _GlowButtonState extends State<GlowButton> with SingleTickerProviderStateMixin {
  late final AnimationController _sweep =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  bool _hover = false;
  bool _pressed = false;
  bool _focus = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !Motion.reduced(context)) _sweep.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  void _setHover(bool v) {
    setState(() => _hover = v);
    if (v && !_sweep.isAnimating && !Motion.reduced(context)) _sweep.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final enabled = widget.onPressed != null && !widget.busy;
    final reduced = Motion.reduced(context);
    final colors = widget.amber ? AppGradients.amber : AppGradients.brand(cs.brightness);
    final fg = widget.amber ? AppColors.ink : Colors.white;
    final br = BorderRadius.circular(18);

    final content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.busy)
          SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: fg))
        else if (widget.icon != null)
          AnimatedSlide(
            offset: Offset(_hover && !reduced ? 0.15 : 0, 0),
            duration: Motion.medium,
            curve: Motion.spring,
            child: Icon(widget.icon, size: 22, color: fg),
          ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            widget.label,
            style: tt.labelLarge?.copyWith(fontSize: 18, color: fg, fontWeight: FontWeight.w700, letterSpacing: 0.2),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );

    return Semantics(
      button: true,
      enabled: enabled,
      child: AnimatedScale(
        scale: _pressed && !reduced ? 0.96 : 1,
        duration: Motion.fast,
        child: AnimatedOpacity(
          opacity: enabled || widget.busy ? 1 : 0.45,
          duration: Motion.medium,
          child: AnimatedContainer(
            duration: Motion.medium,
            curve: Motion.emphasized,
            constraints: const BoxConstraints(minHeight: 58),
            decoration: BoxDecoration(
              borderRadius: br,
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
              boxShadow: [
                BoxShadow(
                  color: colors.last.withAlpha(_hover && enabled ? 120 : 70),
                  blurRadius: _hover && enabled ? 28 : 16,
                  spreadRadius: -6,
                  offset: Offset(0, _hover && enabled ? 12 : 8),
                ),
              ],
            ),
            foregroundDecoration:
                _focus ? BoxDecoration(borderRadius: br, border: Border.all(color: cs.onSurface, width: 2.5)) : null,
            child: ClipRRect(
              borderRadius: br,
              child: Stack(
                children: [
                  // Light sweep.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _sweep,
                        builder: (context, _) => _sweep.value == 0 || _sweep.value == 1
                            ? const SizedBox.shrink()
                            : FractionallySizedBox(
                                alignment: Alignment(-1.6 + 3.2 * Curves.easeInOut.transform(_sweep.value), 0),
                                widthFactor: 0.35,
                                child: Transform(
                                  transform: Matrix4.skewX(-0.35),
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(colors: [
                                        Colors.white.withAlpha(0),
                                        Colors.white.withAlpha(70),
                                        Colors.white.withAlpha(0),
                                      ]),
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                  Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      onTap: enabled
                          ? () {
                              HapticFeedback.lightImpact();
                              widget.onPressed!();
                            }
                          : null,
                      onHover: _setHover,
                      onHighlightChanged: (v) => setState(() => _pressed = v),
                      onFocusChange: (v) => setState(() => _focus = v),
                      splashColor: Colors.white.withAlpha(40),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                        child: Center(heightFactor: 1, child: content),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An icon button whose icon gives a small spring wiggle on hover and press.
class SpringIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? color;
  final double size;

  const SpringIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
    this.size = 22,
  });

  @override
  State<SpringIconButton> createState() => _SpringIconButtonState();
}

class _SpringIconButtonState extends State<SpringIconButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));

  void _kick() {
    if (!Motion.reduced(context)) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = GlassColors.of(context);
    return MouseRegion(
      onEnter: (_) => _kick(),
      child: IconButton(
        tooltip: widget.tooltip,
        onPressed: () {
          _kick();
          HapticFeedback.selectionClick();
          widget.onPressed();
        },
        style: IconButton.styleFrom(
          backgroundColor: g.fill,
          side: BorderSide(color: g.stroke),
          minimumSize: const Size(46, 46),
        ),
        icon: AnimatedBuilder(
          animation: _c,
          builder: (context, child) {
            // Damped wobble: big first swing, settling to rest.
            final v = _c.value;
            final angle = math.sin(v * math.pi * 4) * (1 - v) * 0.35;
            final scale = 1 + math.sin(v * math.pi) * 0.15;
            return Transform.rotate(angle: angle, child: Transform.scale(scale: scale, child: child));
          },
          child: Icon(widget.icon, size: widget.size, color: widget.color),
        ),
      ),
    );
  }
}

/// Sun or moon, turning into each other. Flips between light and dark.
class ThemeToggle extends StatelessWidget {
  final bool dark;
  final VoidCallback onPressed;
  const ThemeToggle({super.key, required this.dark, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final g = GlassColors.of(context);
    return Tooltip(
      message: dark ? 'Switch to light' : 'Switch to dark',
      child: Semantics(
        button: true,
        label: dark ? 'Switch to light mode' : 'Switch to dark mode',
        child: IconButton(
          onPressed: () {
            HapticFeedback.selectionClick();
            onPressed();
          },
          style: IconButton.styleFrom(
            backgroundColor: g.fill,
            side: BorderSide(color: g.stroke),
            minimumSize: const Size(46, 46),
          ),
          icon: AnimatedSwitcher(
            duration: Motion.slow,
            switchInCurve: Motion.spring,
            transitionBuilder: (child, anim) => RotationTransition(
              turns: Tween<double>(begin: -0.35, end: 0).animate(anim),
              child: ScaleTransition(scale: anim, child: FadeTransition(opacity: anim, child: child)),
            ),
            child: Icon(
              dark ? AppIcons.moon : AppIcons.sun,
              key: ValueKey<bool>(dark),
              size: 22,
              color: dark ? cs.primary : cs.amberText,
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ live

/// A dot with a ring that keeps spreading out from it: something is happening right now.
class PulseDot extends StatefulWidget {
  final Color color;
  final double size;
  const PulseDot({super.key, required this.color, this.size = 10});

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s * 2.4,
      height: s * 2.4,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Stack(
          alignment: Alignment.center,
          children: [
            if (_c.isAnimating)
              Container(
                width: s + s * 1.4 * _c.value,
                height: s + s * 1.4 * _c.value,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withAlpha((110 * (1 - _c.value)).round()),
                ),
              ),
            Container(width: s, height: s, decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color)),
          ],
        ),
      ),
    );
  }
}

/// Bobs its child gently up and down. For empty-state illustrations.
class Float extends StatefulWidget {
  final Widget child;
  const Float({super.key, required this.child});

  @override
  State<Float> createState() => _FloatState();
}

class _FloatState extends State<Float> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) =>
            Transform.translate(offset: Offset(0, -5 * Curves.easeInOut.transform(_c.value)), child: child),
      );
}
