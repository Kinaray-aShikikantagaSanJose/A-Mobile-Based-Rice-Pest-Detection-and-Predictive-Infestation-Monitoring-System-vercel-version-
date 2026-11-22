import 'package:flutter/material.dart';
import '../l10n/app_language.dart';
import '../theme.dart';

/// Palay Patrol brand: name, tagline and logo widgets.

const String kAppName = 'Palay Patrol';
const String kAppTagline =
    'Rice Pest Detection, Infestation Hotspot Monitoring, Treatment Recommendation, and Trend Prediction System';
const String kLogoAsset = 'assets/branding/logo.png';

/// Rice planting photo behind the sign-in header (same as the web dashboard).
const String kFieldPhotoAsset = 'assets/branding/planting_rice.jpg';

/// The logo artwork (transparent PNG): reads on light and dark backgrounds.
class PalayPatrolLogo extends StatelessWidget {
  final double width;

  const PalayPatrolLogo({super.key, required this.width});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      kLogoAsset,
      width: width,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: context.tr('{app} logo', {'app': kAppName}),
      errorBuilder: (context, error, stack) => SizedBox(
        width: width,
        height: width * 0.8,
        child: Icon(Icons.grass_rounded, size: width * 0.5, color: AppColors.brandGold),
      ),
    );
  }
}

/// The logo on a rounded white tile (app-icon style), for headers and
/// sign-in screens on either light or dark backgrounds.
class BrandMark extends StatelessWidget {
  final double size;

  const BrandMark({super.key, this.size = 76});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDeep.withValues(alpha: 0.22),
            blurRadius: size * 0.25,
            offset: Offset(0, size * 0.08),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: PalayPatrolLogo(width: size * 0.8),
    );
  }
}

/// "Palay Patrol" in the leaf-to-lime gradient used on the splash artwork.
class BrandTitle extends StatelessWidget {
  final double fontSize;
  final TextAlign textAlign;

  const BrandTitle({super.key, this.fontSize = 36, this.textAlign = TextAlign.center});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => const LinearGradient(
        colors: [AppColors.brandLeaf, AppColors.brandLime],
      ).createShader(bounds),
      child: Text(
        kAppName,
        textAlign: textAlign,
        maxLines: 1,
        style: TextStyle(
          fontFamily: AppFonts.display,
          color: AppColors.surface,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
          height: 1.15,
        ),
      ),
    );
  }
}

/// "Palay" in [color] and "Patrol" in brand gold, for dark headers.
class BrandWordmark extends StatelessWidget {
  final double fontSize;
  final Color color;

  const BrandWordmark({super.key, this.fontSize = 22, this.color = AppColors.surface});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: AppFonts.display,
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.3,
      height: 1.1,
    );
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: 'Palay ', style: style.copyWith(color: color)),
        TextSpan(text: 'Patrol', style: style.copyWith(color: AppColors.brandGold)),
      ]),
      maxLines: 1,
      semanticsLabel: kAppName,
    );
  }
}
