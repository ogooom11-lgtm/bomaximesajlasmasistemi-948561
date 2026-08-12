import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:lottie/lottie.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/telegram_models.dart';
import '../services/chat_controller.dart';
import '../services/settings_store.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.settings,
    required this.controller,
  });

  final SettingsStore settings;
  final ChatController controller;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late bool _unlocked;

  @override
  void initState() {
    super.initState();
    _unlocked = !widget.settings.hasPassword;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        widget.settings,
        widget.controller,
      ]),
      builder: (context, _) {
        if (widget.settings.hasPassword && !_unlocked) {
          return LockScreen(
            settings: widget.settings,
            onUnlocked: () => setState(() => _unlocked = true),
          );
        }

        final needsSetup =
            !widget.settings.hasBotToken &&
            widget.controller.bot == null &&
            !widget.controller.isConnecting;
        return Scaffold(
          body: SafeArea(
            child: needsSetup
                ? SetupView(
                    controller: widget.controller,
                    settings: widget.settings,
                  )
                : ChatWorkspace(
                    settings: widget.settings,
                    controller: widget.controller,
                    onLock: widget.settings.hasPassword
                        ? () => setState(() => _unlocked = false)
                        : null,
                  ),
          ),
        );
      },
    );
  }
}

class LockScreen extends StatefulWidget {
  const LockScreen({
    super.key,
    required this.settings,
    required this.onUnlocked,
  });

