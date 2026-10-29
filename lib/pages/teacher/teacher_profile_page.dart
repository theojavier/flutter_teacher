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
      backgroundColor: _paper,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1100;
            final medium = constraints.maxWidth >= 700;
            final padding = wide
                ? 40.0
                : medium
                ? 28.0
                : 16.0;

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                padding,
                wide ? 38 : 22,
                padding,
                wide ? 72 : 32,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildTitleBar(),
                      SizedBox(height: wide ? 26 : 20),
                      _buildIdentityBanner(
                        imageUrl: imageUrl,
                        data: data,
                        wide: medium,
                      ),
                      const SizedBox(height: 16),
                      if (wide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: _buildInfoCard(
                                title: 'Personal Details',
                                subtitle: 'Basic information on record',
                                headerIcon: Icons.badge_outlined,
                                rows: personalRows,
                                columns: 2,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 2,
                              child: _buildInfoCard(
                                title: 'Academic Details',
                                subtitle: 'Faculty and program information',
                                headerIcon: Icons.school_outlined,
                                rows: academicRows,
                                columns: 1,
                              ),
                            ),
                          ],
                        )
                      else ...[
                        _buildInfoCard(
                          title: 'Personal Details',
                          subtitle: 'Basic information on record',
                          headerIcon: Icons.badge_outlined,
                          rows: personalRows,
                          columns: medium ? 2 : 1,
                        ),
                        const SizedBox(height: 16),
                        _buildInfoCard(
                          title: 'Academic Details',
                          subtitle: 'Faculty and program information',
                          headerIcon: Icons.school_outlined,
                          rows: academicRows,
                          columns: medium ? 2 : 1,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
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
        color: _ink,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, color: _blue),
              const SizedBox(width: 9),
              const Text(
                'ROLE 02 / FACULTY',
                style: TextStyle(
                  color: Color(0xFFA1A1AA),
                  fontSize: 10,
                  letterSpacing: 0.7,
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
      width: size,
      height: size,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1D23),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _blue, width: 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: imageUrl != null && imageUrl.isNotEmpty
            ? Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _avatarPlaceholder(),
              )
            : _avatarPlaceholder(),
      ),
    );
  }

  Widget _avatarPlaceholder() => Container(
    color: const Color(0xFF1D1D23),
    alignment: Alignment.center,
    child: const Icon(Icons.person_outline_rounded, color: _blue, size: 40),
  );

  Widget _identityChip(IconData icon, String label, {required bool filled}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: filled ? _blue : const Color(0xFF1D1D23),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: filled ? _blue : const Color(0xFF37373D)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stateMessage({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      margin: const EdgeInsets.all(24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _blue, size: 32),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: _ink,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 12, height: 1.5),
          ),
        ],
      ),
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

  Widget _sectionHeading(String title, String subtitle, IconData icon) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: _blueWash,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: _blue, size: 19),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildField(_DetailRow row) {
    final value = _text(row.value);
    final missing = value == 'Not provided';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(row.icon, size: 17, color: _blue),
          ),
          const SizedBox(width: 12),
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
