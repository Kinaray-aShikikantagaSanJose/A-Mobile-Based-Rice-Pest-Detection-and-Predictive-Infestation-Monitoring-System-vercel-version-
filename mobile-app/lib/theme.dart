import 'package:flutter/material.dart';

class AppColors {
  /// Deepest surfaces (text on gold, dark accents). Teal-leaning so nothing
  /// reads as a flat dark green; large areas use the gradients below.
  static const Color primaryDeep = Color(0xFF0B3D36);
  static const Color primaryDark = Color(0xFF125E4C);
  static const Color primary = Color(0xFF1B7F53);
  static const Color primaryBright = Color(0xFF2BB673);

  /// Gradient stops (see kHeroGradient / kPrimaryGradient).
  static const Color teal = Color(0xFF0E7C78);
  static const Color emerald = Color(0xFF1FA06B);
  static const Color lime = Color(0xFF7CC245);

  /// Sage canvas: white cards stand out from it (the old cream washed out).
  static const Color background = Color(0xFFEBF0E8);
  static const Color surface = Color(0xFFFFFFFF);

  /// Inputs and panels inside cards.
  static const Color surfaceMuted = Color(0xFFF3F6F1);
  static const Color border = Color(0xFFD9E1D4);
  static const Color textPrimary = Color(0xFF13251B);
  static const Color textSecondary = Color(0xFF4A5A4E);
  static const Color textMuted = Color(0xFF6B7A6E);
  static const Color danger = Color(0xFFE63946);
  static const Color accentLight = Color(0xFFD8F3DC);
  static const Color orange = Color(0xFFE67E22);
  static const Color orangeLight = Color(0xFFFDF2E9);
  static const Color success = Color(0xFF10B981);
  static const Color purple = Color(0xFF7C3AED);
  static const Color sky = Color(0xFF0EA5E9);

  // Palay Patrol brand (sampled from the logo artwork).
  static const Color brandGreen = Color(0xFF015615);
  static const Color brandLeaf = Color(0xFF64A450);
  static const Color brandLime = Color(0xFF9CC054);
  static const Color brandTagline = Color(0xFFBCCC50);
  static const Color brandGold = Color(0xFFE0B409);
  static const Color goldLight = Color(0xFFFFF4CC);
}

/// Teal -> emerald -> leaf gradient behind hero headers (home, profile, results).
const LinearGradient kHeroGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [AppColors.teal, AppColors.emerald, AppColors.lime],
  stops: [0, 0.6, 1],
);

/// Primary buttons, the Scan button and selected states.
const LinearGradient kPrimaryGradient = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [AppColors.emerald, AppColors.teal],
);

/// Soft tint for selected pills and highlighted panels.
LinearGradient tintGradient(Color a, Color b, [double alpha = 0.16]) => LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [a.withValues(alpha: alpha), b.withValues(alpha: alpha)],
    );

class AppShadows {
  /// Resting cards.
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x14102A1C), blurRadius: 16, offset: Offset(0, 6)),
    BoxShadow(color: Color(0x0A102A1C), blurRadius: 2, offset: Offset(0, 1)),
  ];

  /// Floating elements (bottom bar, scan button).
  static const List<BoxShadow> raised = [
    BoxShadow(color: Color(0x26102A1C), blurRadius: 24, offset: Offset(0, 8)),
  ];
}

class AppSpacing {
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;
  static const double hPad = 20.0;
}

class AppRadius {
  static const double xs = 6.0;
  static const double sm = 12.0;
  static const double md = 18.0;
  static const double lg = 26.0;
  static const double pill = 100.0;
}

/// Motion tokens shared by every screen (see lib/widgets/motion.dart).
class AppMotion {
  /// Press feedback, chip toggles.
  static const Duration fast = Duration(milliseconds: 140);
  /// State swaps (loading -> content, filter / tab / month changes).
  static const Duration medium = Duration(milliseconds: 260);
  /// Page transitions.
  static const Duration page = Duration(milliseconds: 320);
  /// One item's entrance (fade + rise).
  static const Duration entrance = Duration(milliseconds: 420);
  /// Delay between consecutive items in a staggered entrance.
  static const Duration stagger = Duration(milliseconds: 45);
  /// Number count-ups and progress fills.
  static const Duration countUp = Duration(milliseconds: 800);
  /// Items after this index appear without a stagger delay.
  static const int maxStagger = 8;
  static const Curve curve = Curves.easeOutCubic;
}

class AppFonts {
  static const String display = 'Bricolage Grotesque';
  static const String body = 'DM Sans';
}

class AppText {
  static const TextTheme theme = TextTheme(
    bodyMedium: TextStyle(fontFamily: AppFonts.body, color: AppColors.textPrimary),
    bodyLarge: TextStyle(fontFamily: AppFonts.body, color: AppColors.textPrimary),
    titleLarge: TextStyle(
      fontFamily: AppFonts.display,
      color: AppColors.textPrimary,
      fontWeight: FontWeight.bold,
    ),
    headlineSmall: TextStyle(
      fontFamily: AppFonts.display,
      color: AppColors.textPrimary,
      fontWeight: FontWeight.bold,
    ),
  );
}

Color severityColor(String severity) {
  switch (severity.toUpperCase()) {
    case 'HIGH':
      return AppColors.danger;
    case 'MEDIUM':
      return AppColors.orange;
    default:
      return AppColors.primary;
  }
}
