import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Colour tokens. The one dark object in the app is the odometer drum.
class AppColors {
  static const green = Color(0xFF0D6B55); // brand, same as the HTML app
  static const greenLight = Color(0xFF63D3B0); // fills on the dark drum surface
  static const amber = Color(0xFFF2A93B); // last drum, "open", "needs attention"
  static const ink = Color(0xFF14201C);
  static const drum = Color(0xFF0F1B17);
  static const paper = Color(0xFFF2F6F4);
  static const line = Color(0xFFDCE5E0);
  static const danger = Color(0xFFB3261E);

  // Translucent whites for text and strokes on the drum surface.
  static const onDrum = Color(0xFFF2F6F4);
  static const onDrumMuted = Color(0xB3F2F6F4); // 70%
  static const onDrumFaint = Color(0x5CF2F6F4); // 36%
  static const drumStroke = Color(0x1AFFFFFF); // 10%
  static const drumTrack = Color(0x24FFFFFF); // 14%
}

/// Frosted-glass colours for the current brightness. Fills stay opaque enough
/// that text on them keeps the same contrast as on a solid surface.
class GlassColors {
  final Color fill;
  final Color fillHigh;
  final Color stroke;
  final Color bar;
  final Color shadow;
  final List<Color> aurora;

  const GlassColors._(this.fill, this.fillHigh, this.stroke, this.bar, this.shadow, this.aurora);

  static const light = GlassColors._(
    Color(0xD9FFFFFF), // 85% white
    Color(0xF2FFFFFF),
    Color(0xB3FFFFFF),
    Color(0xC7FFFFFF),
    Color(0x1F0D3B30),
    [Color(0x3863D3B0), Color(0x2EF2A93B), Color(0x2E0D6B55)],
  );

  static const dark = GlassColors._(
    Color(0xC2131D1A), // 76% surface
    Color(0xD91A2824),
    Color(0x1FFFFFFF),
    Color(0xB8101916),
    Color(0x66000000),
    [Color(0x330D6B55), Color(0x1FF2A93B), Color(0x2963D3B0)],
  );

  static GlassColors of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? dark : light;
}

class AppGradients {
  /// White text on these passes 4.5:1 at every stop.
  static List<Color> brand(Brightness b) => b == Brightness.dark
      ? const [Color(0xFF138A6E), Color(0xFF0B5A48)]
      : const [Color(0xFF0F7A61), Color(0xFF0A5443)];

  /// Ink text on amber.
  static const amber = [Color(0xFFF7C066), Color(0xFFF2A93B)];

  /// The drum surface, with a little green coming through from the top corner.
  static const drum = [Color(0xFF16302A), Color(0xFF0F1B17), Color(0xFF0B1411)];
}

/// Every icon in the app, from Lucide, in one place so the set stays consistent.
class AppIcons {
  static const today = LucideIcons.gauge;
  static const log = LucideIcons.bookOpen;
  static const report = LucideIcons.receiptText;
  static const review = LucideIcons.clipboardCheck;
  static const settings = LucideIcons.slidersHorizontal;

  static const start = LucideIcons.play;
  static const end = LucideIcons.flag;
  static const logFinished = LucideIcons.calendarPlus;
  static const route = LucideIcons.route;
  static const lock = LucideIcons.lock;
  static const lockOpen = LucideIcons.lockOpen;
  static const open = LucideIcons.circleDot;
  static const cancelled = LucideIcons.ban;
  static const flag = LucideIcons.flag;
  static const info = LucideIcons.info;
  static const warn = LucideIcons.triangleAlert;
  static const ok = LucideIcons.circleCheck;
  static const circle = LucideIcons.circle;
  static const check = LucideIcons.check;
  static const close = LucideIcons.x;
  static const add = LucideIcons.plus;
  static const clock = LucideIcons.clock;
  static const calendar = LucideIcons.calendar;
  static const camera = LucideIcons.camera;
  static const gallery = LucideIcons.images;
  static const noPhoto = LucideIcons.imageOff;
  static const sealOk = LucideIcons.shieldCheck;
  static const sealBad = LucideIcons.shieldAlert;
  static const approved = LucideIcons.badgeCheck;
  static const policy = LucideIcons.stamp;
  static const meter = LucideIcons.gauge;
  static const erase = LucideIcons.trash2;
  static const role = LucideIcons.idCard;
  static const twoWheeler = LucideIcons.bike;
  static const fourWheeler = LucideIcons.car;
  static const share = LucideIcons.share2;
  static const send = LucideIcons.send;
  static const openFile = LucideIcons.folderOpen;
  static const inbox = LucideIcons.inbox;
  static const chevron = LucideIcons.chevronRight;
  static const dropdown = LucideIcons.chevronDown;
  static const arrow = LucideIcons.arrowRight;
  static const sun = LucideIcons.sun;
  static const moon = LucideIcons.moon;
  static const phoneTheme = LucideIcons.smartphone;
  static const rupee = LucideIcons.indianRupee;
  static const note = LucideIcons.stickyNote;
}

