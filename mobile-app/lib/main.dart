import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_router.dart';
import 'controllers/auth_controller.dart';
import 'l10n/app_language.dart';
import 'platform/local_files.dart';
import 'services/api_client.dart';
import 'services/notification_service.dart';
import 'services/sync_service.dart';
import 'utils/api_config.dart';
import 'theme.dart';
import 'widgets/motion.dart';

List<CameraDescription> cameras = [];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Web: sqflite on SQLite WebAssembly + browser storage for photos.
  // Nothing to do on a phone.
  await initLocalFiles();

  // In a browser, listing cameras asks for camera permission, so it waits
  // until the camera screen opens (see F31CameraUi).
  if (!kIsWeb) {
    try {
      cameras = await availableCameras();
    } on CameraException catch (e) {
      debugPrint('Camera init error: ${e.code} ${e.description}');
    } catch (e) {
      debugPrint('Camera init error (non-camera-specific): $e');
    }
  }

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Language picked on this phone (English, Filipino or Kinaray-a); works
  // offline and before signing in. A new choice is also saved on the account
  // (best effort), so notifications from the server use it too.
  await AppLanguage.instance.load();
  AppLanguage.instance.onPicked = (lang) {
    if (!AuthControllerImpl.instance.isLoggedIn) return;
    ApiClient.put('/auth/me', {'preferred_language': lang.name})
        .then(ApiClient.applyProfile)
        .catchError((Object e) {
      debugPrint('[Lang] not saved on the account yet: $e');
      return null;
    });
  };

  // 1. Grab the singleton instance
  final auth = AuthControllerImpl.instance;

  // 2. Wait for persistent state to load from disk
  await auth.initialize();

  // 3. Keep local API discovery active while the app is open.
  ApiConfig.startMonitoring();

  // 4. Phone notifications (pop-up with sound) for news found while the app runs.
  await NotificationService.instance.init();

  // 5. Upload queued scans whenever the app is open and a signal is back.
  AutoSync.instance.start();

  // 6. Pass it to MyApp
  runApp(MyApp(auth: auth));
}

class MyApp extends StatelessWidget {
  MyApp({super.key, required this.auth});

  final AuthController auth;
  late final AppRouter _appRouter = AppRouter(auth);

  @override
  Widget build(BuildContext context) {
    // LanguageScope rebuilds every screen that uses context.tr when the
    // language changes.
    return LanguageScope(
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        title: 'Palay Patrol',
        theme: buildAppTheme(),
        routerConfig: _appRouter.router,
      ),
    );
  }
}

/// App-wide defaults so screens that use stock Material widgets (dialogs,
/// text fields, snackbars, progress indicators) match the design tokens.
ThemeData buildAppTheme() {
  final OutlineInputBorder border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.sm),
    borderSide: const BorderSide(color: AppColors.border),
  );
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      error: AppColors.danger,
      surface: AppColors.surface,
    ),
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.background,
    textTheme: AppText.theme,
    // One transition for every pushed screen (fade + short slide, like the
    // capture flow). iOS keeps its native swipe-back transition.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: AppPageTransitionsBuilder(),
        TargetPlatform.fuchsia: AppPageTransitionsBuilder(),
        TargetPlatform.windows: AppPageTransitionsBuilder(),
        TargetPlatform.linux: AppPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.primary,
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.primary,
      selectionColor: AppColors.accentLight,
      selectionHandleColor: AppColors.primary,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceMuted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 14),
      labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
      floatingLabelStyle: const TextStyle(color: AppColors.primary),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: border.copyWith(
        borderSide: const BorderSide(color: AppColors.danger),
      ),
      focusedErrorBorder: border.copyWith(
        borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      space: 1,
      thickness: 1,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      titleTextStyle: const TextStyle(
        fontFamily: AppFonts.display,
        color: AppColors.textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
      contentTextStyle: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 14,
        height: 1.45,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.primary),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.primaryDark,
      contentTextStyle: const TextStyle(color: AppColors.surface, fontSize: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: AppColors.surface,
      showDragHandle: true,
      dragHandleColor: AppColors.border,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.surface,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppColors.surface
              : AppColors.textPrimary,
        ),
        side: const WidgetStatePropertyAll(BorderSide(color: AppColors.border)),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      labelStyle: const TextStyle(
        fontFamily: AppFonts.body,
        color: AppColors.textPrimary,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? AppColors.primary
            : Colors.transparent,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surface,
      surfaceTintColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(AppColors.surface),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.primary
            : AppColors.border,
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
  );
}
