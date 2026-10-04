import 'package:flutter/material.dart';

class NavHeader extends StatefulWidget {
  final String name;
  final String section;

  // Admin fields
  final String? department;
  final String? adminId;

  final String? profileImageUrl;
  final VoidCallback onProfileTap;

  const NavHeader({
    super.key,
    required this.name,
    required this.section,
    this.department,
    this.adminId,
    this.profileImageUrl,
    required this.onProfileTap,
  });

  @override
  State<NavHeader> createState() => _NavHeaderState();
}

class _NavHeaderState extends State<NavHeader>
    with TickerProviderStateMixin {
  bool _expanded = false;

  static const Color _headerColor = Color(0xFF0F2B45);
  static const Color _headerColorLight = Color(0xFF17456F);
  static const Color _textColor = Color(0xFFE6F0F8);
  static const Color _accentColor = Color(0xFF3D8BFF);

  void _toggle() {
    setState(() => _expanded = !_expanded);
  }

  void _selectProfile() {
    setState(() => _expanded = false);

    if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }

    widget.onProfileTap();
  }

  @override
  Widget build(BuildContext context) {
    final hasAdminInfo =
        widget.department != null &&
        widget.department!.isNotEmpty &&
        widget.adminId != null &&
        widget.adminId!.isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ============================================================
        // TOP HEADER
        // Same visual design as the student header
        // ============================================================
        InkWell(
          onTap: _toggle,
          child: SizedBox(
            height: 160,
            width: double.infinity,
            child: UserAccountsDrawerHeader(
              margin: EdgeInsets.zero,

              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _headerColorLight,
                    _headerColor,
                  ],
                ),
              ),

              // ======================================================
              // NAME
              // ======================================================
              accountName: Text(
                widget.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _textColor,
                  fontSize: 16,
                ),
              ),

              // ======================================================
              // DEPARTMENT + ADMIN ID
              // Side by side
              //
              // Example:
              // IT   09266
              // ======================================================
              accountEmail: hasAdminInfo
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            widget.department!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),

                        const SizedBox(width: 8),

                        Text(
                          widget.adminId!,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      widget.section,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),

              // ======================================================
              // PROFILE IMAGE
              // ======================================================
              currentAccountPicture: CircleAvatar(
                backgroundColor: _headerColor,
                child: widget.profileImageUrl != null &&
                        widget.profileImageUrl!.isNotEmpty
                    ? ClipOval(
                        child: Image.network(
                          widget.profileImageUrl!,
                          key: ValueKey(widget.profileImageUrl),
                          fit: BoxFit.cover,
                          width: 80,
                          height: 80,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(
                              Icons.person,
                              size: 40,
                              color: Colors.grey,
                            );
                          },
                        ),
                      )
                    : const Icon(
                        Icons.person,
                        size: 40,
                        color: Colors.grey,
                      ),
              ),

              onDetailsPressed: _toggle,
            ),
          ),
        ),

        // ============================================================
        // DROPDOWN
        // Only My Profile
        // ============================================================
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(
                    12,
                    8,
                    12,
                    8,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ------------------------------------------------
                      // Pointer triangle
                      // ------------------------------------------------
                      Align(
                        alignment: Alignment.topRight,
                        child: Transform.translate(
                          offset: const Offset(-28, 6),
                          child: CustomPaint(
                            size: const Size(18, 10),
                            painter: const _TrianglePainter(
                              color: Color.fromARGB(
                                255,
                                19,
                                54,
                                87,
                              ),
                            ),
                          ),
                        ),
                      ),

                      // ------------------------------------------------
                      // Dropdown panel
                      // ------------------------------------------------
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color.fromARGB(
                            255,
                            19,
                            54,
                            87,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.08),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.12),
                              blurRadius: 12,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _bubbleOption(
                              icon: Icons.person_outline,
                              label: 'My Profile',
                              onTap: _selectProfile,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  // ================================================================
  // DROPDOWN OPTION
  // ================================================================
  Widget _bubbleOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      splashColor: _accentColor.withOpacity(0.12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // Icon circle
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: _accentColor.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_outline,
                size: 16,
                color: _accentColor,
              ),
            ),

            const SizedBox(width: 12),

            // Text
            const Expanded(
              child: Text(
                'My Profile',
                style: TextStyle(
                  color: _textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            // Arrow
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: Colors.white70,
            ),
          ],
        ),
      ),
    );
  }
}

/// Small triangle painter used for the dropdown pointer.
class _TrianglePainter extends CustomPainter {
  final Color color;

  const _TrianglePainter({
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;

    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(
    covariant _TrianglePainter oldDelegate,
  ) {
    return oldDelegate.color != color;
  }
}