  final SettingsStore settings;
  final VoidCallback onUnlocked;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _password = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _unlock() {
    if (widget.settings.verifyPassword(_password.text)) {
      widget.onUnlocked();
      return;
    }
    setState(() => _error = 'كلمة المرور غير صحيحة.');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const Center(child: AppLogo(size: 76)),
                const SizedBox(height: 22),
                Text(
                  'KimomeMessage مقفل',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'أدخل كلمة المرور لعرض محادثات البوت.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _password,
                  obscureText: true,
                  autofocus: true,
                  onSubmitted: (_) => _unlock(),
                  decoration: InputDecoration(
                    labelText: 'كلمة المرور',
                    prefixIcon: const Icon(Icons.lock_outline),
                    errorText: _error,
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _unlock,
                  icon: const Icon(Icons.lock_open),
                  label: const Text('فتح التطبيق'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SetupView extends StatefulWidget {
  const SetupView({
    super.key,
    required this.controller,
    required this.settings,
  });

  final ChatController controller;
  final SettingsStore settings;

  @override
  State<SetupView> createState() => _SetupViewState();
}

class _SetupViewState extends State<SetupView> {
  late final TextEditingController _token;
  late final TextEditingController _chatId;
  late final TextEditingController _apiBaseUrl;

  @override
  void initState() {
    super.initState();
    _token = TextEditingController(text: widget.settings.botToken);
    _chatId = TextEditingController(
      text: widget.settings.preferredChatId?.toString() ?? '',
    );
    _apiBaseUrl = TextEditingController(text: widget.settings.apiBaseUrl);
  }

  @override
  void dispose() {
    _token.dispose();
    _chatId.dispose();
    _apiBaseUrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    await widget.controller.connect(
      token: _token.text,
      apiBaseUrl: _apiBaseUrl.text,
      preferredChatId: int.tryParse(_chatId.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Center(child: AppLogo(size: 84)),
              const SizedBox(height: 22),
              Text(
                'KimomeMessage',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'اربط التطبيق ببوت تلغرام لقراءة الرسائل وإرسال النصوص والوسائط والملفات.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _token,
                textDirection: TextDirection.ltr,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Telegram Bot Token',
                  prefixIcon: Icon(Icons.key),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _chatId,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Chat ID اختياري للإرسال المباشر',
                  prefixIcon: Icon(Icons.tag),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _apiBaseUrl,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'Bot API Server URL',
                  prefixIcon: Icon(Icons.dns_outlined),
                ),
              ),
              const SizedBox(height: 18),
              if (widget.controller.lastError != null) ...<Widget>[
                ErrorBanner(
                  message: widget.controller.lastError!,
                  onClose: widget.controller.clearError,
                ),
                const SizedBox(height: 12),
              ],
              FilledButton.icon(
                onPressed: widget.controller.isConnecting ? null : _connect,
                icon: widget.controller.isConnecting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.link),
                label: Text(
                  widget.controller.isConnecting
                      ? 'جاري الاتصال...'
                      : 'ربط البوت',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChatWorkspace extends StatelessWidget {
  const ChatWorkspace({
    super.key,
    required this.settings,
    required this.controller,
    this.onLock,
  });

  final SettingsStore settings;
  final ChatController controller;
  final VoidCallback? onLock;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 880;
        if (!wide && controller.selectedChatId != null) {
          return ConversationPane(
            controller: controller,
            settings: settings,
            compact: true,
            onBack: controller.clearSelection,
            onSettings: () => showSettingsDialog(context, controller, settings),
          );
        }
        return Row(
          children: <Widget>[
            SizedBox(
              width: wide ? 340 : constraints.maxWidth,
              child: ChatSidebar(
                controller: controller,
                settings: settings,
                onSettings: () =>
                    showSettingsDialog(context, controller, settings),
                onLock: onLock,
              ),
            ),
            if (wide) ...<Widget>[
              const VerticalDivider(width: 1),
              Expanded(
                child: ConversationPane(
                  controller: controller,
                  settings: settings,
                  compact: false,
                  onSettings: () =>
                      showSettingsDialog(context, controller, settings),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class ChatSidebar extends StatefulWidget {
  const ChatSidebar({
    super.key,
    required this.controller,
    required this.settings,
    required this.onSettings,
    this.onLock,
  });

  final ChatController controller;
  final SettingsStore settings;
  final VoidCallback onSettings;
  final VoidCallback? onLock;

  @override
  State<ChatSidebar> createState() => _ChatSidebarState();
}

class _ChatSidebarState extends State<ChatSidebar> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final query = _search.text.trim().toLowerCase();
    final chats = widget.controller.chatSummaries.where((summary) {
      final title = displayChatTitle(widget.settings, summary.chat);
      if (query.isEmpty) {
        return true;
      }
      return title.toLowerCase().contains(query) ||
          (summary.lastMessage?.previewText.toLowerCase().contains(query) ??
              false);
    }).toList();

    return Material(
      color: scheme.surface,
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: <Widget>[
                const AppLogo(size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'KimomeMessage',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      Text(
                        widget.controller.bot?.username.isNotEmpty == true
                            ? '@${widget.controller.bot!.username}'
                            : 'غير متصل',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: widget.controller.isConnected
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Tooltip(
                  message: 'إضافة محادثة',
                  child: IconButton(
                    onPressed: () =>
                        showAddChatDialog(context, widget.controller),
                    icon: const Icon(Icons.add_comment),
                  ),
                ),
                Tooltip(
                  message: widget.settings.darkMode ? 'وضع فاتح' : 'وضع داكن',
                  child: IconButton(
                    onPressed: () =>
                        widget.settings.setDarkMode(!widget.settings.darkMode),
                    icon: Icon(
                      widget.settings.darkMode
                          ? Icons.light_mode
                          : Icons.dark_mode,
                    ),
                  ),
                ),
                Tooltip(
                  message: 'الإعدادات',
                  child: IconButton(
                    onPressed: widget.onSettings,
                    icon: const Icon(Icons.tune),
                  ),
                ),
                if (widget.onLock != null)
                  Tooltip(
                    message: 'قفل',
                    child: IconButton(
                      onPressed: widget.onLock,
                      icon: const Icon(Icons.lock),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'بحث في المحادثات',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          if (widget.controller.lastError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: ErrorBanner(
                message: widget.controller.lastError!,
                onClose: widget.controller.clearError,
              ),
            ),
          Expanded(
            child: chats.isEmpty
                ? EmptyPanel(
                    icon: Icons.forum_outlined,
                    title: 'بانتظار أول محادثة',
                    subtitle: 'عندما يرسل أحدهم للبوت ستظهر المحادثة هنا.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                    itemCount: chats.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final summary = chats[index];
                      return ChatTile(
                        summary: summary,
                        settings: widget.settings,
                        selected:
                            summary.chat.id == widget.controller.selectedChatId,
                        onTap: () =>
                            widget.controller.selectChat(summary.chat.id),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: <Widget>[
                Icon(
                  widget.controller.isPolling
                      ? Icons.sync
                      : Icons.sync_disabled,
                  size: 18,
                  color: widget.controller.isPolling
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.controller.isPolling
                        ? 'يستقبل الرسائل في الخلفية'
                        : 'الاتصال متوقف',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ChatTile extends StatelessWidget {
  const ChatTile({
    super.key,
    required this.summary,
    required this.settings,
    required this.selected,
    required this.onTap,
  });

  final ChatSummary summary;
  final SettingsStore settings;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = summary.lastMessage;
    final title = displayChatTitle(settings, summary.chat);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: selected
            ? scheme.primaryContainer.withValues(alpha: 0.72)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected
              ? scheme.primary.withValues(alpha: 0.34)
              : Colors.transparent,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        leading: CircleAvatar(
          backgroundColor: selected
              ? scheme.primary
              : scheme.surfaceContainerHighest,
          foregroundColor: selected
              ? scheme.onPrimary
              : scheme.onSurfaceVariant,
          child: Text(title.characters.first.toUpperCase()),
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          last?.previewText ?? 'جاهزة للإرسال',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            if (last != null)
              Text(
                intl.DateFormat('HH:mm').format(last.date),
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            if (summary.unreadCount > 0) ...<Widget>[
              const SizedBox(height: 5),
              Badge(label: Text(summary.unreadCount.toString())),
            ],
          ],
        ),
      ),
    );
  }
}

class ConversationPane extends StatefulWidget {
  const ConversationPane({
    super.key,
    required this.controller,
    required this.settings,
    required this.compact,
    required this.onSettings,
    this.onBack,
  });

  final ChatController controller;
  final SettingsStore settings;
  final bool compact;
  final VoidCallback onSettings;
  final VoidCallback? onBack;

  @override
  State<ConversationPane> createState() => _ConversationPaneState();
}

class _ConversationPaneState extends State<ConversationPane> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  TelegramMessage? _replyTo;
  int _lastMessageCount = 0;

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ConversationPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleScroll();
  }

  void _scheduleScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) {
        return;
      }
      final max = _scroll.position.maxScrollExtent;
      _scroll.animateTo(
        max,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _send() async {
    final text = _composer.text;
    if (text.trim().isEmpty) {
      return;
    }
    _composer.clear();
    final replyId = _replyTo?.messageId;
    setState(() => _replyTo = null);
    await widget.controller.sendText(text, replyToMessageId: replyId);
    _scheduleScroll();
  }

  Future<void> _pickFiles(MessageFileMode mode) async {
    final picker = switch (mode) {
      MessageFileMode.photo => (FileType.image, null),
      MessageFileMode.video => (FileType.video, null),
      MessageFileMode.audio || MessageFileMode.voice => (FileType.audio, null),
      MessageFileMode.sticker => (
        FileType.custom,
        <String>['webp', 'tgs', 'webm'],
      ),
      MessageFileMode.animation => (
        FileType.custom,
        <String>['gif', 'mp4', 'webm'],
      ),
      MessageFileMode.auto || MessageFileMode.document => (FileType.any, null),
    };
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      type: picker.$1,
      allowedExtensions: picker.$2,
    );
    final paths = result?.files
        .map((file) => file.path)
        .whereType<String>()
        .toList();
    if (paths == null || paths.isEmpty) {
      return;
    }
    final caption = _composer.text.trim().isEmpty
        ? null
        : _composer.text.trim();
    _composer.clear();
    final replyId = _replyTo?.messageId;
    setState(() => _replyTo = null);
    await widget.controller.sendFiles(
      paths,
      mode: mode,
      caption: caption,
      replyToMessageId: replyId,
    );
    _scheduleScroll();
  }

  Future<void> _toggleRecording() async {
    if (widget.controller.isRecording) {
      await widget.controller.stopVoiceRecordingAndSend();
    } else {
      await widget.controller.startVoiceRecording();
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.controller.selectedChat;
    final messages = widget.controller.selectedMessages;
    if (messages.length != _lastMessageCount) {
      _lastMessageCount = messages.length;
      _scheduleScroll();
    }

    if (chat == null) {
      return EmptyPanel(
        icon: Icons.mark_chat_unread_outlined,
        title: 'اختر محادثة',
        subtitle: 'حدد محادثة من القائمة أو أضف Chat ID من الإعدادات.',
      );
    }

    return Column(
      children: <Widget>[
        ConversationHeader(
          chat: chat,
          settings: widget.settings,
          compact: widget.compact,
          onBack: widget.onBack,
          onRefresh: widget.controller.refreshNow,
          onSettings: widget.onSettings,
        ),
        const Divider(height: 1),
        Expanded(
          child: ChatCanvas(
            child: messages.isEmpty
                ? EmptyPanel(
                    icon: Icons.chat_bubble_outline,
                    title: 'لا توجد رسائل بعد',
                    subtitle: 'اكتب رسالة أو أرسل ملفاً لبدء المحادثة.',
                  )
                : Scrollbar(
                    controller: _scroll,
                    child: ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[index];
                        return MessageBubble(
                          message: message,
                          controller: widget.controller,
                          onReply: () => setState(() => _replyTo = message),
                          onEdit: () => showEditDialog(
                            context,
                            widget.controller,
                            message,
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ),
        MessageComposer(
          controller: _composer,
          replyTo: _replyTo,
          isRecording: widget.controller.isRecording,
          onCancelReply: () => setState(() => _replyTo = null),
          onCancelRecording: widget.controller.cancelVoiceRecording,
          onSend: _send,
          onToggleRecording: _toggleRecording,
          onPickFiles: _pickFiles,
        ),
      ],
    );
  }
}

class ChatCanvas extends StatelessWidget {
  const ChatCanvas({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return CustomPaint(
      painter: _ChatCanvasPainter(
        base: dark ? const Color(0xFF0E1516) : const Color(0xFFEFF5F1),
        line: dark
            ? Colors.white.withValues(alpha: 0.018)
            : Colors.black.withValues(alpha: 0.026),
      ),
      child: child,
    );
  }
}

class _ChatCanvasPainter extends CustomPainter {
  const _ChatCanvasPainter({required this.base, required this.line});

  final Color base;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    final paint = Paint()
      ..color = line
      ..strokeWidth = 1;
    const spacing = 42.0;
    for (double x = -size.height; x < size.width; x += spacing) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height, size.height),
        paint,
      );
    }
    for (double x = 0; x < size.width + size.height; x += spacing) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x - size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ChatCanvasPainter oldDelegate) {
    return oldDelegate.base != base || oldDelegate.line != line;
  }
}

class ConversationHeader extends StatelessWidget {
  const ConversationHeader({
    super.key,
    required this.chat,
    required this.settings,
    required this.compact,
    required this.onRefresh,
    required this.onSettings,
    this.onBack,
  });

  final TelegramChat chat;
  final SettingsStore settings;
  final bool compact;
  final VoidCallback? onBack;
  final VoidCallback onRefresh;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = displayChatTitle(settings, chat);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: <Widget>[
          if (compact)
            IconButton(
              tooltip: 'رجوع',
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
            ),
          CircleAvatar(
            backgroundColor: scheme.primaryContainer,
            foregroundColor: scheme.onPrimaryContainer,
            child: Text(title.characters.first.toUpperCase()),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Chat ID: ${chat.id}',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Tooltip(
            message: 'تحديث',
            child: IconButton(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
            ),
          ),
          Tooltip(
            message: 'تسمية المحادثة',
            child: IconButton(
              onPressed: () => showRenameChatDialog(context, settings, chat),
              icon: const Icon(Icons.edit_note),
            ),
          ),
          Tooltip(
            message: 'الإعدادات',
            child: IconButton(
              onPressed: onSettings,
              icon: const Icon(Icons.tune),
            ),
          ),
        ],
      ),
    );
  }
}

class MessageComposer extends StatelessWidget {
  const MessageComposer({
    super.key,
    required this.controller,
    required this.replyTo,
    required this.isRecording,
    required this.onCancelReply,
    required this.onCancelRecording,
    required this.onSend,
    required this.onToggleRecording,
    required this.onPickFiles,
  });

  final TextEditingController controller;
  final TelegramMessage? replyTo;
  final bool isRecording;
  final VoidCallback onCancelReply;
  final Future<void> Function() onCancelRecording;
  final Future<void> Function() onSend;
  final Future<void> Function() onToggleRecording;
  final Future<void> Function(MessageFileMode mode) onPickFiles;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: replyTo == null
                  ? const SizedBox.shrink()
                  : Container(
                      key: ValueKey(replyTo!.id),
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer.withValues(
                          alpha: 0.55,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: <Widget>[
                          const Icon(Icons.reply, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              replyTo!.previewText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            tooltip: 'إلغاء الرد',
                            onPressed: onCancelReply,
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                AttachmentMenu(onPickFiles: onPickFiles),
                const SizedBox(width: 8),
                EmojiButton(
                  onEmoji: (emoji) {
                    final value = controller.text;
                    final selection = controller.selection;
                    final start = selection.isValid
                        ? selection.start
                        : value.length;
                    final end = selection.isValid
                        ? selection.end
                        : value.length;
                    controller.text = value.replaceRange(start, end, emoji);
                    controller.selection = TextSelection.collapsed(
                      offset: start + emoji.length,
                    );
                  },
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: isRecording ? 'إيقاف وإرسال التسجيل' : 'تسجيل صوت',
                  child: IconButton.filledTonal(
                    onPressed: onToggleRecording,
                    icon: Icon(isRecording ? Icons.stop : Icons.mic),
                    color: isRecording ? scheme.error : null,
                  ),
                ),
                if (isRecording) ...<Widget>[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'إلغاء التسجيل',
                    child: IconButton(
                      onPressed: onCancelRecording,
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 7,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: 'اكتب رسالة...',
                      alignLabelWithHint: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: onSend,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    padding: EdgeInsets.zero,
                  ),
                  child: const Icon(Icons.send),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class AttachmentMenu extends StatelessWidget {
  const AttachmentMenu({super.key, required this.onPickFiles});

  final Future<void> Function(MessageFileMode mode) onPickFiles;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<MessageFileMode>(
      tooltip: 'إرفاق',
      icon: const Icon(Icons.attach_file),
      onSelected: onPickFiles,
      itemBuilder: (context) => const <PopupMenuEntry<MessageFileMode>>[
        PopupMenuItem(
          value: MessageFileMode.document,
          child: ListTile(leading: Icon(Icons.description), title: Text('ملف')),
        ),
        PopupMenuItem(
          value: MessageFileMode.photo,
          child: ListTile(leading: Icon(Icons.image), title: Text('صورة')),
        ),
        PopupMenuItem(
          value: MessageFileMode.video,
          child: ListTile(leading: Icon(Icons.movie), title: Text('فيديو')),
        ),
        PopupMenuItem(
          value: MessageFileMode.audio,
          child: ListTile(leading: Icon(Icons.graphic_eq), title: Text('صوت')),
        ),
        PopupMenuItem(
          value: MessageFileMode.sticker,
          child: ListTile(
            leading: Icon(Icons.emoji_emotions),
            title: Text('ملصق'),
          ),
        ),
        PopupMenuItem(
          value: MessageFileMode.animation,
          child: ListTile(
            leading: Icon(Icons.gif_box),
            title: Text('GIF / Animation'),
          ),
        ),
      ],
    );
  }
}

class EmojiButton extends StatelessWidget {
  const EmojiButton({super.key, required this.onEmoji});

  final ValueChanged<String> onEmoji;

  @override
  Widget build(BuildContext context) {
    const emojis = <String>['👍', '❤️', '😂', '🔥', '👏', '🙏', '😍', '✅'];
    return PopupMenuButton<String>(
      tooltip: 'إيموجي',
      icon: const Icon(Icons.mood),
      onSelected: onEmoji,
      itemBuilder: (context) => emojis
          .map(
            (emoji) => PopupMenuItem<String>(
              value: emoji,
              child: Text(emoji, style: const TextStyle(fontSize: 22)),
            ),
          )
          .toList(),
    );
  }
}

class MessageBubble extends StatefulWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.controller,
    required this.onReply,
    required this.onEdit,
  });

  final TelegramMessage message;
  final ChatController controller;
  final VoidCallback onReply;
  final VoidCallback onEdit;

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final message = widget.message;
    final outgoing = message.isOutgoing;
    final color = outgoing
        ? (scheme.brightness == Brightness.dark
              ? const Color(0xFF174D47)
              : const Color(0xFFD7F7E8))
        : (scheme.brightness == Brightness.dark
              ? const Color(0xFF1B2325)
              : Colors.white);
    final textColor = outgoing ? scheme.onPrimaryContainer : scheme.onSurface;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxBubbleWidth = math.min(screenWidth * 0.68, 560.0);
    final body = message.text ?? message.caption;
    final url = extractFirstUrl(body ?? '');

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - value)),
            child: child,
          ),
        );
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: Align(
          alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              textDirection: outgoing ? TextDirection.rtl : TextDirection.ltr,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: 72,
                    maxWidth: maxBubbleWidth,
                  ),
                  child: IntrinsicWidth(
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 7),
                      decoration: BoxDecoration(
                        color: color,
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(14),
                          topRight: const Radius.circular(14),
                          bottomLeft: Radius.circular(outgoing ? 14 : 4),
                          bottomRight: Radius.circular(outgoing ? 4 : 14),
                        ),
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.48),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          if (!outgoing) ...<Widget>[
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: maxBubbleWidth - 24,
                              ),
                              child: Text(
                                message.fromName ?? message.chat.displayTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: scheme.primary,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(height: 3),
                          ],
                          if (message.replyToMessageId != null) ...<Widget>[
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: scheme.surface.withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(8),
                                border: Border(
                                  right: BorderSide(
                                    color: scheme.secondary,
                                    width: 3,
                                  ),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 6,
                                ),
                                child: Text(
                                  'رد على رسالة #${message.replyToMessageId}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: textColor.withValues(alpha: 0.72),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                          ],
                          if (message.attachments.isNotEmpty)
                            ...message.attachments.map(
                              (attachment) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: AttachmentPreview(
                                  message: message,
                                  attachment: attachment,
                                  controller: widget.controller,
                                  maxWidth: maxBubbleWidth - 24,
                                ),
                              ),
                            ),
                          if (body != null &&
                              body.trim().isNotEmpty) ...<Widget>[
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: maxBubbleWidth - 24,
                              ),
                              child: SelectableText(
                                body,
                                style: TextStyle(
                                  color: textColor,
                                  height: 1.34,
                                  fontSize: 14.5,
                                ),
                              ),
                            ),
                          ],
                          if (url != null) ...<Widget>[
                            const SizedBox(height: 8),
                            LinkPreviewCard(
                              url: url,
                              maxWidth: maxBubbleWidth - 24,
                            ),
                          ],
                          const SizedBox(height: 5),
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(
                                  _statusIcon(message.delivery),
                                  size: 13,
                                  color: textColor.withValues(alpha: 0.56),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _statusLabel(message.delivery),
                                  style: TextStyle(
                                    color: textColor.withValues(alpha: 0.56),
                                    fontSize: 10.5,
                                  ),
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  intl.DateFormat('HH:mm').format(message.date),
                                  style: TextStyle(
                                    color: textColor.withValues(alpha: 0.56),
                                    fontSize: 10.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (message.reactions.isNotEmpty) ...<Widget>[
                            const SizedBox(height: 5),
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: ReactionStrip(
                                reactions: message.reactions,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                MessageActionRail(
                  emphasized: _hovering,
                  message: message,
                  controller: widget.controller,
                  onReply: widget.onReply,
                  onEdit: widget.onEdit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _statusIcon(MessageDelivery delivery) {
    return switch (delivery) {
      MessageDelivery.sending => Icons.schedule,
      MessageDelivery.failed => Icons.error_outline,
      MessageDelivery.sent => Icons.done_all,
      MessageDelivery.edited => Icons.edit,
      MessageDelivery.deleted => Icons.delete_outline,
      MessageDelivery.received => Icons.done,
    };
  }

  String _statusLabel(MessageDelivery delivery) {
    return switch (delivery) {
      MessageDelivery.sending => 'جار الإرسال',
      MessageDelivery.failed => 'فشل',
      MessageDelivery.sent => 'مرسلة',
      MessageDelivery.edited => 'معدلة',
      MessageDelivery.deleted => 'محذوفة',
      MessageDelivery.received => 'واردة',
    };
  }
}

class MessageActionRail extends StatelessWidget {
  const MessageActionRail({
    super.key,
    required this.emphasized,
    required this.message,
    required this.controller,
    required this.onReply,
    required this.onEdit,
  });

  final bool emphasized;
  final TelegramMessage message;
  final ChatController controller;
  final VoidCallback onReply;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedScale(
      duration: const Duration(milliseconds: 150),
      scale: emphasized ? 1.03 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: emphasized
                ? scheme.primary.withValues(alpha: 0.42)
                : scheme.outlineVariant,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Tooltip(
                message: 'رد',
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: onReply,
                  icon: const Icon(Icons.reply, size: 18),
                ),
              ),
              QuickReactionButton(message: message, controller: controller),
              MessageActions(
                message: message,
                controller: controller,
                onReply: onReply,
                onEdit: onEdit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class QuickReactionButton extends StatelessWidget {
  const QuickReactionButton({
    super.key,
    required this.message,
    required this.controller,
  });

  final TelegramMessage message;
  final ChatController controller;

  @override
  Widget build(BuildContext context) {
    const reactions = <String>['👍', '❤️', '😂', '🔥', '👏', '😍'];
    return PopupMenuButton<String>(
      tooltip: 'تفاعل',
      icon: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          const Icon(Icons.add_reaction_outlined, size: 18),
          if (message.reactions.isNotEmpty)
            Positioned(
              left: -5,
              bottom: -5,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(1),
                  child: Text(
                    message.reactions.length == 1
                        ? message.reactions.values.first
                        : message.reactions.length.toString(),
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ),
            ),
        ],
      ),
      onSelected: (emoji) => controller.setReaction(message, emoji),
      itemBuilder: (context) => reactions
          .map(
            (emoji) => PopupMenuItem(
              value: emoji,
              child: Text(emoji, style: const TextStyle(fontSize: 22)),
            ),
          )
          .toList(),
    );
  }
}

class ReactionStrip extends StatelessWidget {
  const ReactionStrip({super.key, required this.reactions});

  final Map<String, String> reactions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: reactions.entries
          .map((entry) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: scheme.primary.withValues(alpha: 0.28),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(entry.value, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 5),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Text(
                      entry.key,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            );
          })
          .toList(growable: false),
    );
  }
}

class MessageActions extends StatelessWidget {
  const MessageActions({
    super.key,
    required this.message,
    required this.controller,
    required this.onReply,
    required this.onEdit,
  });

  final TelegramMessage message;
  final ChatController controller;
  final VoidCallback onReply;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    const reactions = <String>['👍', '❤️', '😂', '🔥', '👏'];
    return PopupMenuButton<String>(
      tooltip: 'خيارات الرسالة',
      icon: const Icon(Icons.more_horiz, size: 18),
      onSelected: (value) async {
        if (value == 'reply') {
          onReply();
        } else if (value == 'edit') {
          onEdit();
        } else if (value == 'delete') {
          final confirmed = await confirmDelete(context);
          if (confirmed) {
            await controller.deleteMessage(message);
          }
        } else if (value.startsWith('react:')) {
          await controller.setReaction(message, value.substring(6));
        }
      },
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        const PopupMenuItem(
          value: 'reply',
          child: ListTile(leading: Icon(Icons.reply), title: Text('رد')),
        ),
        if (message.canEdit)
          const PopupMenuItem(
            value: 'edit',
            child: ListTile(leading: Icon(Icons.edit), title: Text('تعديل')),
          ),
        if (message.canDelete)
          const PopupMenuItem(
            value: 'delete',
            child: ListTile(
              leading: Icon(Icons.delete_outline),
              title: Text('حذف لدى الجميع'),
            ),
          ),
        const PopupMenuDivider(),
        ...reactions.map(
          (emoji) => PopupMenuItem(
            value: 'react:$emoji',
            child: Text(emoji, style: const TextStyle(fontSize: 22)),
          ),
        ),
      ],
    );
  }
}

class AttachmentPreview extends StatefulWidget {
  const AttachmentPreview({
    super.key,
    required this.message,
    required this.attachment,
    required this.controller,
    required this.maxWidth,
  });

  final TelegramMessage message;
  final TelegramAttachment attachment;
  final ChatController controller;
  final double maxWidth;

  @override
  State<AttachmentPreview> createState() => _AttachmentPreviewState();
}

class _AttachmentPreviewState extends State<AttachmentPreview> {
  bool _busy = false;
  bool _saving = false;

  bool get _isImageLike =>
      widget.attachment.kind == AttachmentKind.photo ||
      widget.attachment.kind == AttachmentKind.sticker &&
          !widget.attachment.isVideoSticker ||
      widget.attachment.kind == AttachmentKind.animation &&
          _extension(widget.attachment.fileName).toLowerCase() == 'gif';

  bool get _isVideoLike =>
      widget.attachment.kind == AttachmentKind.video ||
      widget.attachment.kind == AttachmentKind.videoNote ||
      widget.attachment.kind == AttachmentKind.sticker &&
          widget.attachment.isVideoSticker ||
      widget.attachment.kind == AttachmentKind.animation &&
          _extension(widget.attachment.fileName).toLowerCase() != 'gif';

  bool get _isAudioLike =>
      widget.attachment.kind == AttachmentKind.audio ||
      widget.attachment.kind == AttachmentKind.voice;

  bool get _shouldAutoCache => _isImageLike || _isVideoLike || _isAudioLike;

  @override
  void initState() {
    super.initState();
    if (_shouldAutoCache &&
        widget.attachment.canDownload &&
        widget.attachment.localPath == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _download());
    }
  }

  @override
  void didUpdateWidget(covariant AttachmentPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.attachment.localPath != oldWidget.attachment.localPath) {
      _busy = false;
    }
  }

  Future<void> _download() async {
    if (_busy || widget.attachment.localPath != null) {
      return;
    }
    if (!widget.attachment.canDownload) {
      return;
    }
    setState(() => _busy = true);
    await widget.controller.downloadAttachment(
      widget.message,
      widget.attachment,
    );
    if (mounted) {
      setState(() => _busy = false);
    }
  }

  Future<void> _saveToDevice() async {
    if (_saving || !widget.attachment.canDownload) {
      return;
    }
    final targetPath = await FilePicker.saveFile(
      dialogTitle: 'حفظ المرفق',
      fileName: widget.attachment.fileName ?? 'telegram_file',
      lockParentWindow: true,
    );
    if (targetPath == null || targetPath.trim().isEmpty) {
      return;
    }
    setState(() => _saving = true);
    await widget.controller.saveAttachmentToPath(
      widget.message,
      widget.attachment,
      targetPath,
    );
    if (mounted) {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = widget.attachment.localPath;
    late final Widget preview;
    if (_isImageLike) {
      preview = _ImagePreview(
        attachment: widget.attachment,
        path: path,
        busy: _busy,
        maxWidth: widget.maxWidth,
        onDownload: _download,
      );
    } else if (_isVideoLike) {
      preview = _VideoPreview(
        attachment: widget.attachment,
        path: path,
        busy: _busy,
        maxWidth: widget.maxWidth,
        onDownload: _download,
      );
    } else if (_isAudioLike) {
      preview = _AudioPreview(
        attachment: widget.attachment,
        path: path,
        busy: _busy,
        maxWidth: widget.maxWidth,
        onDownload: _download,
      );
    } else {
      preview = AttachmentTile(
        message: widget.message,
        attachment: widget.attachment,
        controller: widget.controller,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        preview,
        if (widget.attachment.canDownload) ...<Widget>[
          const SizedBox(height: 5),
          TextButton.icon(
            onPressed: _saving ? null : _saveToDevice,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_alt),
            label: Text(_saving ? 'جاري الحفظ...' : 'حفظ باسم...'),
          ),
        ],
      ],
    );
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({
    required this.attachment,
    required this.path,
    required this.busy,
    required this.maxWidth,
    required this.onDownload,
  });

  final TelegramAttachment attachment;
  final String? path;
  final bool busy;
  final double maxWidth;
  final Future<void> Function() onDownload;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final resolved = path;
    final width = math.min(
      maxWidth,
      attachment.kind == AttachmentKind.sticker ? 180.0 : 360.0,
    );
    if (resolved != null && File(resolved).existsSync()) {
      if (attachment.isAnimatedSticker ||
          _extension(attachment.fileName) == 'tgs') {
        return _AnimatedStickerPreview(path: resolved, width: width);
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(resolved),
          width: width,
          fit: BoxFit.cover,
          errorBuilder: (context, _, __) => _MediaPlaceholder(
            icon: Icons.broken_image_outlined,
            label: attachment.label,
            busy: false,
            onPressed: onDownload,
          ),
        ),
      );
    }
    return _MediaPlaceholder(
      icon: Icons.image,
      label: busy ? 'تحميل الصورة...' : attachment.label,
      busy: busy,
      color: scheme.primary,
      onPressed: onDownload,
    );
  }
}

class _AnimatedStickerPreview extends StatelessWidget {
  const _AnimatedStickerPreview({required this.path, required this.width});

  final String path;
  final double width;

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    try {
      final decoded = gzip.decode(file.readAsBytesSync());
      return SizedBox(
        width: width,
        height: width,
        child: Lottie.memory(
          Uint8List.fromList(decoded),
          repeat: true,
          animate: true,
          fit: BoxFit.contain,
        ),
      );
    } catch (_) {
      return _MediaPlaceholder(
        icon: Icons.emoji_emotions,
        label: 'تعذر تشغيل الملصق المتحرك',
        busy: false,
        onPressed: () async {},
      );
    }
  }
}

class _VideoPreview extends StatelessWidget {
  const _VideoPreview({
    required this.attachment,
    required this.path,
    required this.busy,
    required this.maxWidth,
    required this.onDownload,
  });

  final TelegramAttachment attachment;
  final String? path;
  final bool busy;
  final double maxWidth;
  final Future<void> Function() onDownload;

  @override
  Widget build(BuildContext context) {
    final resolved = path;
    if (resolved != null && File(resolved).existsSync()) {
      return InlineVideoPlayer(
        path: resolved,
        width: math.min(maxWidth, 420.0),
      );
    }
    return _MediaPlaceholder(
      icon: Icons.play_circle_outline,
      label: busy ? 'تحميل الفيديو...' : '${attachment.label} · اضغط للتشغيل',
      busy: busy,
      onPressed: onDownload,
    );
  }
}

class _AudioPreview extends StatelessWidget {
  const _AudioPreview({
    required this.attachment,
    required this.path,
    required this.busy,
    required this.maxWidth,
    required this.onDownload,
  });

  final TelegramAttachment attachment;
  final String? path;
  final bool busy;
  final double maxWidth;
  final Future<void> Function() onDownload;

  @override
  Widget build(BuildContext context) {
    final resolved = path;
    if (resolved != null && File(resolved).existsSync()) {
      return InlineAudioPlayer(
        path: resolved,
        label: attachment.label,
        width: math.min(maxWidth, 360.0),
      );
    }
    return _MediaPlaceholder(
      icon: Icons.graphic_eq,
      label: busy ? 'تحميل الصوت...' : '${attachment.label} · تشغيل',
      busy: busy,
      onPressed: onDownload,
    );
  }
}

class _MediaPlaceholder extends StatelessWidget {
  const _MediaPlaceholder({
    required this.icon,
    required this.label,
    required this.busy,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String label;
  final bool busy;
  final Future<void> Function() onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: busy ? null : onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 340),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (busy)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(icon, color: color ?? scheme.primary),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class InlineVideoPlayer extends StatefulWidget {
  const InlineVideoPlayer({super.key, this.path, this.url, required this.width})
    : assert(path != null || url != null);

  final String? path;
  final String? url;
  final double width;

  @override
  State<InlineVideoPlayer> createState() => _InlineVideoPlayerState();
}

class _InlineVideoPlayerState extends State<InlineVideoPlayer> {
  late final Player _player;
  late final VideoController _controller;
  OverlayEntry? _pipEntry;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _player.open(Media(_mediaSource), play: false);
  }

  @override
  void didUpdateWidget(covariant InlineVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path || oldWidget.url != widget.url) {
      _player.open(Media(_mediaSource), play: false);
    }
  }

  @override
  void dispose() {
    _pipEntry?.remove();
    _player.dispose();
    super.dispose();
  }

  void _openPictureInPicture() {
    if (_pipEntry != null) {
      return;
    }
    final overlay = Overlay.of(context);
    _pipEntry = OverlayEntry(
      builder: (context) => MiniVideoOverlay(
        source: _mediaSource,
        onClose: () {
          _pipEntry?.remove();
          _pipEntry = null;
        },
      ),
    );
    overlay.insert(_pipEntry!);
  }

  String get _mediaSource => widget.url ?? Uri.file(widget.path!).toString();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: widget.width,
        height: math.min(widget.width * 0.62, 260.0),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Video(controller: _controller),
            Positioned(
              top: 8,
              left: 8,
              child: Tooltip(
                message: 'صورة داخل صورة',
                child: IconButton.filledTonal(
                  onPressed: _openPictureInPicture,
                  icon: const Icon(Icons.picture_in_picture_alt),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MiniVideoOverlay extends StatefulWidget {
  const MiniVideoOverlay({
    super.key,
    required this.source,
    required this.onClose,
  });

  final String source;
  final VoidCallback onClose;

  @override
  State<MiniVideoOverlay> createState() => _MiniVideoOverlayState();
}

class _MiniVideoOverlayState extends State<MiniVideoOverlay> {
  late final Player _player;
  late final VideoController _controller;
  Offset _offset = const Offset(28, 28);

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _player.open(Media(widget.source));
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = math.min(360.0, size.width * 0.44);
    final height = width * 0.62;
    return Positioned(
      left: _offset.dx,
      bottom: _offset.dy,
      child: Material(
        elevation: 16,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: width,
          height: height + 38,
          child: Column(
            children: <Widget>[
              GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    _offset = Offset(
                      (_offset.dx + details.delta.dx).clamp(
                        8.0,
                        size.width - width - 8,
                      ),
                      (_offset.dy - details.delta.dy).clamp(
                        8.0,
                        size.height - height - 46,
                      ),
                    );
                  });
                },
                child: Container(
                  height: 38,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.drag_indicator, size: 18),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text(
                          'صورة داخل صورة',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: 'إغلاق',
                        onPressed: widget.onClose,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(child: Video(controller: _controller)),
            ],
          ),
        ),
      ),
    );
  }
}

class InlineAudioPlayer extends StatefulWidget {
  const InlineAudioPlayer({
    super.key,
    required this.path,
    required this.label,
    required this.width,
  });

  final String path;
  final String label;
  final double width;

  @override
  State<InlineAudioPlayer> createState() => _InlineAudioPlayerState();
}

class _InlineAudioPlayerState extends State<InlineAudioPlayer> {
  late final Player _player;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _player.open(Media(Uri.file(widget.path).toString()), play: false);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: widget.width,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          StreamBuilder<bool>(
            stream: _player.stream.playing,
            initialData: _player.state.playing,
            builder: (context, snapshot) {
              final playing = snapshot.data ?? false;
              return IconButton.filledTonal(
                onPressed: _player.playOrPause,
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
              );
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                StreamBuilder<Duration>(
                  stream: _player.stream.position,
                  initialData: Duration.zero,
                  builder: (context, snapshot) {
                    final position = snapshot.data ?? Duration.zero;
                    return Text(
                      _formatDuration(position),
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AttachmentTile extends StatefulWidget {
  const AttachmentTile({
    super.key,
    required this.message,
    required this.attachment,
    required this.controller,
  });

  final TelegramMessage message;
  final TelegramAttachment attachment;
  final ChatController controller;

  @override
  State<AttachmentTile> createState() => _AttachmentTileState();
}

class _AttachmentTileState extends State<AttachmentTile> {
  bool _busy = false;

  Future<void> _downloadOrOpen() async {
    setState(() => _busy = true);
    await widget.controller.openAttachment(widget.message, widget.attachment);
    if (mounted) {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final local =
        widget.attachment.localPath != null &&
        widget.attachment.localPath!.isNotEmpty;
    return Container(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.64),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(_attachmentIcon(widget.attachment.kind), color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  widget.attachment.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (widget.attachment.sizeLabel.isNotEmpty)
                  Text(
                    widget.attachment.sizeLabel,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (widget.attachment.canDownload)
            IconButton(
              tooltip: local ? 'فتح' : 'تنزيل',
              onPressed: _busy ? null : _downloadOrOpen,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(local ? Icons.open_in_new : Icons.download),
            ),
        ],
      ),
    );
  }

  IconData _attachmentIcon(AttachmentKind kind) {
    return switch (kind) {
      AttachmentKind.photo => Icons.image,
      AttachmentKind.document => Icons.description,
      AttachmentKind.video => Icons.movie,
      AttachmentKind.audio => Icons.graphic_eq,
      AttachmentKind.voice => Icons.mic,
      AttachmentKind.videoNote => Icons.videocam,
      AttachmentKind.sticker => Icons.emoji_emotions,
      AttachmentKind.animation => Icons.gif_box,
      AttachmentKind.contact => Icons.contact_phone,
      AttachmentKind.location => Icons.location_on,
      AttachmentKind.venue => Icons.place,
      AttachmentKind.poll => Icons.poll,
      AttachmentKind.dice => Icons.casino,
      AttachmentKind.unknown => Icons.attach_file,
    };
  }
}

class LinkPreviewCard extends StatelessWidget {
  const LinkPreviewCard({super.key, required this.url, required this.maxWidth});

  final String url;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final uri = Uri.tryParse(url);
    final host = uri?.host.isNotEmpty == true ? uri!.host : url;
    final isVideo = isDirectVideoUrl(url);
    if (isVideo) {
      final mediaWidth = math.max(180.0, math.min(maxWidth - 20, 420.0));
      return Container(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          minWidth: math.min(maxWidth, 220.0),
        ),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: scheme.tertiaryContainer.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(8),
          border: Border(right: BorderSide(color: scheme.tertiary, width: 3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.play_circle, color: scheme.tertiary),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  tooltip: 'فتح الرابط',
                  onPressed: () async {
                    final parsed = Uri.tryParse(url);
                    if (parsed != null) {
                      await launchUrl(
                        parsed,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                  icon: const Icon(Icons.open_in_new, size: 18),
                ),
              ],
            ),
            Text(
              url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.ltr,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 9),
            InlineVideoPlayer(url: url, width: mediaWidth),
          ],
        ),
      );
    }
    return InkWell(
      onTap: () async {
        final parsed = Uri.tryParse(url);
        if (parsed != null) {
          await launchUrl(parsed, mode: LaunchMode.externalApplication);
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth, minWidth: 220),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: scheme.tertiaryContainer.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(8),
          border: Border(right: BorderSide(color: scheme.tertiary, width: 3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.link, color: scheme.tertiary),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.open_in_new, size: 18),
          ],
        ),
      ),
    );
  }
}

class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.message, required this.onClose});

  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.error_outline, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
          IconButton(
            onPressed: onClose,
            icon: Icon(Icons.close, color: scheme.onErrorContainer),
          ),
        ],
      ),
    );
  }
}

class AccountSettingsCard extends StatelessWidget {
  const AccountSettingsCard({
    super.key,
    required this.controller,
    required this.settings,
    required this.onLogin,
  });

  final ChatController controller;
  final SettingsStore settings;
  final Future<void> Function() onLogin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bot = controller.bot;
    final title = bot == null ? 'غير مسجل الدخول' : '@${bot.username}';
    final subtitle = bot == null
        ? 'اربط التطبيق ببوت تلغرام من زر تسجيل الدخول.'
        : 'متصل عبر ${settings.apiBaseUrl}';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.56),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            backgroundColor: bot == null ? scheme.surface : scheme.primary,
            foregroundColor: bot == null
                ? scheme.onSurfaceVariant
                : scheme.onPrimary,
            child: Icon(bot == null ? Icons.person_off : Icons.smart_toy),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onLogin,
            icon: const Icon(Icons.login),
            label: const Text('تسجيل الدخول'),
          ),
        ],
      ),
    );
  }
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 52, color: scheme.primary),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _AppLogoPainter(Theme.of(context).colorScheme),
    );
  }
}

