import 'package:flutter/material.dart';

import '../services/chat_controller.dart';
import '../services/settings_store.dart';

class AccountsListScreen extends StatelessWidget {
  const AccountsListScreen({
    super.key,
    required this.settings,
    required this.controller,
  });

  final SettingsStore settings;
  final ChatController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accounts = settings.accounts;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  Center(child: _MiniLogo(size: 72, scheme: scheme)),
                  const SizedBox(height: 16),
                  Text(
                    'اختر الحساب',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'يمكنك إضافة أكثر من بوت والتبديل بينهم. كل حساب محمي بكلمة مرور اختيارية.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: accounts.isEmpty
                        ? _Empty(icon: Icons.person_off, title: 'لا يوجد حسابات', subtitle: 'أضف أول بوت للبدء', scheme: scheme)
                        : ListView.separated(
                            itemCount: accounts.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final acc = accounts[i];
                              final isActive = acc.id == settings.activeAccountId;
                              return AccountTile(
                                account: acc,
                                isActive: isActive,
                                onTap: () => _selectAccount(context, acc),
                                onEdit: () => showAddAccountDialog(context, settings, existing: acc),
                                onDelete: () => _confirmDelete(context, acc),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => showAddAccountDialog(context, settings),
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة حساب جديد'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _selectAccount(BuildContext context, AccountProfile acc) async {
    if (acc.hasPassword) {
      final ok = await showAccountPasswordDialog(context, settings, acc);
      if (!ok) return;
    }
    await settings.setActiveAccount(acc.id);
    await controller.switchToAccount(acc);
    if (context.mounted) Navigator.of(context).maybePop();
  }

  Future<void> _confirmDelete(BuildContext context, AccountProfile acc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الحساب؟'),
        content: Text('هل تريد حذف "${acc.displayLabel}"؟ سيتم حذف أرشيف رسائله المحلي فقط، ولن يحذف البوت من تلغرام.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed == true) {
      await settings.removeAccount(acc.id);
      if (settings.accounts.isNotEmpty && settings.activeAccountId == null) {
        final first = settings.accounts.first;
        await settings.setActiveAccount(first.id);
        await controller.switchToAccount(first);
      }
    }
  }
}

class _MiniLogo extends StatelessWidget {
  const _MiniLogo({required this.size, required this.scheme});
  final double size;
  final ColorScheme scheme;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [scheme.primary, scheme.tertiary, scheme.secondary]),
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      child: Icon(Icons.smart_toy, size: size * 0.5, color: Colors.white),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.subtitle, required this.scheme});
  final IconData icon;
  final String title;
  final String subtitle;
  final ColorScheme scheme;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 52, color: scheme.primary),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
        const SizedBox(height: 6),
        Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
      ]),
    );
  }
}

class AccountTile extends StatelessWidget {
  const AccountTile({
    super.key,
    required this.account,
    required this.isActive,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final AccountProfile account;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: isActive ? scheme.primaryContainer.withValues(alpha: 0.6) : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isActive ? scheme.primary : scheme.outlineVariant),
      ),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: isActive ? scheme.primary : scheme.surface,
          foregroundColor: isActive ? scheme.onPrimary : scheme.onSurfaceVariant,
          child: const Icon(Icons.smart_toy),
        ),
        title: Text(account.displayLabel, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(account.apiBaseUrl, textDirection: TextDirection.ltr, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 2),
            Row(
              children: [
                if (account.hasPassword) ...[
                  Icon(Icons.lock, size: 12, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text('محمي', style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                  const SizedBox(width: 8),
                ],
                if (isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(99)),
                    child: Text('نشط', style: TextStyle(fontSize: 10, color: scheme.onPrimary, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'edit') onEdit();
            if (v == 'delete') onDelete();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit), title: Text('تعديل'))),
            PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete), title: Text('حذف'))),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onClose});
  final String message;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(8)),
      child: Row(children: [Icon(Icons.error_outline, color: scheme.onErrorContainer), const SizedBox(width: 8), Expanded(child: Text(message, style: TextStyle(color: scheme.onErrorContainer))), IconButton(onPressed: onClose, icon: Icon(Icons.close, color: scheme.onErrorContainer))]),
    );
  }
}