extension AmberText on ColorScheme {
  /// Amber that stays readable as text: the bright amber on dark, a deeper amber on light.
  Color get amberText => brightness == Brightness.dark ? AppColors.amber : const Color(0xFF8A5A00);
}

const String kFont = 'BarlowSC';

/// Barlow has no rupee sign (or arrows), so the phone's own font fills in.
const List<String> kFontFallback = ['Roboto', 'Noto Sans'];

/// Figures that line up in columns (readings, km, rupees).
TextStyle numStyle(double size, {FontWeight weight = FontWeight.w600, Color? color}) => TextStyle(
      fontFamily: kFont,
      fontFamilyFallback: kFontFallback,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: 1.0,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

class AppTheme {
  static ThemeData light() {
    final cs = ColorScheme.fromSeed(seedColor: AppColors.green, brightness: Brightness.light).copyWith(
      primary: AppColors.green,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFD3EBE2),
      onPrimaryContainer: const Color(0xFF06382D),
      secondary: const Color(0xFF4B6359),
      tertiary: AppColors.amber,
      onTertiary: AppColors.ink,
      tertiaryContainer: const Color(0xFFFCEACB),
      onTertiaryContainer: const Color(0xFF4A2F00),
      surface: Colors.white,
      onSurface: AppColors.ink,
      onSurfaceVariant: const Color(0xFF4B5E57),
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: const Color(0xFFF7FAF8),
      surfaceContainer: const Color(0xFFEFF4F1),
      surfaceContainerHigh: const Color(0xFFE8EFEB),
      surfaceContainerHighest: const Color(0xFFE1E9E5),
      outline: const Color(0xFF7F8F88),
      outlineVariant: AppColors.line,
      error: AppColors.danger,
      errorContainer: const Color(0xFFFBE4E1),
      onErrorContainer: const Color(0xFF5C0F09),
    );
    return _build(cs, AppColors.paper);
  }

  static ThemeData dark() {
    final cs = ColorScheme.fromSeed(seedColor: AppColors.green, brightness: Brightness.dark).copyWith(
      primary: const Color(0xFF63D3B0),
      onPrimary: const Color(0xFF00382B),
      primaryContainer: const Color(0xFF0F4F40),
      onPrimaryContainer: const Color(0xFFC9F0E3),
      tertiary: AppColors.amber,
      onTertiary: const Color(0xFF3A2400),
      tertiaryContainer: const Color(0xFF5A3C00),
      onTertiaryContainer: const Color(0xFFFFDEA6),
      surface: const Color(0xFF131D1A),
      onSurface: const Color(0xFFE5ECE8),
      onSurfaceVariant: const Color(0xFFA9B9B2),
      surfaceContainerLowest: const Color(0xFF0B1210),
      surfaceContainerLow: const Color(0xFF101916),
      surfaceContainer: const Color(0xFF16211E),
      surfaceContainerHigh: const Color(0xFF1C2825),
      surfaceContainerHighest: const Color(0xFF233230),
      outline: const Color(0xFF6C7D76),
      outlineVariant: const Color(0xFF2A3A35),
      error: const Color(0xFFFFB4AB),
      errorContainer: const Color(0xFF5C1A15),
      onErrorContainer: const Color(0xFFFFDAD6),
    );
    return _build(cs, const Color(0xFF0B1210));
  }

  static TextTheme _textTheme(TextTheme t) => t.copyWith(
        displaySmall: t.displaySmall?.copyWith(fontSize: 40, fontWeight: FontWeight.w700, letterSpacing: -0.8),
        headlineMedium:
            t.headlineMedium?.copyWith(fontSize: 34, fontWeight: FontWeight.w700, height: 1.05, letterSpacing: -0.6),
        headlineSmall:
            t.headlineSmall?.copyWith(fontSize: 28, fontWeight: FontWeight.w700, height: 1.1, letterSpacing: -0.4),
        titleLarge: t.titleLarge?.copyWith(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.2),
        titleMedium: t.titleMedium?.copyWith(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 0),
        titleSmall: t.titleSmall?.copyWith(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0),
        bodyLarge: t.bodyLarge?.copyWith(fontSize: 18, height: 1.3),
        bodyMedium: t.bodyMedium?.copyWith(fontSize: 16, height: 1.3),
        bodySmall: t.bodySmall?.copyWith(fontSize: 14, height: 1.3),
        labelLarge: t.labelLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.1),
        labelMedium: t.labelMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 0.1),
        labelSmall: t.labelSmall?.copyWith(fontSize: 13, fontWeight: FontWeight.w500, letterSpacing: 0.1),
      );

  static ThemeData _build(ColorScheme cs, Color bg) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: cs.brightness,
      colorScheme: cs,
      fontFamily: kFont,
      fontFamilyFallback: kFontFallback,
    );
    final text = _textTheme(base.textTheme).apply(bodyColor: cs.onSurface, displayColor: cs.onSurface);

    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c, width: w),
        );

    return base.copyWith(
      scaffoldBackgroundColor: bg,
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: cs.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cs.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        border: border(cs.outlineVariant),
        enabledBorder: border(cs.outlineVariant),
        disabledBorder: border(cs.outlineVariant),
        focusedBorder: border(cs.primary, 2),
        errorBorder: border(cs.error),
        focusedErrorBorder: border(cs.error, 2),
        labelStyle: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        floatingLabelStyle: text.bodyMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.w600),
        hintStyle: text.bodyMedium?.copyWith(color: cs.outline),
        helperStyle: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        errorStyle: text.bodySmall?.copyWith(color: cs.error),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 54),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: text.labelLarge?.copyWith(fontSize: 18),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 54),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          side: BorderSide(color: cs.outline.withAlpha(120)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: text.labelLarge?.copyWith(fontSize: 18),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(64, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: text.labelLarge,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: cs.primaryContainer,
        indicatorShape: const StadiumBorder(),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final on = states.contains(WidgetState.selected);
          return text.labelMedium?.copyWith(
            fontWeight: on ? FontWeight.w700 : FontWeight.w500,
            color: on ? cs.onSurface : cs.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final on = states.contains(WidgetState.selected);
          return IconThemeData(size: 26, color: on ? cs.onPrimaryContainer : cs.onSurfaceVariant);
        }),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: cs.outlineVariant),
        backgroundColor: cs.surface,
        selectedColor: cs.primaryContainer,
        labelStyle: text.labelLarge,
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      ),
      dividerTheme: DividerThemeData(color: cs.outlineVariant, thickness: 1, space: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentTextStyle: text.bodyMedium?.copyWith(color: cs.onInverseSurface),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
      actionIconTheme: ActionIconThemeData(
        backButtonIconBuilder: (_) => const Icon(LucideIcons.arrowLeft),
        closeButtonIconBuilder: (_) => const Icon(LucideIcons.x),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: ZoomPageTransitionsBuilder(allowEnterRouteSnapshotting: false),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.linux: ZoomPageTransitionsBuilder(allowEnterRouteSnapshotting: false),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: ZoomPageTransitionsBuilder(allowEnterRouteSnapshotting: false),
      }),
      dialogTheme: DialogTheme(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: text.titleLarge,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: cs.inverseSurface, borderRadius: BorderRadius.circular(8)),
        textStyle: text.bodySmall?.copyWith(color: cs.onInverseSurface),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
    );
  }
}