class _AppLogoPainter extends CustomPainter {
  const _AppLogoPainter(this.scheme);

  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final body = RRect.fromRectAndRadius(
      rect,
      Radius.circular(size.width * 0.22),
    );
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: <Color>[scheme.primary, scheme.tertiary, scheme.secondary],
      ).createShader(rect);
    canvas.drawRRect(body, paint);

    final bubblePaint = Paint()..color = scheme.surface.withValues(alpha: 0.94);
    final bubble = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.2,
        size.height * 0.24,
        size.width * 0.6,
        size.height * 0.42,
      ),
      Radius.circular(size.width * 0.12),
    );
    canvas.drawRRect(bubble, bubblePaint);

    final tail = Path()
      ..moveTo(size.width * 0.38, size.height * 0.62)
      ..lineTo(size.width * 0.31, size.height * 0.78)
      ..lineTo(size.width * 0.53, size.height * 0.64)
      ..close();
    canvas.drawPath(tail, bubblePaint);

    final dotPaint = Paint()..color = scheme.primary;
    for (final x in <double>[0.36, 0.5, 0.64]) {
      canvas.drawCircle(
        Offset(size.width * x, size.height * 0.45),
        size.width * 0.035,
        dotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AppLogoPainter oldDelegate) =>
      oldDelegate.scheme != scheme;
}

