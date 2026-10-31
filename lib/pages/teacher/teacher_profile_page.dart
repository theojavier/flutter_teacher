import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EditProfilePage extends StatefulWidget {
  final String teacherId;

  const EditProfilePage({super.key, required this.teacherId});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  static const Color _paper = Color(0xFFF7F8F6);
  static const Color _ink = Color(0xFF111217);
  static const Color _muted = Color(0xFF777981);
  static const Color _line = Color(0xFFDCDDDC);
  static const Color _blue = Color(0xFF153CFF);
  static const Color _blueWash = Color(0xFFE9EDFF);

  Map<String, dynamic>? userData;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection("users")
          .doc(widget.teacherId)
          .get();

      if (!mounted) return;
      setState(() {
        userData = doc.exists ? doc.data() : null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _paper,
        body: Center(child: CircularProgressIndicator(color: _blue)),
      );
    }

    if (userData == null) {
      return Scaffold(
        backgroundColor: _paper,
        body: Center(
          child: _stateMessage(
            icon: Icons.person_off_outlined,
            title: 'Profile not found',
            message: 'Your teacher profile could not be loaded.',
          ),
        ),
      );
    }

    final data = userData!;

    // Profile image (fix Imgur page links)
    String? imageUrl = data["profileImage"] as String?;
    if (imageUrl != null &&
        imageUrl.contains("imgur.com") &&
        !imageUrl.contains("i.imgur.com")) {
      imageUrl = "${imageUrl.replaceAll("imgur.com", "i.imgur.com")}.jpg";
    }

    final programsList = data["programs"];
    final programs = programsList is List && programsList.isNotEmpty
        ? programsList.join(", ")
        : null;

    final personalRows = [
      _DetailRow(Icons.person_outline, 'Name', data['name']),
      _DetailRow(Icons.wc_outlined, 'Gender', data['gender']),
      _DetailRow(Icons.favorite_border, 'Civil status', data['civilStatus']),
      _DetailRow(Icons.flag_outlined, 'Nationality', data['nationality']),
      _DetailRow(Icons.cake_outlined, 'Date of birth', data['dob']),
      _DetailRow(Icons.email_outlined, 'Email', data['email']),
    ];
    final academicRows = [
      _DetailRow(Icons.badge_outlined, 'Teacher ID', data['ID']),
      _DetailRow(
        Icons.confirmation_number_outlined,
        'ID number',
        data['id number'],
      ),
      _DetailRow(Icons.menu_book_outlined, 'Major', data['major']),
      _DetailRow(Icons.layers_outlined, 'Programs', programs),
      _DetailRow(Icons.security_outlined, 'Role', data['role']),
      _DetailRow(Icons.groups_outlined, 'Year / block', data['yearBlock']),
    ];

    return Scaffold(
      backgroundColor: _bgColor,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTitleBar(),
            const SizedBox(height: 16),

            // ==================================================
            // PROFILE HEADER + PERSONAL DETAILS
            // ==================================================
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Column(
                  children: [
                    _buildAvatarZone(imageUrl, data),
                    _buildDetailsZone(
                      title: "Personal Details",
                      headerIcon: Icons.badge_outlined,
                      rows: [
                        _DetailRow(Icons.person_outline, "Name", data["name"]),
                        _DetailRow(Icons.wc, "Gender", data["gender"]),
                        _DetailRow(
                          Icons.favorite_border,
                          "Civil Status",
                          data["civilStatus"],
                        ),
                        _DetailRow(
                          Icons.flag_outlined,
                          "Nationality",
                          data["nationality"],
                        ),
                        _DetailRow(
                          Icons.cake_outlined,
                          "Date of Birth",
                          data["dob"],
                        ),
                        _DetailRow(
                          Icons.email_outlined,
                          "Email",
                          data["email"],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ==================================================
            // ACADEMIC DETAILS
            // ==================================================
            _buildInfoCard(
              title: "Academic Details",
              headerIcon: Icons.school_outlined,
              rows: [
                _DetailRow(Icons.badge_outlined, "Teacher ID", data["ID"]),
                _DetailRow(
                  Icons.confirmation_number_outlined,
                  "ID Number",
                  data["id number"],
                ),
                _DetailRow(Icons.menu_book_outlined, "Major", data["major"]),
                _DetailRow(Icons.layers_outlined, "Programs", programs),
                _DetailRow(Icons.security_outlined, "Role", data["role"]),
                _DetailRow(
                  Icons.groups_outlined,
                  "Year / Block",
                  data["yearBlock"],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // SHARED: GLOW BORDER WRAPPER
  // ============================================================

  Widget _glowBorder({
    required Widget child,
    required double radius,
    double thickness = 3,
    double blur = 14,
  }) {
    return Container(
      padding: EdgeInsets.all(thickness),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _accentColor.withOpacity(0.9),
            _accentColor.withOpacity(0.25),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: _accentColor.withOpacity(0.35),
            blurRadius: blur,
            spreadRadius: 1,
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _glowIconChip(IconData icon, {double iconSize = 16}) {
    return _glowBorder(
      radius: 12,
      thickness: 2,
      blur: 12,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          color: _cardColor,
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: iconSize, color: Colors.white),
        ),
      ),
    );
  }

  // ============================================================
  // TITLE BAR
  // ============================================================

  Widget _buildTitleBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '06 / FACULTY WORKSPACE',
          style: TextStyle(
            color: _blue,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'My profile.',
          style: TextStyle(
            color: _ink,
            fontSize: 36,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 7),
        const Text(
          'View your faculty details and academic information.',
          style: TextStyle(color: _muted, fontSize: 13, height: 1.6),
        ),
      ],
    );
  }

  Widget _buildIdentityBanner({
    required String? imageUrl,
    required Map<String, dynamic> data,
    required bool wide,
  }) {
    final name = _text(data['name'], fallback: 'Teacher');
    final teacherId = _text(data['ID'], fallback: 'ID not available');
    final role = _text(data['role'], fallback: 'Teacher');
    final faculty = _text(
      data['major'] ?? data['department'],
      fallback: 'Faculty member',
    );

    final identity = Column(
      crossAxisAlignment: wide
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Text(
          name,
          textAlign: wide ? TextAlign.left : TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: wide ? 30 : 24,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          faculty,
          textAlign: wide ? TextAlign.left : TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 12),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: wide ? WrapAlignment.start : WrapAlignment.center,
          children: [
            _identityChip(Icons.school_outlined, role, filled: false),
            _identityChip(Icons.badge_outlined, teacherId, filled: true),
          ],
        ),
      ],
    );

    final avatar = _buildAvatar(imageUrl, size: wide ? 100 : 88);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(wide ? 28 : 22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_headerColorLight, _headerColor],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, color: _blue),
              const SizedBox(width: 9),
              const Text(
                'ROLE 02 / FACULTY',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  "TEACHER INFORMATION",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          const Divider(height: 1, color: Color(0xFF36373C)),
          SizedBox(height: wide ? 24 : 22),
          if (wide)
            Row(
              children: [
                avatar,
                const SizedBox(width: 24),
                Expanded(child: identity),
              ],
            )
          else
            Column(children: [avatar, const SizedBox(height: 16), identity]),
        ],
      ),
    );
  }

  Widget _buildAvatar(String? imageUrl, {required double size}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 26),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_headerColorLight, _headerColor],
        ),
      ),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              SizedBox(
                width: 96,
                height: 96,
                child: _glowBorder(
                  radius: 22,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(19),
                    child: (imageUrl != null && imageUrl.isNotEmpty)
                        ? Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => fallbackAvatar,
                          )
                        : fallbackAvatar,
                  ),
                ),
              ),
              Positioned(
                bottom: 2,
                right: 2,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: _onlineColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: _headerColor, width: 2.5),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          Text(
            (data["name"] ?? "N/A").toString().toUpperCase(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.4,
            ),
          ),

          const SizedBox(height: 10),

          // ======================================================
          // TEACHER ID BADGE
          // ======================================================
          _glowBorder(
            radius: 30,
            thickness: 1.5,
            blur: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: _cardColor,
                borderRadius: BorderRadius.circular(28.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.badge, size: 14, color: _accentColor),
                  const SizedBox(width: 6),
                  Text(
                    data["ID"]?.toString() ?? "N/A",
                    style: const TextStyle(
                      color: _textColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SECTION HEADER (shared by details zone + info card)
  // ============================================================

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        _glowIconChip(icon),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            color: _textColor,
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(height: 1, color: Colors.white.withOpacity(0.08)),
        ),
      ],
    );
  }

  String _text(Object? value, {String fallback = 'Not provided'}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  Widget _buildInfoCard({
    required String title,
    required String subtitle,
    required IconData headerIcon,
    required List<_DetailRow> rows,
    required int columns,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeading(title, subtitle, headerIcon),
          const SizedBox(height: 14),
          const Divider(height: 1, color: _line),
          LayoutBuilder(
            builder: (context, constraints) {
              final columnCount = columns > 1 && constraints.maxWidth >= 520
                  ? columns
                  : 1;
              if (columnCount == 1) {
                return Column(
                  children: [for (final row in rows) _buildField(row)],
                );
              }

              const gap = 24.0;
              final itemWidth =
                  (constraints.maxWidth - gap * (columnCount - 1)) /
                  columnCount;
              return Wrap(
                spacing: gap,
                children: [
                  for (final row in rows)
                    SizedBox(width: itemWidth, child: _buildField(row)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ============================================================
  // INFO CARD (standalone)
  // ============================================================

  Widget _buildInfoCard({
    required String title,
    required IconData headerIcon,
    required List<_DetailRow> rows,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_cardColor.withOpacity(0.9), _cardColor.withOpacity(0.55)],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(title, headerIcon),
            const SizedBox(height: 8),
            for (int i = 0; i < rows.length; i++)
              _buildDetail(rows[i], shaded: i.isOdd),
          ],
        ),
      ),
    );
  }

  Widget _buildField(_DetailRow row) {
    final value = _text(row.value);
    final missing = value == 'Not provided';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: shaded ? Colors.white.withOpacity(0.03) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(row.icon, size: 16, color: _accentColor.withOpacity(0.8)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.label.toUpperCase(),
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 9,
                    letterSpacing: 0.7,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                SelectableText(
                  value,
                  style: TextStyle(
                    color: missing ? _muted : _ink,
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: missing ? FontWeight.w500 : FontWeight.w700,
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

// ================================================================
// DETAIL ROW MODEL
// ================================================================

class _DetailRow {
  final IconData icon;
  final String label;
  final dynamic value;

  const _DetailRow(this.icon, this.label, this.value);
}
