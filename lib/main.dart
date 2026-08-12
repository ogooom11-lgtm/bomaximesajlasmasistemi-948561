import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'src/app.dart';
import 'src/services/app_instance_service.dart';
import 'src/services/chat_controller.dart';
import 'src/services/notification_service.dart';
import 'src/services/settings_store.dart';
import 'src/services/sticker_store.dart';
import 'src/services/tray_lifecycle_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final trayLifecycle = TrayLifecycleService.instance;
  final appInstance = AppInstanceService.instance;
  appInstance.onSecondInstanceRequested = trayLifecycle.showFromTray;
  final isPrimaryInstance = await appInstance.activateOrClaim();
  if (!isPrimaryInstance) {
    return;
  }

  MediaKit.ensureInitialized();
  await trayLifecycle.initialize();

  final settings = SettingsStore();
  await settings.load();

  final stickerStore = StickerStore();
  await stickerStore.load();

  final notifications = NotificationService(settings);
  await notifications.initialize();

  final controller = ChatController(
    settings: settings,
    notifications: notifications,
    stickerStore: stickerStore,
  );
  await controller.bootstrap();

  runApp(KimomeMessageApp(
    settings: settings,
    controller: controller,
    stickerStore: stickerStore,
    notifications: notifications,
  ));
}
