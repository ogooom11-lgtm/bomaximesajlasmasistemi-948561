import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'app_instance_service.dart';

class TrayLifecycleService with WindowListener, TrayListener {
  TrayLifecycleService._();

  static final TrayLifecycleService instance = TrayLifecycleService._();

  factory TrayLifecycleService() => instance;

  bool _initialized = false;

  Future<void> initialize() async {
    if (!_isSupported || _initialized) {
      return;
    }
    _initialized = true;

    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(title: 'KimomeMessage', minimumSize: Size(920, 640)),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );

    await trayManager.setIcon('assets/branding/kimome_icon.png');
    await trayManager.setToolTip('KimomeMessage يعمل في الخلفية');
    await trayManager.setContextMenu(
      Menu(
        items: <MenuItem>[
          MenuItem(key: 'show', label: 'إظهار النافذة'),
          MenuItem.separator(),
          MenuItem(key: 'quit', label: 'إغلاق التطبيق'),
        ],
      ),
    );
    trayManager.addListener(this);
  }

  @override
  void onWindowClose() async {
    if (await windowManager.isPreventClose()) {
      await _hideToTray();
    }
  }

  @override
  void onWindowMinimize() async {
    await _hideToTray();
  }

  @override
  void onTrayIconMouseDown() {
    showFromTray();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        showFromTray();
        break;
      case 'quit':
        quit();
        break;
    }
  }

  Future<void> _hideToTray() async {
    await windowManager.setSkipTaskbar(true);
    await windowManager.hide();
  }

  Future<void> showFromTray() async {
    if (!_isSupported) {
      return;
    }
    await windowManager.ensureInitialized();
    await windowManager.setSkipTaskbar(false);
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> quit() async {
    if (!_isSupported) {
      return;
    }
    await windowManager.setPreventClose(false);
    await trayManager.destroy();
    await AppInstanceService.instance.dispose();
    await windowManager.destroy();
  }

  bool get _isSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
}
