import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class AppInstanceService {
  AppInstanceService._();

  static final AppInstanceService instance = AppInstanceService._();

  static const int _port = 49387;
  static const String _showCommand = 'show';

  RandomAccessFile? _lockFile;
  ServerSocket? _server;

  Future<void> Function()? onSecondInstanceRequested;

  Future<bool> activateOrClaim() async {
    if (kIsWeb ||
        !(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return true;
    }

    final lock = await _openLockFile();
    try {
      await lock.lock(FileLock.exclusive);
      _lockFile = lock;
    } on FileSystemException {
      await lock.close();
      await _notifyPrimaryInstance();
      return false;
    }

    await _startActivationServer();
    return true;
  }

  Future<RandomAccessFile> _openLockFile() async {
    final path =
        '${Directory.systemTemp.path}${Platform.pathSeparator}kimomesage.instance.lock';
    final file = File(path);
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    return file.open(mode: FileMode.write);
  }

  Future<void> _startActivationServer() async {
    try {
      _server = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        _port,
        shared: false,
      );
      _server!.listen((client) => unawaited(_handleActivation(client)));
    } on SocketException {
      // The file lock is the source of truth. If the port is busy, the first
      // instance still stays unique; only second-launch focus is unavailable.
    }
  }

  Future<void> _handleActivation(Socket client) async {
    try {
      final command = await utf8.decoder
          .bind(client)
          .join()
          .timeout(const Duration(milliseconds: 700), onTimeout: () => '');
      if (command.trim() == _showCommand) {
        final callback = onSecondInstanceRequested;
        if (callback != null) {
          await callback();
        }
      }
    } finally {
      client.destroy();
    }
  }

  Future<void> _notifyPrimaryInstance() async {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        _port,
        timeout: const Duration(milliseconds: 700),
      );
      socket.write('$_showCommand\n');
      await socket.flush();
      socket.destroy();
    } on SocketException {
      // The primary instance may be an older build or still starting.
    } on TimeoutException {
      // Keep the second instance closed even when activation cannot be sent.
    }
  }

  Future<void> dispose() async {
    await _server?.close();
    _server = null;
    await _lockFile?.unlock();
    await _lockFile?.close();
    _lockFile = null;
  }
}
