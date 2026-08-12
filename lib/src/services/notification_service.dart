import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/telegram_models.dart';
import 'settings_store.dart';

class NotificationService {
  NotificationService(this._settings);

  final SettingsStore _settings;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const int _groupedNotificationId = 0;

  int _totalUnread = 0;
  final Map<int, _ChatUnreadInfo> _unreadPerChat = {};
  Timer? _debounceTimer;
  final List<TelegramMessage> _recentMessages = [];

  Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
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
      onDidReceiveNotificationResponse: (response) {
        if (response.actionId == 'clear_action' ||
            response.payload == 'clear') {
          clearNotifications();
        }
      },
    );
  }

  // Called per incoming message from ChatController
  Future<void> showIncomingMessage(TelegramMessage message) async {
    if (!_settings.notificationsEnabled) return;

    _totalUnread++;
    final chatId = message.chat.id;
    final existing = _unreadPerChat[chatId];
    if (existing == null) {
      _unreadPerChat[chatId] = _ChatUnreadInfo(
        chatId: chatId,
        chatTitle: message.chat.displayTitle,
        fromName: message.fromName ?? message.chat.displayTitle,
        count: 1,
        lastMessage: message,
      );
    } else {
      existing.count++;
      existing.fromName = message.fromName ?? existing.fromName;
      existing.lastMessage = message;
    }

    _recentMessages.add(message);
    if (_recentMessages.length > 10) _recentMessages.removeAt(0);

    // Debounce to group rapid messages into one notification
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 1200), () {
      _showGroupedNotification();
    });

    if (_settings.soundsEnabled) {
      await SystemSound.play(SystemSoundType.alert);
    }
  }

  Future<void> _showGroupedNotification() async {
    if (!_settings.notificationsEnabled) return;
    if (_totalUnread == 0) return;

    String title;
    String body;

    if (_unreadPerChat.length == 1) {
      final info = _unreadPerChat.values.first;
      final sender =
          info.chatTitle.isNotEmpty ? info.chatTitle : info.fromName;
      if (info.count == 1) {
        title = sender;
        body = info.lastMessage?.previewText ?? 'رسالة جديدة';
      } else {
        title = sender;
        body = 'لديك ${info.count} رسائل غير مقروءة من $sender';
      }
    } else {
      // Multiple chats
      final totalChats = _unreadPerChat.length;
      final names = _unreadPerChat.values
          .map((e) => e.chatTitle)
          .take(3)
          .join('، ');
      title = 'KimomeMessage';
      if (_totalUnread == 1) {
        body = 'رسالة جديدة من $names';
      } else {
        body =
            'لديك $_totalUnread رسائل غير مقروءة من $totalChats محادثات: $names';
        if (body.length > 120) {
          body =
              'لديك $_totalUnread رسائل غير مقروءة من $totalChats محادثات';
        }
      }
    }

    // Notification details - all non-const to avoid const-expression errors
    final androidDetails = AndroidNotificationDetails(
      'kimome_messages',
      'رسائل KimomeMessage',
      channelDescription: 'تنبيهات الرسائل الجديدة من بوت تلغرام',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      groupKey: 'kimome_group',
      setAsGroupSummary: true,
      actions: const <AndroidNotificationAction>[
        AndroidNotificationAction('clear_action', 'حذف الإشعارات',
            showsUserInterface: false, cancelNotification: true),
      ],
    );

    const darwinDetails = DarwinNotificationDetails(
      presentSound: true,
      categoryIdentifier: 'kimome_category',
    );

    final linuxDetails = LinuxNotificationDetails(
      urgency: LinuxNotificationUrgency.normal,
      category: LinuxNotificationCategory.imReceived,
      actions: const <LinuxNotificationAction>[
        LinuxNotificationAction(
            key: 'clear_action', label: 'حذف الإشعارات'),
      ],
    );

    const windowsDetails = WindowsNotificationDetails(
      duration: WindowsNotificationDuration.short,
      subtitle: 'رسائل غير مقروءة',
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
      linux: linuxDetails,
      windows: windowsDetails,
    );

    await _plugin.show(
      id: _groupedNotificationId,
      title: title,
      body: body,
      notificationDetails: details,
      payload: 'grouped',
    );
  }

  Future<void> showSummaryIfAppOpen(
      {required int totalUnread, required List<String> chatNames}) async {
    if (!_settings.notificationsEnabled) return;
    if (totalUnread == 0) return;

    String title = 'KimomeMessage';
    String body;
    if (totalUnread == 1) {
      body = chatNames.isNotEmpty
          ? 'رسالة غير مقروءة من ${chatNames.first}'
          : 'لديك رسالة غير مقروءة';
    } else {
      if (chatNames.length == 1) {
        body =
            'لديك $totalUnread رسائل غير مقروءة من ${chatNames.first}';
      } else {
        body = 'لديك $totalUnread رسائل غير مقروءة';
      }
    }

    final details = NotificationDetails(
      android: const AndroidNotificationDetails(
        'kimome_messages',
        'رسائل KimomeMessage',
        channelDescription: 'تنبيهات الرسائل الجديدة',
        importance: Importance.low,
        priority: Priority.low,
        groupKey: 'kimome_group',
        setAsGroupSummary: true,
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction('clear_action', 'حذف الإشعارات'),
        ],
      ),
      linux: const LinuxNotificationDetails(
        actions: <LinuxNotificationAction>[
          LinuxNotificationAction(
              key: 'clear_action', label: 'حذف الإشعارات')
        ],
      ),
      windows: const WindowsNotificationDetails(),
    );

    await _plugin.show(
      id: _groupedNotificationId,
      title: title,
      body: body,
      notificationDetails: details,
      payload: 'summary',
    );
  }

  Future<void> clearNotifications() async {
    _totalUnread = 0;
    _unreadPerChat.clear();
    _recentMessages.clear();
    _debounceTimer?.cancel();
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  Future<void> onChatOpened(int chatId) async {
    // When user opens a chat, remove its unread from grouped count
    final removed = _unreadPerChat.remove(chatId);
    if (removed != null) {
      _totalUnread = (_totalUnread - removed.count).clamp(0, 1 << 30);
      if (_totalUnread == 0) {
        await clearNotifications();
      } else {
        await _showGroupedNotification();
      }
    }
  }

  Future<void> playSendSound() async {
    if (_settings.soundsEnabled) {
      await SystemSound.play(SystemSoundType.click);
    }
  }
}

class _ChatUnreadInfo {
  _ChatUnreadInfo({
    required this.chatId,
    required this.chatTitle,
    required this.fromName,
    required this.count,
    this.lastMessage,
  });

  final int chatId;
  final String chatTitle;
  String fromName;
  int count;
  TelegramMessage? lastMessage;
}
