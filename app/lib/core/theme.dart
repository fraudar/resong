// language: Dart, file: lib/core/theme.dart, target: mobile-first + desktop, runtime: resong app
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tokens dinâmicos por tema (Black OLED / Light) acessíveis via `AppColors.of(context)`.
@immutable
class ThemeColors extends ThemeExtension<ThemeColors> {
  const ThemeColors({
    required this.isDark,
    required this.bg,
    required this.bgElevated,
    required this.surface,
    required this.stroke,
    required this.glassFill,
    required this.glassFillStrong,
    required this.glassBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.heroPillBg,
    required this.heroPillFg,
    required this.accent,
    required this.accentAlt,
    required this.danger,
  });

  final bool isDark;
  final Color bg;
  final Color bgElevated;
  final Color surface;
  final Color stroke;
  final Color glassFill;
  final Color glassFillStrong;
  final Color glassBorder;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color heroPillBg;
  final Color heroPillFg;
  final Color accent;
  final Color accentAlt;
  final Color danger;

  static ThemeColors black({Color accent = AppColors.accent}) => ThemeColors(
        isDark: true,
        bg: const Color(0xFF040406),
        bgElevated: const Color(0xFF0D0D12),
        surface: const Color(0xFF16161D),
        stroke: const Color(0x1EFFFFFF),
        glassFill: const Color(0x26FFFFFF),
        glassFillStrong: const Color(0x4012141A),
        glassBorder: const Color(0x2EFFFFFF),
        textPrimary: const Color(0xF5FFFFFF),
        textSecondary: const Color(0xB8FFFFFF),
        textTertiary: const Color(0x75FFFFFF),
        heroPillBg: Colors.white,
        heroPillFg: const Color(0xFF0B0C10),
        accent: accent,
        accentAlt: AppColors.accentAlt,
        danger: AppColors.danger,
      );

  static ThemeColors light({Color accent = AppColors.accent}) => ThemeColors(
        isDark: false,
        bg: const Color(0xFFF4F5F8),
        bgElevated: Colors.white,
        surface: const Color(0xFFE9EBF0),
        stroke: const Color(0x17000000),
        glassFill: const Color(0xA6FFFFFF),
        glassFillStrong: const Color(0xCCFFFFFF),
        glassBorder: const Color(0x24000000),
        textPrimary: const Color(0xFF111218),
        textSecondary: const Color(0xA6111218),
        textTertiary: const Color(0x69111218),
        heroPillBg: const Color(0xFF121319),
        heroPillFg: Colors.white,
        accent: accent,
        accentAlt: const Color(0xFF0E9F7E),
        danger: const Color(0xFFE13A58),
      );

  @override
  ThemeColors copyWith({
    bool? isDark,
    Color? bg,
    Color? bgElevated,
    Color? surface,
    Color? stroke,
    Color? glassFill,
    Color? glassFillStrong,
    Color? glassBorder,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? heroPillBg,
    Color? heroPillFg,
    Color? accent,
    Color? accentAlt,
    Color? danger,
  }) =>
      ThemeColors(
        isDark: isDark ?? this.isDark,
        bg: bg ?? this.bg,
        bgElevated: bgElevated ?? this.bgElevated,
        surface: surface ?? this.surface,
        stroke: stroke ?? this.stroke,
        glassFill: glassFill ?? this.glassFill,
        glassFillStrong: glassFillStrong ?? this.glassFillStrong,
        glassBorder: glassBorder ?? this.glassBorder,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        textTertiary: textTertiary ?? this.textTertiary,
        heroPillBg: heroPillBg ?? this.heroPillBg,
        heroPillFg: heroPillFg ?? this.heroPillFg,
        accent: accent ?? this.accent,
        accentAlt: accentAlt ?? this.accentAlt,
        danger: danger ?? this.danger,
      );

