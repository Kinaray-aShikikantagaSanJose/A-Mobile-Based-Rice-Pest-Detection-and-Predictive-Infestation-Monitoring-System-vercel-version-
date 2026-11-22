import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_language.dart';
import '../theme.dart';
import 'motion.dart';

/// Language picker button (translate icon + EN / FIL / KRJ), styled like
/// [AppCircleButton]. [dark] is for the green hero headers.
class LanguageButton extends StatelessWidget {
  final bool dark;
  const LanguageButton({super.key, this.dark = false});

  @override
  Widget build(BuildContext context) {
    final lang = context.lang;
    final fg = dark ? AppColors.surface : AppColors.textPrimary;
    return Tooltip(
      message: context.tr('Language'),
      child: Semantics(
        button: true,
        label: '${context.tr('Language')}: ${lang.label}',
        child: PressScale(
          scale: 0.92,
          child: Material(
            color: dark ? Colors.white.withValues(alpha: 0.12) : AppColors.surface,
            shape: StadiumBorder(
              side: BorderSide(color: dark ? Colors.white.withValues(alpha: 0.18) : AppColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const ValueKey('language-button'),
              onTap: () => showLanguagePicker(context),
              child: SizedBox(
                height: 42,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.translate_rounded, size: 19, color: fg),
                      const SizedBox(width: 5),
                      Text(lang.short, style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet with the three languages. The choice applies at once and is
/// kept on the phone (and on the account once signed in).
Future<void> showLanguagePicker(BuildContext context) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.hPad, 0, AppSpacing.hPad, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              ctx.tr('Choose your language'),
              style: const TextStyle(fontFamily: AppFonts.display, fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.md),
            for (final l in AppLang.values)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _LanguageOption(
                  lang: l,
                  selected: ctx.lang == l,
                  onTap: () {
                    AppLanguage.instance.pick(l);
                    Navigator.of(ctx).pop();
                  },
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _LanguageOption extends StatelessWidget {
  final AppLang lang;
  final bool selected;
  final VoidCallback onTap;
  const _LanguageOption({required this.lang, required this.selected, required this.onTap});

  static const Map<AppLang, String> _hint = {
    AppLang.en: 'English',
    AppLang.fil: 'Tagalog / Filipino',
    AppLang.krj: 'Karay-a (Antique)',
  };

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.accentLight : AppColors.surfaceMuted,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('language-${lang.name}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Text(
                  lang.short,
                  style: TextStyle(
                    color: selected ? AppColors.surface : AppColors.textSecondary,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(lang.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                    Text(_hint[lang]!, style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                  ],
                ),
              ),
              if (selected) const Icon(Icons.check_circle_rounded, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}