String displayChatTitle(SettingsStore settings, TelegramChat chat) {
  return settings.customChatName(chat.id) ?? chat.displayTitle;
}

String? extractFirstUrl(String text) {
  final match = RegExp(
    r'https?:\/\/[^\s<>()]+',
    caseSensitive: false,
  ).firstMatch(text);
  return match?.group(0);
}

bool isDirectVideoUrl(String url) {
  final uri = Uri.tryParse(url);
  final path = (uri?.path.isNotEmpty == true ? uri!.path : url).toLowerCase();
  return <String>{
    '.mp4',
    '.webm',
    '.mov',
    '.m4v',
    '.mkv',
    '.avi',
    '.m3u8',
  }.any(path.endsWith);
}

String _extension(String? filename) {
  if (filename == null) {
    return '';
  }
  final index = filename.lastIndexOf('.');
  if (index < 0 || index == filename.length - 1) {
    return '';
  }
  return filename.substring(index + 1).toLowerCase();
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  final hours = duration.inHours;
  if (hours > 0) {
    return '$hours:$minutes:$seconds';
  }
  return '$minutes:$seconds';
}

Future<void> showAddChatDialog(
  BuildContext context,
  ChatController controller,
) async {
  final chatId = TextEditingController();
  final name = TextEditingController();
  String? error;
  await showDialog<void>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('إضافة محادثة'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextField(
                    controller: chatId,
                    autofocus: true,
                    textDirection: TextDirection.ltr,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Chat ID',
                      prefixIcon: const Icon(Icons.tag),
                      errorText: error,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'اسم مخصص',
                      prefixIcon: Icon(Icons.drive_file_rename_outline),
                    ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  final id = int.tryParse(chatId.text.trim());
                  if (id == null) {
                    setDialogState(() => error = 'أدخل رقم محادثة صحيح.');
                    return;
                  }
                  await controller.addManualChat(chatId: id, name: name.text);
                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                },
                icon: const Icon(Icons.add),
                label: const Text('إضافة'),
              ),
            ],
          );
        },
      );
    },
  );
  chatId.dispose();
  name.dispose();
}

