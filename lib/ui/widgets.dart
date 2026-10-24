import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'motion.dart';
import 'theme.dart';

// ------------------------------------------------------------------ brand

class LogoMark extends StatelessWidget {
  final double size;
  const LogoMark({super.key, this.size = 36});

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/logo/logo_mark.png',
        width: size,
        height: size,
        filterQuality: FilterQuality.medium,
        semanticLabel: 'Vehicle Log Book',
      );
}

// ------------------------------------------------------------------ surfaces

/// Padding for a tab's scrolling page: room at the bottom for the floating nav bar.
EdgeInsets pagePadding(BuildContext context) =>
    EdgeInsets.fromLTRB(16, 4, 16, 28 + MediaQuery.paddingOf(context).bottom);

/// A frosted-glass panel. Pass [onTap] to make the whole panel a button.
class Surface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double radius;
  final bool outlined;
  final VoidCallback? onTap;
  final String? semanticLabel;

  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.radius = 20,
    this.outlined = true,
    this.onTap,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) => GlassCard(
        padding: padding,
        tint: color,
        radius: radius,
        borderColor: outlined ? null : Colors.transparent,
        onTap: onTap,
        semanticLabel: semanticLabel,
        child: child,
      );
}

/// A small card that does one thing: an icon tile, a title and a line under it.
/// [accent] shows the line as a figure.
class ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback? onTap;
  final bool accent;

  const ActionCard({super.key, required this.icon, required this.title, required this.body, this.onTap, this.accent = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: accent ? AppGradients.amber : AppGradients.brand(cs.brightness),
                  ),
                ),
                child: Icon(icon, size: 21, color: accent ? AppColors.ink : Colors.white),
              ),
              const Spacer(),
              Icon(AppIcons.arrow, size: 18, color: cs.onSurfaceVariant),
            ],
          ),
          const SizedBox(height: 12),
          Text(title, style: tt.titleSmall),
          const SizedBox(height: 2),
          accent
              ? FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(body, style: numStyle(20, weight: FontWeight.w700, color: cs.primary)),
                )
              : Text(body, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 10),
        child: Row(
          children: [
            Expanded(child: Text(text, style: Theme.of(context).textTheme.titleLarge)),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  const EmptyState({super.key, required this.icon, required this.title, required this.body, this.action});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Float(
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [cs.primaryContainer, cs.primaryContainer.withAlpha(150)],
                ),
                boxShadow: [BoxShadow(color: cs.primary.withAlpha(40), blurRadius: 20, offset: const Offset(0, 8))],
              ),
              child: Icon(icon, size: 30, color: cs.onPrimaryContainer),
            ),
          ),
          const SizedBox(height: 16),
          Text(title, style: tt.titleMedium, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text(
              body,
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ odometer

/// Mechanical odometer readout. Leading zeros are dimmed and the last drum is amber,
/// as on the logo. When [rollIn] is set the drums roll up from zero the first time they appear.
class OdometerDrums extends StatefulWidget {
  final int value;
  final int digits;
  final double cellWidth;
  final double cellHeight;
  final double fontSize;
  final bool amberLast;
  final bool rollIn;

  const OdometerDrums({
    super.key,
    required this.value,
    this.digits = 5,
    this.cellWidth = 44,
    this.cellHeight = 64,
    this.fontSize = 42,
    this.amberLast = true,
    this.rollIn = false,
  });

  @override
  State<OdometerDrums> createState() => _OdometerDrumsState();
}

class _OdometerDrumsState extends State<OdometerDrums> {
  late int _shown;

  @override
  void initState() {
    super.initState();
    _shown = widget.rollIn ? 0 : widget.value;
    if (widget.rollIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _shown = widget.value);
      });
    }
  }

  @override
  void didUpdateWidget(OdometerDrums old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _shown = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    final maxV = math.pow(10, widget.digits).toInt() - 1;
    final v = _shown < 0 ? 0 : (_shown > maxV ? maxV : _shown);
    final s = v.toString().padLeft(widget.digits, '0');
    final firstSig = s.indexOf(RegExp(r'[1-9]'));
    final sigFrom = firstSig < 0 ? widget.digits - 1 : firstSig;
    final gap = widget.cellWidth > 30 ? 4.0 : 3.0;
    return Semantics(
      label: '${widget.value} kilometres',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < widget.digits; i++) ...[
              if (i > 0) SizedBox(width: gap),
              _Drum(
                char: s[i],
                dim: i < sigFrom,
                amber: widget.amberLast && i == widget.digits - 1,
                width: widget.cellWidth,
                height: widget.cellHeight,
                fontSize: widget.fontSize,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Drum extends StatelessWidget {
  final String char;
  final bool dim;
  final bool amber;
  final double width;
  final double height;
  final double fontSize;

  const _Drum({
    required this.char,
    required this.dim,
    required this.amber,
    required this.width,
    required this.height,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(width > 30 ? 8 : 5);
    final color = amber ? AppColors.amber : (dim ? AppColors.onDrumFaint : AppColors.onDrum);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1B2B26), AppColors.drum, Color(0xFF0A1310)],
        ),
        borderRadius: radius,
        border: Border.all(color: AppColors.drumStroke),
        boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 6, offset: Offset(0, 3))],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 520),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, anim) => SlideTransition(
                position: Tween<Offset>(begin: const Offset(0, 0.8), end: Offset.zero).animate(anim),
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: Text(
                char,
                key: ValueKey<String>('$char-$dim-$amber'),
                style: numStyle(fontSize, weight: FontWeight.w700, color: color),
              ),
            ),
            // Curve of the drum: shade the top and bottom edges.
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: const [Color(0x99000000), Color(0x00000000), Color(0x00000000), Color(0x99000000)],
                      stops: const [0.0, 0.3, 0.7, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The month's km as a road: filled up to the limit, amber beyond it, with a milestone
/// at the limit. Drawn for the dark drum surface.
class LimitRoad extends StatelessWidget {
  final int used;
  final int limit;
  const LimitRoad({super.key, required this.used, required this.limit});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final total = math.max(math.max(used, limit), 1).toDouble();
    final limitFrac = limit <= 0 ? 1.0 : limit / total;
    final withinFrac = math.min(used, limit) / total;
    final over = used > limit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (context, t, _) => LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              return SizedBox(
                height: 28,
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 9,
                      height: 10,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: AppColors.drumTrack, borderRadius: BorderRadius.circular(5)),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      top: 9,
                      height: 10,
                      width: w * withinFrac * t,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: AppColors.greenLight, borderRadius: BorderRadius.circular(5)),
                      ),
                    ),
                    if (over)
                      Positioned(
                        left: w * limitFrac,
                        top: 9,
                        height: 10,
                        width: w * (1 - limitFrac) * t,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppColors.amber,
                            borderRadius: const BorderRadius.horizontal(right: Radius.circular(5)),
                          ),
                        ),
                      ),
                    Positioned(
                      left: math.max(0.0, w * limitFrac - 1.5),
                      top: 2,
                      height: 24,
                      width: 3,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: AppColors.onDrum, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment(limitFrac * 2 - 1, 0),
          child: Text(
            '$limit km limit',
            style: tt.bodySmall?.copyWith(color: AppColors.onDrumMuted, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ status

enum PillKind { locked, open, cancelled, flag, info }

class StatusPill extends StatelessWidget {
  final String label;
  final PillKind kind;
  final IconData? icon;

  const StatusPill(this.label, {super.key, this.kind = PillKind.info, this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Color bg;
    Color fg;
    IconData? ic = icon;
    switch (kind) {
      case PillKind.locked:
        bg = cs.primaryContainer;
        fg = cs.onPrimaryContainer;
        ic ??= AppIcons.lock;
        break;
      case PillKind.open:
        bg = cs.tertiaryContainer;
        fg = cs.onTertiaryContainer;
        
        break;
      case PillKind.cancelled:
        bg = cs.surfaceContainerHigh;
        fg = cs.onSurfaceVariant;
        ic ??= AppIcons.cancelled;
        break;
      case PillKind.flag:
        bg = cs.errorContainer;
        fg = cs.onErrorContainer;
        ic ??= AppIcons.flag;
        break;
      case PillKind.info:
        bg = cs.surfaceContainerHigh;
        fg = cs.onSurfaceVariant;
        break;
    }
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 9, vertical: kind == PillKind.open && ic == null ? 1 : 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withAlpha(30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (kind == PillKind.open && ic == null)
            Padding(padding: const EdgeInsets.only(right: 2), child: PulseDot(color: fg, size: 7))
          else if (ic != null) ...[Icon(ic, size: 13, color: fg), const SizedBox(width: 5)],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ route

/// From and to, joined by a dashed line: a filled dot where you left, a ring where you went.
class RouteLine extends StatelessWidget {
  final String from;
  final String to;
  final int toLines;
  final bool large;

  const RouteLine({super.key, required this.from, required this.to, this.toLines = 1, this.large = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final fromStyle = (large ? tt.bodyLarge : tt.bodyMedium)?.copyWith(color: cs.onSurfaceVariant);
    final toStyle = (large ? tt.titleLarge : tt.titleMedium);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 16,
            child: CustomPaint(painter: _RoutePainter(color: cs.primary, line: cs.outline, topY: large ? 12 : 11, bottomInset: large ? 16 : 13)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(from, style: fromStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Text(to, style: toStyle, maxLines: toLines, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  final Color color;
  final Color line;
  final double topY;
  final double bottomInset;
  const _RoutePainter({required this.color, required this.line, required this.topY, required this.bottomInset});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final yTop = topY;
    final yBottom = size.height - bottomInset;
    final dash = Paint()
      ..color = line
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    var y = yTop + 8;
    while (y + 3 < yBottom - 8) {
      canvas.drawLine(Offset(cx, y), Offset(cx, y + 3), dash);
      y += 7;
    }
    canvas.drawCircle(Offset(cx, yTop), 4.5, Paint()..color = color);
    canvas.drawCircle(
      Offset(cx, yBottom),
      4.5,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_RoutePainter old) =>
      old.color != color || old.line != line || old.topY != topY || old.bottomInset != bottomInset;
}

// ------------------------------------------------------------------ ledger

/// A label and a figure joined by a dotted leader, like a line in a log book.
/// The leader runs from the end of the label's last line to the figure, so a long label
/// wraps instead of overflowing, even at large text sizes, and the panel behind shows through.
class LedgerRow extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;
  final Color? valueColor;

  const LedgerRow({super.key, required this.label, required this.value, this.strong = false, this.valueColor});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final labelStyle = (strong ? tt.titleMedium : tt.bodyMedium)!;
    final valueStyle = numStyle(strong ? 24 : 18,
        weight: strong ? FontWeight.w700 : FontWeight.w600, color: valueColor ?? cs.onSurface);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: LayoutBuilder(
        builder: (context, c) {
          final scaler = MediaQuery.textScalerOf(context);
          final dir = Directionality.of(context);
          final vp = TextPainter(
            text: TextSpan(text: value, style: valueStyle),
            textDirection: dir,
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          final lp = TextPainter(text: TextSpan(text: label, style: labelStyle), textDirection: dir, textScaler: scaler)
            ..layout(maxWidth: math.max(0.0, c.maxWidth - vp.width - 16));
          final lines = lp.computeLineMetrics();
          final lastLine = lines.isEmpty ? 0.0 : lines.last.width;
          final dotsLeft = lastLine + 8;
          final dotsRight = vp.width + 8;
          return Stack(
            children: [
              if (c.maxWidth - dotsLeft - dotsRight > 6)
                Positioned(
                  left: dotsLeft,
                  right: dotsRight,
                  bottom: 5,
                  height: 2,
                  child: CustomPaint(painter: _DotsPainter(cs.outline.withAlpha(110))),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(child: Text(label, style: labelStyle)),
                  const SizedBox(width: 16),
                  Text(value, style: valueStyle),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DotsPainter extends CustomPainter {
  final Color color;
  const _DotsPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    var x = 1.0;
    while (x < size.width) {
      canvas.drawCircle(Offset(x, 1), 1, p);
      x += 5;
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) => old.color != color;
}

// ------------------------------------------------------------------ approvals

/// Staff, then Block Integrator, then Accountant, then District Integrator.
/// [done] is how many of the four have finished their step.
class ApprovalChain extends StatelessWidget {
  final int done;
  const ApprovalChain({super.key, required this.done});

  static const _who = ['You', 'Block Integrator', 'Accountant', 'District Integrator'];
  static const _what = ['submit', 'checks', 'verifies', 'approves'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < 4; i++)
          Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _Rail(show: i > 0, on: i <= done, color: cs.primary, off: cs.outlineVariant)),
                    _Node(state: i < done ? 2 : (i == done ? 1 : 0)),
                    Expanded(child: _Rail(show: i < 3, on: i < done, color: cs.primary, off: cs.outlineVariant)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _who[i],
                  style: tt.labelMedium?.copyWith(fontWeight: i == done ? FontWeight.w700 : FontWeight.w500),
                  textAlign: TextAlign.center,
                ),
                Text(
                  _what[i],
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Rail extends StatelessWidget {
  final bool show;
  final bool on;
  final Color color;
  final Color off;
  const _Rail({required this.show, required this.on, required this.color, required this.off});

  @override
  Widget build(BuildContext context) => Container(
        height: 3,
        color: show ? (on ? color : off) : Colors.transparent,
      );
}

class _Node extends StatelessWidget {
  /// 0 waiting, 1 next to act, 2 finished
  final int state;
  const _Node({required this.state});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (state == 2) {
      return TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: Motion.slow,
        curve: Curves.elasticOut,
        builder: (context, v, child) => Transform.scale(scale: v, child: child),
        child: CircleAvatar(radius: 14, backgroundColor: cs.primary, child: Icon(AppIcons.check, size: 16, color: cs.onPrimary)),
      );
    }
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: state == 1 ? cs.primaryContainer : cs.surface,
        border: Border.all(color: state == 1 ? cs.primary : cs.outlineVariant, width: 2),
      ),
      child: state == 1 ? Center(child: Container(width: 8, height: 8, decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle))) : null,
    );
  }
}

// ------------------------------------------------------------------ month chips

class MonthChips extends StatelessWidget {
  final List<String> months;
  final String selected;
  final String Function(String) label;
  final ValueChanged<String> onSelected;

  const MonthChips({super.key, required this.months, required this.selected, required this.label, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: months.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final m = months[i];
          return ChoiceChip(
            label: Text(label(m)),
            selected: m == selected,
            onSelected: (_) => onSelected(m),
          );
        },
      ),
    );
  }
}

/// A figure with a small caption, used in summary strips.
class StatCell extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const StatCell({super.key, required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: numStyle(26, weight: FontWeight.w700, color: color ?? cs.onSurface)),
        ),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      ],
    );
  }
}
