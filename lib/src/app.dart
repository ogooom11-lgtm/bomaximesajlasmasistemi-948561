import 'package:flutter/material.dart';

import 'services/chat_controller.dart';
import 'services/notification_service.dart';
import 'services/settings_store.dart';
import 'services/sticker_store.dart';
import 'theme/app_theme.dart';
import 'ui/home_shell.dart';

class KimomeMessageApp extends StatelessWidget {
  const KimomeMessageApp({
    super.key,
    required this.settings,
    required this.controller,
    required this.stickerStore,
    required this.notifications,
  });

  final SettingsStore settings;
  final ChatController controller;
  final StickerStore stickerStore;
  final NotificationService notifications;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([settings, stickerStore]),
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'KimomeMessage',
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: settings.darkMode ? ThemeMode.dark : ThemeMode.light,
          builder: (context, child) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: HomeShell(
            settings: settings,
            controller: controller,
            stickerStore: stickerStore,
            notifications: notifications,
          ),
        );
      },
    );
  }
}