Future<void> showRenameChatDialog(
  BuildContext context,
  SettingsStore settings,
  TelegramChat chat,
) async {
  final name = TextEditingController(
    text: settings.customChatName(chat.id) ?? chat.displayTitle,
  );
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('تسمية المحادثة'),
      content: TextField(
        controller: name,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'اسم المحادثة',
          prefixIcon: Icon(Icons.drive_file_rename_outline),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        TextButton.icon(
          onPressed: () async {
            await settings.setCustomChatName(chat.id, null);
            if (context.mounted) {
              Navigator.pop(context);
            }
          },
          icon: const Icon(Icons.restore),
          label: const Text('الاسم الأصلي'),
        ),
        FilledButton.icon(
          onPressed: () async {
            await settings.setCustomChatName(chat.id, name.text);
            if (context.mounted) {
              Navigator.pop(context);
            }
          },
          icon: const Icon(Icons.check),
          label: const Text('حفظ'),
        ),
      ],
    ),
  );
  name.dispose();
}

Future<bool> confirmDelete(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('حذف الرسالة؟'),
      content: const Text(
        'سيحاول التطبيق حذفها من تلغرام لدى الجميع حسب صلاحيات البوت.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.delete_outline),
          label: const Text('حذف'),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<void> showEditDialog(
  BuildContext context,
  ChatController controller,
  TelegramMessage message,
) async {
  final editor = TextEditingController(
    text: message.text ?? message.caption ?? '',
  );
  final value = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('تعديل الرسالة'),
      content: TextField(
        controller: editor,
        autofocus: true,
        minLines: 2,
        maxLines: 8,
        decoration: const InputDecoration(hintText: 'النص الجديد'),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, editor.text),
          icon: const Icon(Icons.check),
          label: const Text('حفظ'),
        ),
      ],
    ),
  );
  editor.dispose();
  if (value != null) {
    await controller.editMessage(message, value);
  }
}

