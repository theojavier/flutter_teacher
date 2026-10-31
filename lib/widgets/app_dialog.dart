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
import '../helpers/AppTheme.dart';

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
}

class AppToast {
  AppToast._();

  static void show(
    BuildContext context,
    String message, {
    String? title,
    AppTone tone = AppTone.info,
  }) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppTheme.card,
          content: Row(
            children: [
              Icon(tone.icon, color: tone.color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null)
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppTheme.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    Text(message, style: const TextStyle(color: AppTheme.text)),
                  ],
                ),
              ),
            ],
          ),
        ),
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
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.line),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon ?? tone.icon, color: tone.color, size: 30),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (detail != null && detail!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  detail!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: tone.color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.mutedText, height: 1.45),
              ),
              if (note != null && note!.isNotEmpty) ...[
                const SizedBox(height: 10),
                SelectableText(
                  note!,
                  style: const TextStyle(
                    color: AppTheme.mutedText,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(children: actions),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Palette (from the HTML)
// ---------------------------------------------------------------------
const Color _ink = Color(0xFF121217);
const Color _inkSoft = Color(0xFF1D1D23);
const Color _inkLine = Color(0xFF37373D);
const Color _inkHover = Color(0xFF28282F);
const Color _inkMuted = Color(0xFFA1A1AA);
const Color _blue = Color(0xFF153CFF);
const Color _red = Color(0xFFDF2D45);
const Color _redLight = Color(0xFFFF6B7E);
const Color _redSoft = Color(0xFFFFF3F5);
const Color _redBorder = Color(0xFFF3CED5);
const Color _paper = Color(0xFFF7F8F6);
const Color _line = Color(0xFFDFE0DE);
const Color _muted = Color(0xFF75777D);
const Color _errorText = Color(0xFFA42237);
const Color _okBg = Color(0xFFE9F7EF);
const Color _okBorder = Color(0xFFD0E6D8);
const Color _okText = Color(0xFF19724C);

String _initialsOf(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'AD';
  final first = parts.first[0];
  final last = parts.length > 1 ? parts.last[0] : '';
  return (first + last).toUpperCase();
}

String _subtitleOf(String? idNumber) =>
    (idNumber != null && idNumber.isNotEmpty) ? idNumber : 'Administrator';

class _UserAvatar extends StatelessWidget {
  final String? url;
  final String name;
  final double size;
  final double fontSize;

  const _UserAvatar({
    required this.url,
    required this.name,
    required this.size,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final initials = Text(
      _initialsOf(name),
      style: TextStyle(
        color: Colors.white,
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
      ),
    );
    final hasImage = url != null && url!.isNotEmpty;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: _blue, shape: BoxShape.circle),
      clipBehavior: Clip.antiAlias,
      child: hasImage
          ? Image.network(
              url!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => initials,
            )
          : initials,
    );
  }
}

// ---------------------------------------------------------------------
// Top bar button
// ---------------------------------------------------------------------
class AdminUserButton extends StatefulWidget {
  final String? avatarUrl;
  final String name;
  final String? idNumber;
  final VoidCallback onViewProfile;
  final VoidCallback? onChangePassword;
  final VoidCallback onLogout;

  const AdminUserButton({
    super.key,
    required this.avatarUrl,
    required this.name,
    required this.idNumber,
    required this.onViewProfile,
    this.onChangePassword,
    required this.onLogout,
  });

  @override
  State<AdminUserButton> createState() => _AdminUserButtonState();
}

class _AdminUserButtonState extends State<AdminUserButton> {
  bool _isOpen = false;

  Future<void> _openMenu() async {
    setState(() => _isOpen = true);

    final size = MediaQuery.of(context).size;
    final topInset = MediaQuery.of(context).padding.top;
    final wide = size.width >= 900;

    await showDialog(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) => Dialog(
        insetPadding: EdgeInsets.only(
          top: wide ? 68 : topInset + 58,
          right: wide ? 28 : 12,
          left: 12,
        ),
        alignment: Alignment.topRight,
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: ProfileMenuPanel(
          avatarUrl: widget.avatarUrl,
          name: widget.name,
          idNumber: widget.idNumber,
          onViewProfile: () {
            Navigator.of(ctx).pop();
            widget.onViewProfile();
          },
          onChangePassword: () {
            Navigator.of(ctx).pop();
            // Use the trigger's own context (still mounted after the
            // menu dialog closes) rather than the menu's ctx.
            if (widget.onChangePassword != null) {
              widget.onChangePassword!();
            } else {
              confirmChangePassword(context);
            }
          },
          onLogout: () {
            Navigator.of(ctx).pop();
            widget.onLogout();
          },
        ),
      ),
    );

    if (mounted) setState(() => _isOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    // The HTML hides the name on small screens: avatar only there.
    final compact = MediaQuery.of(context).size.width < 680;

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(9),
        side: BorderSide(color: _isOpen ? _blue : _line),
      ),
      child: InkWell(
        onTap: _openMenu,
        borderRadius: BorderRadius.circular(9),
        hoverColor: _paper,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: EdgeInsets.fromLTRB(5, 4, compact ? 6 : 11, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _UserAvatar(
                url: widget.avatarUrl,
                name: widget.name,
                size: 33,
                fontSize: 10,
              ),
              if (!compact) ...[
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _subtitleOf(widget.idNumber),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _muted, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ],
              SizedBox(width: compact ? 2 : 6),
              Icon(
                _isOpen
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: _muted,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Dropdown panel
// ---------------------------------------------------------------------
class ProfileMenuPanel extends StatelessWidget {
  final String? avatarUrl;
  final String name;
  final String? idNumber;
  final VoidCallback onViewProfile;
  final VoidCallback onChangePassword;
  final VoidCallback onLogout;

  const ProfileMenuPanel({
    super.key,
    required this.avatarUrl,
    required this.name,
    required this.idNumber,
    required this.onViewProfile,
    required this.onChangePassword,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final panelWidth = (MediaQuery.of(context).size.width - 24).clamp(
      280.0,
      300.0,
    );

    return Material(
      color: Colors.transparent,
      child: Container(
        width: panelWidth,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: _ink,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _inkLine),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 28,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: _inkSoft,
                border: Border(bottom: BorderSide(color: _inkLine)),
              ),
              child: Row(
                children: [
                  _UserAvatar(
                    url: avatarUrl,
                    name: name,
                    size: 44,
                    fontSize: 13,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13.5,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            const Icon(
                              Icons.badge_outlined,
                              size: 13,
                              color: _inkMuted,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                _subtitleOf(idNumber),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _inkMuted,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 6),
            _ProfileMenuTile(
              icon: Icons.person_outline,
              iconColor: Colors.white,
              iconBg: _inkSoft,
              label: 'View profile',
              onTap: onViewProfile,
            ),
            const Divider(
              height: 1,
              indent: 16,
              endIndent: 16,
              color: _inkLine,
            ),
            _ProfileMenuTile(
              icon: Icons.lock_outline,
              iconColor: Colors.white,
              iconBg: _inkSoft,
              label: 'Change password',
              onTap: onChangePassword,
            ),
            const Divider(
              height: 1,
              indent: 16,
              endIndent: 16,
              color: _inkLine,
            ),
            _ProfileMenuTile(
              icon: Icons.logout,
              iconColor: _redLight,
              iconBg: _red.withValues(alpha: 0.16),
              iconBorder: _red.withValues(alpha: 0.35),
              label: 'Log out',
              labelColor: _redLight,
              onTap: onLogout,
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

class _ProfileMenuTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final Color iconBorder;
  final String label;
  final Color? labelColor;
  final VoidCallback onTap;

  const _ProfileMenuTile({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    required this.onTap,
    this.iconBorder = _inkLine,
    this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      hoverColor: _inkHover,
      highlightColor: _inkHover,
      splashColor: _inkHover,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: iconBorder),
              ),
              child: Icon(icon, size: 16, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: labelColor ?? Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Built-in "Change password" fallback. Same behavior as before (send a
// Firebase password reset email to whoever is currently signed in),
// restyled to the HTML modal look.
// ---------------------------------------------------------------------
Future<void> confirmChangePassword(BuildContext context) {
  return showDialog(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => const _ChangePasswordDialog(),
  );
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  bool _isSending = false;
  bool _sent = false;
  String? _errorMessage;

  String? get _email => FirebaseAuth.instance.currentUser?.email;

  Future<void> _sendResetEmail() async {
    final email = _email;
    if (email == null) {
      setState(() {
        _errorMessage = "No signed-in user found. Please log in again.";
      });
      return;
    }

    setState(() {
      _isSending = true;
      _errorMessage = null;
    });

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) setState(() => _sent = true);
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _errorMessage = _messageFor(e));
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage = "Something went wrong. Please try again.",
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  String _messageFor(FirebaseAuthException e) {
    switch (e.code) {
      case 'too-many-requests':
        return 'Too many attempts. Please wait a bit and try again.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      case 'user-not-found':
        return 'No account found for this email.';
      default:
        return e.message ?? 'Could not send reset email (${e.code}).';
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = _email;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE4E4E4)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.24),
                blurRadius: 60,
                offset: const Offset(0, 24),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  border: Border.all(color: const Color(0xFFCCD7FF)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.lock_reset, color: _blue, size: 24),
              ),
              const SizedBox(height: 14),
              const Text(
                'Change password',
                style: TextStyle(
                  color: _ink,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.9,
                ),
              ),
              const SizedBox(height: 14),

              if (_errorMessage != null)
                _buildBanner(
                  title: 'Something went wrong',
                  message: _errorMessage!,
                  bg: _redSoft,
                  border: _redBorder,
                  fg: _errorText,
                  icon: Icons.error_outline,
                )
              else if (_sent)
                _buildBanner(
                  title: 'Email sent',
                  message:
                      'Check ${email ?? 'your inbox'} for a link to reset your password.',
                  bg: _okBg,
                  border: _okBorder,
                  fg: _okText,
                  icon: Icons.check_circle_outline,
                )
              else ...[
                const Text(
                  "We'll send a password reset link to:",
                  style: TextStyle(color: _muted, fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 13,
                    horizontal: 14,
                  ),
                  decoration: BoxDecoration(
                    color: _paper,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _line),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.alternate_email, color: _blue, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          email ?? 'No email on file',
                          style: const TextStyle(color: _ink, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),
              if (_sent)
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _line),
                      shape: RoundedRectangleBorder(
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
                            backgroundColor: _blue,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: _blue.withOpacity(0.6),
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
