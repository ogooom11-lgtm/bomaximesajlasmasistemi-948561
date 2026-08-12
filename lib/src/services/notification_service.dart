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
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const macSettings = DarwinInitializationSettings();
    const linuxSettings = LinuxInitializationSettings(
      defaultActionName: 'فتح KimomeMessage',
    );
    const windowsSettings = WindowsInitializationSettings(
      appName: 'KimomeMessage',
      appUserModelId: 'Kimome.Message.Desktop',
      guid: '9f3f1b48-67c5-4ed8-a514-bd7ef1a9e443',
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      macOS: macSettings,
      linux: linuxSettings,
      windows: windowsSettings,
    );

    await _plugin.initialize(
      settings: initSettings,
    );
  }

  Future<void> showIncomingMessage(TelegramMessage message) async {
    if (!_settings.notificationsEnabled) {
      return;
    }

    const details = NotificationDetails(
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
        subtitle: 'رسالة جديدة',
      ),
    );

    await _plugin.show(
      id: message.id.hashCode & 0x7fffffff,
      title: 'KimomeMessage',
      body: 'لديك رسائل جديدة',
      notificationDetails: details,
    );

    if (_settings.soundsEnabled) {
      await SystemSound.play(SystemSoundType.alert);
    }
  }

  Future<void> clearNotifications() async {
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  Future<void> onChatOpened(int chatId) async {
    // للإشعار العادي لا نحتاج تجميع، هذه الدالة تبقى فارغة للتوافق
  }

  Future<void> showSummaryIfAppOpen(
      {required int totalUnread, required List<String> chatNames}) async {
    // غير مستخدم في الوضع العادي
  }

  Future<void> playSendSound() async {
    if (_settings.soundsEnabled) {
      await SystemSound.play(SystemSoundType.click);
    }
  }
}