  @override
  ThemeColors lerp(ThemeExtension<ThemeColors>? other, double t) {
    if (other is! ThemeColors) return this;
    return ThemeColors(
      isDark: t < 0.5 ? isDark : other.isDark,
      bg: Color.lerp(bg, other.bg, t)!,
      bgElevated: Color.lerp(bgElevated, other.bgElevated, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      stroke: Color.lerp(stroke, other.stroke, t)!,
      glassFill: Color.lerp(glassFill, other.glassFill, t)!,
      glassFillStrong: Color.lerp(glassFillStrong, other.glassFillStrong, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      heroPillBg: Color.lerp(heroPillBg, other.heroPillBg, t)!,
      heroPillFg: Color.lerp(heroPillFg, other.heroPillFg, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentAlt: Color.lerp(accentAlt, other.accentAlt, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

/// Sistema visual do resong: suporte nativo a Black (OLED profundo) e Light,
/// acento vivo vindo da capa e tipografia Space Grotesk + Inter.
abstract final class AppColors {
  static const bg = Color(0xFF040406);
  static const bgElevated = Color(0xFF0D0D12);
  static const surface = Color(0xFF16161D);
  static const stroke = Color(0x1EFFFFFF);

  static const accent = Color(0xFF7C5CFF);
  static const accentAlt = Color(0xFF22D3A6);
  static const danger = Color(0xFFFF5C7A);

  static const textPrimary = Color(0xF5FFFFFF);
  static const textSecondary = Color(0xB8FFFFFF);
  static const textTertiary = Color(0x75FFFFFF);

  static const scrimTop = Color(0xB3000000);

  static ThemeColors of(BuildContext context) {
    final ext = Theme.of(context).extension<ThemeColors>();
    if (ext != null) return ext;
    return Theme.of(context).brightness == Brightness.dark
        ? ThemeColors.black()
        : ThemeColors.light();
  }
}

extension ResongThemeContext on BuildContext {
  ThemeColors get colors => AppColors.of(this);
}

abstract final class AppTheme {
  static ThemeData dark({Color accent = AppColors.accent}) => _build(
        colors: ThemeColors.black(accent: accent),
        brightness: Brightness.dark,
      );

  static ThemeData black({Color accent = AppColors.accent}) => dark(accent: accent);

  static ThemeData light({Color accent = AppColors.accent}) => _build(
        colors: ThemeColors.light(accent: accent),
        brightness: Brightness.light,
      );

  static ThemeData _build({required ThemeColors colors, required Brightness brightness}) {
    final accent = colors.accent;
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
      primary: accent,
      secondary: accent,
      surface: colors.bgElevated,
      error: colors.danger,
    ).copyWith(
      surface: colors.bg,
      onSurface: colors.textPrimary,
      outline: colors.stroke,
    );

    final base = ThemeData(brightness: brightness, useMaterial3: true, colorScheme: scheme);

    final textTheme = GoogleFonts.interTextTheme(base.textTheme).copyWith(
      displayLarge: GoogleFonts.spaceGrotesk(fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -1.1, height: 1.05, color: colors.textPrimary),
      displayMedium: GoogleFonts.spaceGrotesk(fontSize: 27, fontWeight: FontWeight.w700, letterSpacing: -0.7, height: 1.12, color: colors.textPrimary),
      headlineSmall: GoogleFonts.spaceGrotesk(fontSize: 21, fontWeight: FontWeight.w600, letterSpacing: -0.4, color: colors.textPrimary),
      titleLarge: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: colors.textPrimary),
      titleMedium: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: colors.textPrimary),
      titleSmall: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: colors.textSecondary),
      bodyLarge: TextStyle(fontSize: 15, color: colors.textPrimary, height: 1.35),
      bodyMedium: TextStyle(fontSize: 13.5, color: colors.textSecondary, height: 1.35),
      bodySmall: TextStyle(fontSize: 12, color: colors.textTertiary),
      labelLarge: GoogleFonts.spaceGrotesk(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.1, color: colors.textPrimary),
      labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: colors.textTertiary),
    );

    return base.copyWith(
      scaffoldBackgroundColor: colors.bg,
      textTheme: textTheme,
      extensions: [colors],
      splashFactory: InkSparkle.splashFactory,
      highlightColor: (colors.isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.headlineSmall,
        iconTheme: IconThemeData(color: colors.textPrimary, size: 22),
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: colors.stroke)),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.glassFill,
        hoverColor: Colors.transparent,
        hintStyle: TextStyle(color: colors.textTertiary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: colors.stroke)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: colors.stroke)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colors.textSecondary.withValues(alpha: 0.45), width: 1.0),
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 4.0,
        activeTrackColor: colors.isDark ? Colors.white : colors.textPrimary,
        inactiveTrackColor: (colors.isDark ? Colors.white : Colors.black).withValues(alpha: 0.16),
        thumbColor: colors.isDark ? Colors.white : colors.textPrimary,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        overlayColor: accent.withValues(alpha: 0.16),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.bgElevated,
        contentTextStyle: textTheme.bodyLarge,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: colors.stroke)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.bgElevated,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26), side: BorderSide(color: colors.stroke)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.bgElevated,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colors.textSecondary,
        textColor: colors.textPrimary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: colors.textPrimary,
        unselectedLabelColor: colors.textTertiary,
        indicatorColor: accent,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: Colors.transparent,
        labelStyle: textTheme.labelLarge,
        unselectedLabelStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w500),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
      floatingActionButtonTheme: FloatingActionButtonThemeData(backgroundColor: accent, foregroundColor: Colors.white),
      dividerTheme: DividerThemeData(color: colors.stroke, thickness: 1),
    );
  }
}

/// Degradê que sai da capa e se mescla ao fundo do tema ativo.
Gradient heroGradient(Color tone, {bool top = false, Color? baseBg}) {
  final bg = baseBg ?? AppColors.bg;
  return LinearGradient(
    begin: top ? Alignment.bottomCenter : Alignment.topCenter,
    end: top ? Alignment.topCenter : Alignment.bottomCenter,
    colors: [
      tone.withValues(alpha: top ? 0.0 : 0.78),
      tone.withValues(alpha: top ? 0.52 : 0.36),
      bg.withValues(alpha: 0.96),
      bg,
    ],
    stops: const [0.0, 0.32, 0.76, 1.0],
  );
}

Color mixToward(Color a, Color b, double t) => Color.lerp(a, b, t.clamp(0, 1))!;
