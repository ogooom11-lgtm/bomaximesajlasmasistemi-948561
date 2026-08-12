import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/telegram_models.dart';
import 'settings_store.dart';

class NotificationService {
  NotificationService(this._settings);

  final SettingsStore _settings;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
      macOS: DarwinInitializationSettings(),
      linux: LinuxInitializationSettings(
        defaultActionName: 'فتح KimomeMessage',
      ),
      windows: WindowsInitializationSettings(
        appName: 'KimomeMessage',
        appUserModelId: 'Kimome.Message.Desktop',
        guid: '9f3f1b48-67c5-4ed8-a514-bd7ef1a9e443',
      ),
    );
    await _plugin.initialize(settings: settings);
  }

  Future<void> showIncomingMessage(TelegramMessage message) async {
    if (!_settings.notificationsEnabled) {
      return;
    }
    const title = 'KimomeMessage';
    const body = 'لديك رسائل جديدة';
    await _plugin.show(
      id: message.id.hashCode & 0x7fffffff,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'kimome_messages',
          'رسائل KimomeMessage',
          channelDescription: 'تنبيهات الرسائل الجديدة من بوت تلغرام',
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
        ),
        iOS: DarwinNotificationDetails(presentSound: true),
        macOS: DarwinNotificationDetails(presentSound: true),
        linux: LinuxNotificationDetails(
          urgency: LinuxNotificationUrgency.normal,
          category: LinuxNotificationCategory.imReceived,
        ),
        windows: WindowsNotificationDetails(
          duration: WindowsNotificationDuration.short,
          subtitle: 'رسالة غير مقروءة',
        ),
      ),
    );

    if (_settings.soundsEnabled) {
      await SystemSound.play(SystemSoundType.alert);
    }
  }

  Future<void> playSendSound() async {
    if (_settings.soundsEnabled) {
      await SystemSound.play(SystemSoundType.click);
    }
  }
}
