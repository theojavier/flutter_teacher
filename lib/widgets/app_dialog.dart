import 'package:flutter/material.dart';
import '../helpers/app_theme.dart';

enum AppTone { info, success, warning, danger, error }

extension _ToneStyle on AppTone {
  Color get color {
    switch (this) {
      case AppTone.success:
        return AppTheme.success;
      case AppTone.warning:
        return const Color(0xFFFBBF24);
      case AppTone.danger:
      case AppTone.error:
        return AppTheme.error;
      case AppTone.info:
        return AppTheme.accent;
    }
  }

  IconData get icon {
    switch (this) {
      case AppTone.success:
        return Icons.check_circle_outline_rounded;
      case AppTone.warning:
        return Icons.warning_amber_rounded;
      case AppTone.danger:
      case AppTone.error:
        return Icons.error_outline_rounded;
      case AppTone.info:
        return Icons.info_outline_rounded;
    }
  }
}

/// Themed popups. Shown in the nearest navigator, so under a ShellRoute
/// they stay inside the main content area instead of covering the sidebar.
class AppDialog {
  AppDialog._();

  /// Yes/No style dialog. Returns true only when the user confirms.
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
    final result = await _present<bool>(
      context,
      (ctx) => _AppDialogCard(
        tone: tone,
        icon: icon,
        title: title,
        message: message,
        detail: detail,
        actions: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              style: _outlined(),
              child: Text(cancelLabel),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton(
              autofocus: true,
              onPressed: () => Navigator.of(ctx).pop(true),
              style: _filled(tone.color),
              child: Text(confirmLabel),
            ),
          ),
        ],
      ),
    );
    return result == true;
  }

  /// Single-button result dialog (success, warning, error, info).
  static Future<void> alert(
    BuildContext context, {
    required String title,
    required String message,
    String? detail,
    String? note, // technical detail, shown in a muted box
    String buttonLabel = 'Got it',
    AppTone tone = AppTone.info,
    IconData? icon,
  }) {
    return _present<void>(
      context,
      (ctx) => _AppDialogCard(
        tone: tone,
        icon: icon,
        title: title,
        message: message,
        detail: detail,
        note: note,
        actions: [
          Expanded(
            child: FilledButton(
              autofocus: true,
              onPressed: () => Navigator.of(ctx).pop(),
              style: _filled(tone.color),
              child: Text(buttonLabel),
            ),
          ),
        ],
      ),
    );
  }

  /// Presents a custom dialog in the same animated, nearest-navigator route.
  static Future<T?> custom<T>(
    BuildContext context, {
    required WidgetBuilder builder,
  }) {
    return _present<T>(context, builder);
  }

  /// A themed dialog card for forms that need custom content and actions.
  static Widget formCard({
    required String title,
    required Widget content,
    required String confirmLabel,
    required VoidCallback onConfirm,
    required VoidCallback onCancel,
    String cancelLabel = 'Cancel',
    AppTone tone = AppTone.info,
    IconData? icon,
  }) {
    return _AppDialogCard(
      tone: tone,
      icon: icon,
      title: title,
      message: '',
      content: content,
      actions: [
        Expanded(
          child: OutlinedButton(
            onPressed: onCancel,
            style: _outlined(),
            child: Text(cancelLabel),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            onPressed: onConfirm,
            style: _filled(tone.color),
            child: Text(confirmLabel),
          ),
        ),
      ],
    );
  }

  static Future<T?> _present<T>(BuildContext context, WidgetBuilder builder) {
    return showGeneralDialog<T>(
      context: context,
      useRootNavigator: false, // <- keeps it inside the main view
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (ctx, animation, secondaryAnimation) => builder(ctx),
      transitionBuilder: (ctx, anim, secondaryAnimation, child) {
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
        side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
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

class _AppDialogCard extends StatelessWidget {
  final AppTone tone;
  final IconData? icon;
  final String title;
  final String message;
  final String? detail;
  final String? note;
  final Widget? content;
  final List<Widget> actions;

  const _AppDialogCard({
    required this.tone,
    required this.title,
    required this.message,
    required this.actions,
    this.icon,
    this.detail,
    this.note,
    this.content,
  });

  @override
  Widget build(BuildContext context) {
    final color = tone.color;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppTheme.header, AppTheme.card],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: color.withValues(alpha: 0.45), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
              BoxShadow(color: color.withValues(alpha: 0.12), blurRadius: 30),
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
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: color.withValues(alpha: 0.35)),
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
                          color: Colors.black.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(10),
                          border:
                              Border.all(color: Colors.white.withValues(alpha: 0.06)),
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
          colors: [color.withValues(alpha: 0.9), color.withValues(alpha: 0.25)],
        ),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 16, spreadRadius: 1),
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
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
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
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(tone.icon, color: color, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (title != null)
                            Text(
                              title,
                              style: TextStyle(
                                color: AppTheme.text,
                                fontWeight: FontWeight.w700,
                                fontSize: 13.5,
                              ),
                            ),
                          Text(
                            message,
                            style: TextStyle(
                              color: title == null
                                  ? AppTheme.text
                                  : AppTheme.mutedText,
                              fontSize: 12.5,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.close, size: 16, color: AppTheme.mutedText),
                      onPressed: messenger.hideCurrentSnackBar,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
  }
}