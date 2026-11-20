import 'package:flutter/material.dart';

import '../controllers/auth_controller.dart';
import '../platform/local_files.dart';
import '../services/api_client.dart';
import '../theme.dart';

String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2);
  final s = parts.map((p) => p[0].toUpperCase()).join();
  return s.isEmpty ? '?' : s;
}

/// The signed-in person's round profile picture, or their initials on a
/// gradient. Rebuilds when the session changes (new picture, new name).
/// [preview] shows a local file instead (a picture being uploaded; on the
/// web a `blob:` URL).
class UserAvatar extends StatelessWidget {
  final double size;
  final bool onDark;
  final String? preview;

  const UserAvatar({super.key, this.size = 48, this.onDark = false, this.preview});

  @override
  Widget build(BuildContext context) {
    final auth = AuthControllerImpl.instance;
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        final s = auth.session;
        final url = ApiClient.avatarUrl(s?.avatarUrl);
        final Widget initials = Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: onDark
                ? const LinearGradient(colors: [AppColors.brandGold, Color(0xFFF5D66B)])
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.lime, AppColors.emerald, AppColors.teal],
                  ),
          ),
          child: Text(
            initialsOf(s?.name ?? ''),
            style: TextStyle(
              color: onDark ? AppColors.primaryDeep : Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: size * 0.34,
            ),
          ),
        );
        Widget picture = initials;
        if (preview != null) {
          picture = localImage(preview!, fit: BoxFit.cover);
        } else if (url != null) {
          picture = Image.network(
            url,
            headers: ApiClient.currentHeaders,
            fit: BoxFit.cover,
            cacheWidth: (size * 3).round(),
            // Offline or not reachable: the initials, not a broken image.
            errorBuilder: (_, _, _) => initials,
            loadingBuilder: (context, child, progress) => progress == null ? child : initials,
          );
        }
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: onDark ? Colors.white.withValues(alpha: 0.45) : Colors.white,
              width: size >= 80 ? 4 : 2,
            ),
            boxShadow: size >= 80 ? AppShadows.raised : null,
          ),
          child: ClipOval(child: picture),
        );
      },
    );
  }
}
