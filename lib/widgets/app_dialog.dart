// profile_menu.dart
//
// Self-contained profile menu widgets for the app header, styled to match
// the FOTS Admin HTML (white / ink / red):
//   - AdminUserButton: the account button in the top bar (avatar, name,
//     chevron). Tapping it opens the menu.
//   - ProfileMenuPanel: the dropdown panel (ink header + white menu list).
//   - confirmChangePassword: pop-up that sends Firebase's password reset
//     email to the signed-in user (used when onChangePassword is null).
//
// Behavior is unchanged from the navy version. Only the look changed.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../helpers/app_theme.dart';

enum AppTone { info, success, warning, danger, error }

extension _AppToneStyle on AppTone {
  Color get color => switch (this) {
    AppTone.success => AppTheme.success,
    AppTone.warning => const Color(0xFFFBBF24),
    AppTone.danger || AppTone.error => AppTheme.error,
    AppTone.info => AppTheme.accent,
  };

  IconData get icon => switch (this) {
    AppTone.success => Icons.check_circle_outline_rounded,
    AppTone.warning => Icons.warning_amber_rounded,
    AppTone.danger || AppTone.error => Icons.error_outline_rounded,
    AppTone.info => Icons.info_outline_rounded,
  };
}

class AppDialog {
  AppDialog._();

  static Future<bool> confirm(
    BuildContext context, {
    required String title,
    required String message,
    String? detail,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    AppTone tone = AppTone.info,
    IconData? icon,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _AppMessageDialog(
        title: title,
        message: message,
        detail: detail,
        tone: tone,
        icon: icon,
        actions: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(cancelLabel),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: tone.color,
                foregroundColor: Colors.white,
              ),
              child: Text(confirmLabel),
            ),
          ),
        ],
      ),
    );
    return result == true;
  }

  static Future<void> alert(
    BuildContext context, {
    required String title,
    required String message,
    String? detail,
    String? note,
    String buttonLabel = 'Got it',
    AppTone tone = AppTone.info,
    IconData? icon,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _AppMessageDialog(
        title: title,
        message: message,
        detail: detail,
        note: note,
        tone: tone,
        icon: icon,
        actions: [
          Expanded(
            child: ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: tone.color,
                foregroundColor: Colors.white,
              ),
              child: Text(buttonLabel),
            ),
          ),
        ],
      ),
    );
  }

  static Future<T?> custom<T>(
    BuildContext context, {
    required WidgetBuilder builder,
  }) => showDialog<T>(context: context, builder: builder);

  static Widget formCard({
    required String title,
    required IconData icon,
    required String confirmLabel,
    required VoidCallback onCancel,
    required VoidCallback onConfirm,
    required Widget content,
  }) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.line),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
                child: Row(
                  children: [
                    Icon(icon, color: AppTheme.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: AppTheme.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: onCancel,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: content,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(22),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: onCancel,
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: onConfirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(confirmLabel),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<T?> _present<T>(BuildContext context, WidgetBuilder builder) {
    return showGeneralDialog<T>(
      context: context,
      useRootNavigator: false, // <- keeps it inside the main view
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withOpacity(0.55),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (ctx, _, __) => builder(ctx),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  static ButtonStyle _outlined() => OutlinedButton.styleFrom(
        foregroundColor: AppTheme.text,
        minimumSize: const Size(0, 46),
        side: BorderSide(color: Colors.white.withOpacity(0.2)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );

  static ButtonStyle _filled(Color color) => FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: color.computeLuminance() > 0.5
            ? const Color(0xFF0B1220)
            : Colors.white,
        minimumSize: const Size(0, 46),
        elevation: 0,
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );
  }
}

class _AppMessageDialog extends StatelessWidget {
  final String title;
  final String message;
  final String? detail;
  final String? note;
  final AppTone tone;
  final IconData? icon;
  final List<Widget> actions;

  const _AppMessageDialog({
    required this.title,
    required this.message,
    required this.tone,
    required this.actions,
    this.icon,
    this.detail,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppTheme.header, AppTheme.card],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: color.withOpacity(0.45), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.45),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
              BoxShadow(color: color.withOpacity(0.12), blurRadius: 30),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 26, 24, 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _iconBadge(color),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.text,
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (detail != null && detail!.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: color.withOpacity(0.35)),
                        ),
                        child: Text(
                          detail!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: color,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                    if (message.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppTheme.mutedText,
                          fontSize: 13.5,
                          height: 1.45,
                        ),
                      ),
                    ],
                    if (note != null && note!.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.25),
                          borderRadius: BorderRadius.circular(10),
                          border:
                              Border.all(color: Colors.white.withOpacity(0.06)),
                        ),
                        child: SelectableText(
                          note!,
                          style: TextStyle(
                            color: AppTheme.mutedText,
                            fontSize: 11.5,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (content != null)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.55,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: content!,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: Row(children: actions),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconBadge(Color color) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withOpacity(0.9), color.withOpacity(0.25)],
        ),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.35), blurRadius: 16, spreadRadius: 1),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Icon(icon ?? tone.icon, color: Colors.white, size: 26),
      ),
    );
  }
}

/// Themed floating toast. Uses the page's own ScaffoldMessenger, so it also
/// appears inside the main view.
class AppToast {
  AppToast._();

  static void feedback(BuildContext context, String message) {
    final normalized = message.toLowerCase();
    final tone = normalized.contains('success') ||
            normalized.contains('saved successfully') ||
            normalized.contains('updated successfully')
        ? AppTone.success
        : normalized.contains('failed') ||
                normalized.contains('error') ||
                normalized.contains('could not') ||
                normalized.contains('unable')
            ? AppTone.error
            : normalized.contains('please') ||
                    normalized.contains('enter ') ||
                    normalized.contains('must save') ||
                    normalized.contains('no uid') ||
                    normalized.contains('cannot be empty')
                ? AppTone.warning
                : AppTone.info;
    final title = switch (tone) {
      AppTone.success => 'Completed',
      AppTone.warning => 'Action needed',
      AppTone.danger || AppTone.error => 'Action failed',
      AppTone.info => 'Notice',
    };
    show(context, message, title: title, tone: tone);
  }

  static void show(
    BuildContext context,
    String message, {
    String? title,
    AppTone tone = AppTone.info,
  }) {
    final color = tone.color;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.transparent,
          elevation: 0,
          padding: EdgeInsets.zero,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          duration: const Duration(seconds: 4),
          content: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                decoration: BoxDecoration(
                  color: AppTheme.header,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: color.withOpacity(0.5)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Done',
                      style: TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 50,
                        child: OutlinedButton(
                          onPressed: _isSending
                              ? null
                              : () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: _line),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              color: _ink,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 50,
                        child: ElevatedButton(
                          onPressed: (_isSending || email == null)
                              ? null
                              : _sendResetEmail,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _red,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: _red.withOpacity(0.6),
                            disabledForegroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: _isSending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Send reset link',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBanner({
    required String title,
    required String message,
    required Color bg,
    required Color border,
    required Color fg,
    required IconData icon,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: fg,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 12.5,
                    height: 1.5,
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