Future<void> showSettingsDialog(
  BuildContext context,
  ChatController controller,
  SettingsStore settings,
) async {
  final password = TextEditingController();
  await showDialog<void>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('الإعدادات'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    AccountSettingsCard(
                      controller: controller,
                      settings: settings,
                      onLogin: () async {
                        await showLoginDialog(context, controller, settings);
                        setDialogState(() {});
                      },
                    ),
                    const SizedBox(height: 12),
                    if (controller.lastError != null) ...<Widget>[
                      ErrorBanner(
                        message: controller.lastError!,
                        onClose: controller.clearError,
                      ),
                      const SizedBox(height: 12),
                    ],
                    SwitchListTile(
                      value: settings.darkMode,
                      onChanged: (value) async {
                        await settings.setDarkMode(value);
                        setDialogState(() {});
                      },
                      secondary: const Icon(Icons.dark_mode),
                      title: const Text('الوضع الداكن'),
                    ),
                    SwitchListTile(
                      value: settings.notificationsEnabled,
                      onChanged: (value) async {
                        await settings.setNotificationsEnabled(value);
                        setDialogState(() {});
                      },
                      secondary: const Icon(Icons.notifications_active),
                      title: const Text('إشعارات الكمبيوتر'),
                    ),
                    SwitchListTile(
                      value: settings.soundsEnabled,
                      onChanged: (value) async {
                        await settings.setSoundsEnabled(value);
                        setDialogState(() {});
                      },
                      secondary: const Icon(Icons.volume_up),
                      title: const Text('أصوات التطبيق'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: password,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: settings.hasPassword
                            ? 'تغيير كلمة مرور القفل'
                            : 'إنشاء كلمة مرور للقفل',
                        prefixIcon: const Icon(Icons.lock),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: <Widget>[
              if (settings.hasPassword)
                TextButton.icon(
                  onPressed: () async {
                    await settings.clearPassword();
                    setDialogState(() {});
                  },
                  icon: const Icon(Icons.lock_open),
                  label: const Text('إزالة القفل'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إغلاق'),
              ),
              FilledButton.icon(
                onPressed: () async {
                  if (password.text.trim().isNotEmpty) {
                    await settings.setPassword(password.text);
                  }
                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                },
                icon: const Icon(Icons.save),
                label: const Text('حفظ'),
              ),
            ],
          );
        },
      );
    },
  );
  password.dispose();
}

