import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

const Color _ink = Color(0xFF111217);
const Color _inkSoft = Color(0xFF1D1D23);
const Color _inkLine = Color(0xFF37373D);
const Color _inkHover = Color(0xFF28282F);
const Color _muted = Color(0xFFA1A1AA);
const Color _blue = Color(0xFF153CFF);
const Color _blueLight = Color(0xFF9DB0FF);

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'T';
  return (parts.first[0] + (parts.length > 1 ? parts.last[0] : ''))
      .toUpperCase();
}

class _TeacherAvatar extends StatelessWidget {
  final String? url;
  final String name;
  final double size;
  final double fontSize;

  const _TeacherAvatar({
    required this.url,
    required this.name,
    required this.size,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(color: _blue, shape: BoxShape.circle),
      child: url != null && url!.isNotEmpty
          ? Image.network(
              url!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _initialsLabel(),
            )
          : _initialsLabel(),
    );
  }

  Widget _initialsLabel() => Text(
    _initials(name),
    style: TextStyle(
      color: Colors.white,
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
    ),
  );
}

class ProfileMenuTrigger extends StatefulWidget {
  final String? avatarUrl;
  final String name;
  final String? idNumber;
  final VoidCallback onViewProfile;
  final VoidCallback? onChangePassword;
  final VoidCallback onLogout;

  const ProfileMenuTrigger({
    super.key,
    required this.avatarUrl,
    required this.name,
    required this.idNumber,
    required this.onViewProfile,
    this.onChangePassword,
    required this.onLogout,
  });

  @override
  State<ProfileMenuTrigger> createState() => _ProfileMenuTriggerState();
}

class _ProfileMenuTriggerState extends State<ProfileMenuTrigger> {
  bool _isOpen = false;

  Future<void> _openMenu() async {
    setState(() => _isOpen = true);
    final size = MediaQuery.of(context).size;
    final topInset = MediaQuery.of(context).padding.top;
    final wide = size.width >= 900;

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black26,
      builder: (dialogContext) => Dialog(
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
            Navigator.of(dialogContext).pop();
            widget.onViewProfile();
          },
          onChangePassword: () {
            Navigator.of(dialogContext).pop();
            if (widget.onChangePassword != null) {
              widget.onChangePassword!();
            } else {
              confirmChangePassword(context);
            }
          },
          onLogout: () {
            Navigator.of(dialogContext).pop();
            widget.onLogout();
          },
        ),
      ),
    );

    if (mounted) setState(() => _isOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.width < 680;

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: _isOpen ? _blue : const Color(0xFFDCDDDC)),
      ),
      child: InkWell(
        onTap: _openMenu,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: EdgeInsets.fromLTRB(5, 4, compact ? 6 : 11, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TeacherAvatar(
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
                        widget.idNumber?.isNotEmpty == true
                            ? widget.idNumber!
                            : 'Faculty member',
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
                  _TeacherAvatar(
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
                              color: _muted,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                idNumber?.isNotEmpty == true
                                    ? idNumber!
                                    : 'Faculty member',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _muted,
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
              iconColor: _blueLight,
              iconBg: _blue.withOpacity(0.16),
              iconBorder: _blue.withOpacity(0.35),
              label: 'Log out',
              labelColor: _blueLight,
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
      setState(
        () => _errorMessage = 'No signed-in user found. Please log in again.',
      );
      return;
    }

    setState(() {
      _isSending = true;
      _errorMessage = null;
    });

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) setState(() => _sent = true);
    } on FirebaseAuthException catch (error) {
      if (mounted) setState(() => _errorMessage = _messageFor(error));
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage = 'Something went wrong. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  String _messageFor(FirebaseAuthException error) => switch (error.code) {
    'too-many-requests' =>
      'Too many attempts. Please wait a bit and try again.',
    'network-request-failed' =>
      'Network error. Check your connection and try again.',
    'user-not-found' => 'No account found for this email.',
    _ => error.message ?? 'Could not send reset email (${error.code}).',
  };

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
            color: _ink,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _inkLine),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _blue.withOpacity(0.16),
                  border: Border.all(color: _blue.withOpacity(0.4)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.lock_reset,
                  color: _blueLight,
                  size: 24,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Change password',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              if (_errorMessage != null)
                _PasswordNotice(
                  title: 'Something went wrong',
                  message: _errorMessage!,
                  color: const Color(0xFFFF7884),
                )
              else if (_sent)
                _PasswordNotice(
                  title: 'Email sent',
                  message:
                      'Check ${email ?? 'your inbox'} for a link to reset your password.',
                  color: const Color(0xFF6FE4AA),
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
                    color: _inkSoft,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _inkLine),
                  ),
                  child: Text(
                    email ?? 'No email on file',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              if (_sent)
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Done'),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isSending
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: (_isSending || email == null)
                            ? null
                            : _sendResetEmail,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _blue,
                          foregroundColor: Colors.white,
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
                            : const Text('Send reset link'),
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
}

class _PasswordNotice extends StatelessWidget {
  final String title;
  final String message;
  final Color color;

  const _PasswordNotice({
    required this.title,
    required this.message,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        border: Border.all(color: color.withOpacity(0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(message, style: const TextStyle(color: _muted, height: 1.5)),
        ],
      ),
    );
  }
}
