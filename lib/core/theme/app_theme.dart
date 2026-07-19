import 'package:flutter/material.dart';

enum AppThemeId {
  obsidianBlack,
  graphite,
  midnightIndigo,
  nordicLight,
  warmPaper,
}

@immutable
final class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.background,
    required this.surface,
    required this.elevatedSurface,
    required this.primaryText,
    required this.secondaryText,
    required this.accent,
    required this.success,
    required this.warning,
    required this.danger,
    required this.border,
    required this.focusRing,
    required this.shadow,
    this.radius = 6,
    this.spacing = 6,
    this.animationDuration = const Duration(milliseconds: 140),
  });

  final Color background;
  final Color surface;
  final Color elevatedSurface;
  final Color primaryText;
  final Color secondaryText;
  final Color accent;
  final Color success;
  final Color warning;
  final Color danger;
  final Color border;
  final Color focusRing;
  final Color shadow;
  final double radius;
  final double spacing;
  final Duration animationDuration;

  AppTokens reducedMotion(bool enabled) =>
      enabled ? copyWith(animationDuration: Duration.zero) : this;

  @override
  AppTokens copyWith({
    Color? background,
    Color? surface,
    Color? elevatedSurface,
    Color? primaryText,
    Color? secondaryText,
    Color? accent,
    Color? success,
    Color? warning,
    Color? danger,
    Color? border,
    Color? focusRing,
    Color? shadow,
    double? radius,
    double? spacing,
    Duration? animationDuration,
  }) => AppTokens(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    elevatedSurface: elevatedSurface ?? this.elevatedSurface,
    primaryText: primaryText ?? this.primaryText,
    secondaryText: secondaryText ?? this.secondaryText,
    accent: accent ?? this.accent,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    danger: danger ?? this.danger,
    border: border ?? this.border,
    focusRing: focusRing ?? this.focusRing,
    shadow: shadow ?? this.shadow,
    radius: radius ?? this.radius,
    spacing: spacing ?? this.spacing,
    animationDuration: animationDuration ?? this.animationDuration,
  );

  @override
  AppTokens lerp(covariant AppTokens? other, double t) => other == null
      ? this
      : t < .5
      ? this
      : other;
}

const appThemeTokens = <AppThemeId, AppTokens>{
  AppThemeId.obsidianBlack: AppTokens(
    background: Color(0xFF08090A),
    surface: Color(0xFF111315),
    elevatedSurface: Color(0xFF191C1F),
    primaryText: Color(0xFFF4F5F6),
    secondaryText: Color(0xFFA5ABB2),
    accent: Color(0xFF8B7CFF),
    success: Color(0xFF58C99A),
    warning: Color(0xFFE3B45B),
    danger: Color(0xFFE87575),
    border: Color(0xFF2B2F34),
    focusRing: Color(0xFFA89DFF),
    shadow: Color(0x99000000),
  ),
  AppThemeId.graphite: AppTokens(
    background: Color(0xFF151719),
    surface: Color(0xFF1E2124),
    elevatedSurface: Color(0xFF292D31),
    primaryText: Color(0xFFF1F2F3),
    secondaryText: Color(0xFFB1B5BA),
    accent: Color(0xFF67A7F5),
    success: Color(0xFF61C99C),
    warning: Color(0xFFE6B85C),
    danger: Color(0xFFE77A7A),
    border: Color(0xFF383D42),
    focusRing: Color(0xFF91C1FA),
    shadow: Color(0x80000000),
  ),
  AppThemeId.midnightIndigo: AppTokens(
    background: Color(0xFF0B0C1B),
    surface: Color(0xFF14162B),
    elevatedSurface: Color(0xFF1D2040),
    primaryText: Color(0xFFF2F1FF),
    secondaryText: Color(0xFFAAA9C7),
    accent: Color(0xFF8F86FF),
    success: Color(0xFF55CAA5),
    warning: Color(0xFFE5B76C),
    danger: Color(0xFFEA777F),
    border: Color(0xFF30345B),
    focusRing: Color(0xFFB0AAFF),
    shadow: Color(0x99000014),
  ),
  AppThemeId.nordicLight: AppTokens(
    background: Color(0xFFF3F6F7),
    surface: Color(0xFFFFFFFF),
    elevatedSurface: Color(0xFFE8EEF0),
    primaryText: Color(0xFF172024),
    secondaryText: Color(0xFF58666D),
    accent: Color(0xFF386E87),
    success: Color(0xFF287B5E),
    warning: Color(0xFF9A681B),
    danger: Color(0xFFA74242),
    border: Color(0xFFC9D3D7),
    focusRing: Color(0xFF245C75),
    shadow: Color(0x260C252F),
  ),
  AppThemeId.warmPaper: AppTokens(
    background: Color(0xFFF5F0E6),
    surface: Color(0xFFFFFBF3),
    elevatedSurface: Color(0xFFEDE5D7),
    primaryText: Color(0xFF2D2822),
    secondaryText: Color(0xFF71675B),
    accent: Color(0xFF9B5D3D),
    success: Color(0xFF477658),
    warning: Color(0xFF93651D),
    danger: Color(0xFFA4483F),
    border: Color(0xFFD8CCBC),
    focusRing: Color(0xFF80492F),
    shadow: Color(0x2E3F2E1C),
  ),
};

ThemeData buildAppTheme(AppThemeId id, {bool reducedMotion = false}) {
  final tokens = appThemeTokens[id]!.reducedMotion(reducedMotion);
  final brightness = id == AppThemeId.nordicLight || id == AppThemeId.warmPaper
      ? Brightness.light
      : Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: tokens.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: tokens.accent,
      brightness: brightness,
      surface: tokens.surface,
      error: tokens.danger,
    ),
    cardTheme: CardThemeData(
      color: tokens.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: tokens.border),
        borderRadius: BorderRadius.circular(tokens.radius),
      ),
    ),
    dividerColor: tokens.border,
    splashFactory: NoSplash.splashFactory,
    visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
    textTheme: ThemeData(brightness: brightness).textTheme.apply(
      bodyColor: tokens.primaryText,
      displayColor: tokens.primaryText,
      fontFamily: 'Segoe UI',
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: tokens.surface,
      indicatorColor: tokens.accent.withValues(alpha: .16),
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius),
      ),
      minWidth: 52,
      minExtendedWidth: 176,
      labelType: NavigationRailLabelType.none,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tokens.elevatedSurface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.radius),
        borderSide: BorderSide(color: tokens.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.radius),
        borderSide: BorderSide(color: tokens.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(tokens.radius),
        borderSide: BorderSide(color: tokens.focusRing, width: 1.5),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      dense: true,
      minVerticalPadding: 4,
      contentPadding: EdgeInsets.symmetric(horizontal: 10),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: tokens.elevatedSurface,
      elevation: 16,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius),
        side: BorderSide(color: tokens.border),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: tokens.elevatedSurface,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radius),
        side: BorderSide(color: tokens.border),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: tokens.elevatedSurface,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(4),
      ),
      textStyle: TextStyle(color: tokens.primaryText, fontSize: 12),
    ),
    focusColor: tokens.focusRing,
    extensions: [tokens],
  );
}