Future<bool> showAccountPasswordDialog(BuildContext context, SettingsStore settings, AccountProfile account) async {
  final ctrl = TextEditingController();
  String? error;
  bool result = false;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text('كلمة مرور ${account.displayLabel}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              obscureText: true,
              autofocus: true,
              onSubmitted: (_) {
                if (settings.verifyAccountPassword(account.id, ctrl.text)) {
                  result = true;
                  Navigator.pop(ctx);
                } else {
                  setState(() => error = 'كلمة مرور خاطئة');
                }
              },
              decoration: InputDecoration(labelText: 'كلمة المرور', prefixIcon: const Icon(Icons.lock), errorText: error),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () {
              if (settings.verifyAccountPassword(account.id, ctrl.text)) {
                result = true;
                Navigator.pop(ctx);
              } else {
                setState(() => error = 'كلمة مرور خاطئة');
              }
            },
            child: const Text('دخول'),
          ),
        ],
      ),
    ),
  );
  ctrl.dispose();
  return result;
}

Future<void> showAddAccountDialog(BuildContext context, SettingsStore settings, {AccountProfile? existing}) async {
  final labelCtrl = TextEditingController(text: existing?.label ?? '');
  final tokenCtrl = TextEditingController(text: existing?.botToken ?? '');
  final apiCtrl = TextEditingController(text: existing?.apiBaseUrl ?? 'https://api.telegram.org');
  final chatIdCtrl = TextEditingController(text: existing?.preferredChatId?.toString() ?? '');
  final passCtrl = TextEditingController();
  String? error;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(existing == null ? 'إضافة حساب' : 'تعديل حساب'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: labelCtrl, decoration: const InputDecoration(labelText: 'اسم الحساب', prefixIcon: Icon(Icons.badge))),
                const SizedBox(height: 10),
                TextField(controller: tokenCtrl, textDirection: TextDirection.ltr, obscureText: existing == null, decoration: const InputDecoration(labelText: 'Bot Token', prefixIcon: Icon(Icons.key))),
                const SizedBox(height: 10),
                TextField(controller: apiCtrl, textDirection: TextDirection.ltr, decoration: const InputDecoration(labelText: 'Bot API URL', helperText: 'اتركه افتراضي أو استخدم Local Server لدعم ملفات كبيرة', prefixIcon: Icon(Icons.dns))),
                const SizedBox(height: 10),
                TextField(controller: chatIdCtrl, textDirection: TextDirection.ltr, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Chat ID افتراضي (اختياري)', prefixIcon: Icon(Icons.tag))),
                const SizedBox(height: 10),
                TextField(controller: passCtrl, obscureText: true, decoration: InputDecoration(labelText: existing == null ? 'كلمة مرور للحساب (اختياري)' : 'كلمة مرور جديدة (اتركه فارغ للاحتفاظ)', prefixIcon: const Icon(Icons.lock))),
                if (error != null) ...[const SizedBox(height: 10), _ErrorBanner(message: error!, onClose: () => setState(() => error = null))],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton.icon(
            onPressed: () async {
              final token = tokenCtrl.text.trim();
              if (token.isEmpty) {
                setState(() => error = 'أدخل التوكن');
                return;
              }
              try {
                if (existing == null) {
                  await settings.addAccount(
                    label: labelCtrl.text.trim().isEmpty ? 'حساب ${settings.accounts.length + 1}' : labelCtrl.text.trim(),
                    token: token,
                    apiBaseUrl: apiCtrl.text,
                    preferredChatId: int.tryParse(chatIdCtrl.text.trim()),
                    password: passCtrl.text.trim().isEmpty ? null : passCtrl.text.trim(),
                  );
                } else {
                  await settings.updateAccountFull(
                    id: existing.id,
                    label: labelCtrl.text.trim(),
                    token: token,
                    apiBaseUrl: apiCtrl.text,
                    preferredChatId: int.tryParse(chatIdCtrl.text.trim()),
                    newPassword: passCtrl.text.trim().isEmpty ? null : passCtrl.text.trim(),
                  );
                }
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                setState(() => error = e.toString());
              }
            },
            icon: const Icon(Icons.save),
            label: Text(existing == null ? 'إضافة' : 'حفظ'),
          ),
        ],
      ),
    ),
  );
  labelCtrl.dispose();
  tokenCtrl.dispose();
  apiCtrl.dispose();
  chatIdCtrl.dispose();
  passCtrl.dispose();
}