Future<void> showLoginDialog(
  BuildContext context,
  ChatController controller,
  SettingsStore settings,
) async {
  final token = TextEditingController(text: settings.botToken);
  final chatId = TextEditingController(
    text: settings.preferredChatId?.toString() ?? '',
  );
  final apiBaseUrl = TextEditingController(text: settings.apiBaseUrl);
  String? error;
  await showDialog<void>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('تسجيل الدخول'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    TextField(
                      controller: token,
                      autofocus: true,
                      textDirection: TextDirection.ltr,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Telegram Bot Token',
                        prefixIcon: Icon(Icons.key),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: chatId,
                      textDirection: TextDirection.ltr,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Chat ID افتراضي اختياري',
                        prefixIcon: Icon(Icons.tag),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: apiBaseUrl,
                      textDirection: TextDirection.ltr,
                      decoration: const InputDecoration(
                        labelText: 'Bot API Server URL',
                        helperText:
                            'اتركه كما هو، أو استخدم Local Bot API Server لدعم ملفات كبيرة.',
                        prefixIcon: Icon(Icons.dns_outlined),
                      ),
                    ),
                    if (error != null) ...<Widget>[
                      const SizedBox(height: 12),
                      ErrorBanner(
                        message: error!,
                        onClose: () => setDialogState(() => error = null),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء'),
              ),
              FilledButton.icon(
                onPressed: controller.isConnecting
                    ? null
                    : () async {
                        await controller.connect(
                          token: token.text,
                          apiBaseUrl: apiBaseUrl.text,
                          preferredChatId: int.tryParse(chatId.text.trim()),
                        );
                        if (controller.lastError != null) {
                          setDialogState(() => error = controller.lastError);
                          return;
                        }
                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                      },
                icon: controller.isConnecting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: Text(
                  controller.isConnecting ? 'جاري الدخول...' : 'تسجيل الدخول',
                ),
              ),
            ],
          );
        },
      );
    },
  );
  token.dispose();
  chatId.dispose();
  apiBaseUrl.dispose();
}
