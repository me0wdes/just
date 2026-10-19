import 'package:flutter/material.dart';

/// Tokens from the Figma file "Just" (collection «Just · цвета»), one
/// value per theme. Names follow the Figma variables.
@immutable
class DayColors extends ThemeExtension<DayColors> {
  final Color canvas, screen, card, border, track, pill, input;
  final Color text, muted, icon, done, overdue;
  const DayColors({
    required this.canvas,
    required this.screen,
    required this.card,
    required this.border,
    required this.track,
    required this.pill,
    required this.input,
    required this.text,
    required this.muted,
    required this.icon,
    required this.done,
    required this.overdue,
  });
  static const light = DayColors(
    canvas: Color(0xfff7f7f7),
    screen: Color(0xffffffff),
    card: Color(0xffffffff),
    border: Color(0xffececec),
    track: Color(0xfff5f5f5),
    pill: Color(0xffffffff),
    input: Color(0xfff4f4f4),
    text: Color(0xff141414),
    // AA: 5.3:1 on white, 4.9:1 on track/input.
    muted: Color(0xff6b6b6b),
    // 3.45:1 so the check ring reads as a control (WCAG 1.4.11).
    icon: Color(0xff8a8a8a),
    // White tick keeps 3.6:1 on the fill.
    done: Color(0xff2a9a4c),
    overdue: Color(0xffcf2e2e),
  );
  static const dark = DayColors(
    canvas: Color(0xff0e0e0e),
    screen: Color(0xff161616),
    card: Color(0xff1c1c1c),
    border: Color(0xff2a2a2a),
    track: Color(0xff222222),
    pill: Color(0xff323232),
    input: Color(0xff222222),
    text: Color(0xffededed),
    muted: Color(0xff9a9a9a),
    icon: Color(0xff7e7e7e),
    done: Color(0xff2f9c52),
    overdue: Color(0xffff7b72),
  );

  // Roles used across widgets, mapped onto the Figma tokens.
  Color get raised => track;
  Color get selected => track;
  Color get hover => Color.lerp(card, track, .6)!;
  Color get divider => border;
  Color get accent => done;
  Color get onAccent => const Color(0xffffffff);

  static DayColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<DayColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  DayColors copyWith() => this;
  @override
  DayColors lerp(DayColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return DayColors(
      canvas: l(canvas, other.canvas),
      screen: l(screen, other.screen),
      card: l(card, other.card),
      border: l(border, other.border),
      track: l(track, other.track),
      pill: l(pill, other.pill),
      input: l(input, other.input),
      text: l(text, other.text),
      muted: l(muted, other.muted),
      icon: l(icon, other.icon),
      done: l(done, other.done),
      overdue: l(overdue, other.overdue),
    );
  }
}

ThemeData dayTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final c = dark ? DayColors.dark : DayColors.light;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: c.accent,
        brightness: brightness,
      ).copyWith(
        // Buttons and switches are neutral: ink on paper, paper on ink.
        primary: c.text,
        onPrimary: c.screen,
        surface: c.screen,
        onSurface: c.text,
        onSurfaceVariant: c.muted,
        surfaceContainerHigh: c.raised,
        surfaceContainerHighest: c.selected,
        secondaryContainer: c.selected,
        onSecondaryContainer: c.text,
        outline: c.border,
        outlineVariant: c.divider,
        error: c.overdue,
      );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    splashFactory: NoSplash.splashFactory,
    hoverColor: c.hover,
    highlightColor: Colors.transparent,
    focusColor: c.text.withValues(alpha: .08),
    colorScheme: scheme,
    fontFamily: 'Golos',
    scaffoldBackgroundColor: c.canvas,
    canvasColor: c.screen,
    dividerColor: c.divider,
    extensions: [c],
  );
  final field = OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide(color: c.border),
  );
  return base.copyWith(
    textTheme: base.textTheme
        .copyWith(
          // Just/Заголовок, Just/Дело, Just/Дата, Just/Мета, Just/Вкладка.
          // Just/Заголовок: the wordmark.
          headlineMedium: base.textTheme.headlineMedium?.copyWith(
            fontFamily: 'Instrument Serif',
            fontSize: 40,
            height: 48 / 40,
            fontWeight: FontWeight.w400,
            letterSpacing: -.6,
          ),
          titleMedium: base.textTheme.titleMedium?.copyWith(
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
          // Just/Приветствие: the view title on the header card.
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontSize: 20,
            height: 26 / 20,
            fontWeight: FontWeight.w500,
            letterSpacing: -.2,
          ),
          bodyLarge: base.textTheme.bodyLarge?.copyWith(
            fontSize: 17,
            height: 22 / 17,
            fontWeight: FontWeight.w400,
            letterSpacing: -.085,
          ),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(
            fontSize: 15,
            height: 20 / 15,
          ),
          bodySmall: base.textTheme.bodySmall?.copyWith(
            fontSize: 13,
            height: 18 / 13,
          ),
          labelLarge: base.textTheme.labelLarge?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        )
        .apply(bodyColor: c.text, displayColor: c.text),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.input,
      hintStyle: TextStyle(color: c.muted, fontWeight: FontWeight.w400),
      border: field,
      enabledBorder: field,
      focusedBorder: field.copyWith(
        borderSide: BorderSide(color: c.muted, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(40, 40),
        foregroundColor: c.text,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.text,
        foregroundColor: c.screen,
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        textStyle: const TextStyle(
          fontFamily: 'Golos',
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.text,
        side: BorderSide(color: c.border),
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        textStyle: const TextStyle(
          fontFamily: 'Golos',
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.text,
        textStyle: const TextStyle(
          fontFamily: 'Golos',
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.screen,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: c.border),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.screen,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: c.border),
      ),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: c.canvas,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xff2a2a2a) : const Color(0xff222222),
      contentTextStyle: const TextStyle(
        color: Color(0xffededed),
        fontSize: 14,
        fontFamily: 'Golos',
      ),
      actionTextColor: dark ? const Color(0xff7fb0ff) : const Color(0xff8cb8ff),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      width: 420,
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 500),
      decoration: BoxDecoration(
        color: dark ? const Color(0xff2e2e2e) : const Color(0xff2a2a2a),
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: const TextStyle(
        fontFamily: 'Golos',
        color: Colors.white,
        fontSize: 12,
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: c.text,
      thumbColor: c.text,
      inactiveTrackColor: c.selected,
    ),
    dividerTheme: DividerThemeData(color: c.divider, thickness: 1, space: 1),
    listTileTheme: ListTileThemeData(
      iconColor: c.text,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  );
}
