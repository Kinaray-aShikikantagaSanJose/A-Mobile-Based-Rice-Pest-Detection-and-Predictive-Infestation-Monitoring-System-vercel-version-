import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'strings.dart';

/// App languages. The English text is the key: `context.tr('Records')` looks
/// it up in lib/l10n/parts/*.dart and falls back to the English text, so a
/// missing translation never shows a blank.
///
///   en  - English
///   fil - Filipino (simple, everyday words)
///   krj - Kinaray-a / Karay-a as spoken in Antique (ISO 639-3 "krj")
///
/// Placeholders: `context.tr('{n} observations', {'n': 3})`.
enum AppLang {
  en('English', 'EN'),
  fil('Filipino', 'FIL'),
  krj('Kinaray-a', 'KRJ');

  const AppLang(this.label, this.short);

  /// Name shown in the language picker (always in that language).
  final String label;

  /// Short code shown on the language button.
  final String short;

  static AppLang? fromCode(String? code) {
    for (final l in AppLang.values) {
      if (l.name == (code ?? '').trim().toLowerCase()) return l;
    }
    return null;
  }
}

/// The current language. Kept on the phone (works offline and before
/// signing in) and, once signed in, saved on the account too.
class AppLanguage extends ChangeNotifier {
  AppLanguage._();
  static final AppLanguage instance = AppLanguage._();

  static const String _kLang = 'appLanguage';

  AppLang _lang = AppLang.en;
  bool _chosen = false;

  AppLang get lang => _lang;
  String get code => _lang.name;

  /// True once the person picked a language on this phone. Until then the
  /// language saved on their account (if any) is used after signing in.
  bool get chosenOnThisDevice => _chosen;

  /// Called after the person picks a language (main.dart saves it on the account).
  void Function(AppLang lang)? onPicked;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = AppLang.fromCode(prefs.getString(_kLang));
      if (saved != null) {
        _lang = saved;
        _chosen = true;
      }
    } catch (e) {
      debugPrint('[Lang] could not read the saved language: $e');
    }
    notifyListeners();
  }

  /// The person picked [lang] (language button, profile).
  Future<void> pick(AppLang lang) async {
    _chosen = true;
    final changed = lang != _lang;
    _lang = lang;
    if (changed) notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLang, lang.name);
    } catch (e) {
      debugPrint('[Lang] could not save the language: $e');
    }
    onPicked?.call(lang);
  }

  /// The language saved on the account (after sign-in). Used only when the
  /// person never picked one on this phone, so a choice made here wins.
  void adoptAccountLanguage(String? code) {
    final l = AppLang.fromCode(code);
    if (l == null || _chosen || l == _lang) return;
    _lang = l;
    notifyListeners();
  }
}

String _fill(String text, Map<String, Object?>? vars) {
  if (vars == null || vars.isEmpty) return text;
  return text.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) {
    final v = vars[m.group(1)];
    return v == null ? m.group(0)! : '$v';
  });
}

String _translate(String text, Map<String, Object?>? vars, AppLang lang) {
  if (lang == AppLang.en) return _fill(text, vars);
  final entry = kStrings[text];
  return _fill(entry?[lang.name] ?? text, vars);
}

/// Translates English [text] into the current language. For code without a
/// BuildContext (services, models). In widgets use `context.tr(...)`, which
/// also rebuilds the widget when the language changes.
String tr(String text, [Map<String, Object?>? vars]) => _translate(text, vars, AppLanguage.instance.lang);

extension TrContext on BuildContext {
  /// Translated [text]; the widget rebuilds when the language changes.
  String tr(String text, [Map<String, Object?>? vars]) {
    final scope = dependOnInheritedWidgetOfExactType<LanguageScope>();
    return _translate(text, vars, scope?.notifier?.lang ?? AppLanguage.instance.lang);
  }

  AppLang get lang {
    final scope = dependOnInheritedWidgetOfExactType<LanguageScope>();
    return scope?.notifier?.lang ?? AppLanguage.instance.lang;
  }
}

/// Put above MaterialApp: widgets using `context.tr` rebuild on a change.
class LanguageScope extends InheritedNotifier<AppLanguage> {
  LanguageScope({super.key, required super.child}) : super(notifier: AppLanguage.instance);
}
