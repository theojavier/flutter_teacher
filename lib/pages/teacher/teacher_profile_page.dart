import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EditProfilePage extends StatefulWidget {
  final String teacherId;

  const EditProfilePage({super.key, required this.teacherId});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  // Shared theme palette
  static const Color _bgColor = Color(0xFF0B1220);
  static const Color _headerColor = Color(0xFF0F2B45);
  static const Color _headerColorLight = Color(0xFF17456F);
  static const Color _cardColor = Color(0xFF0F3B61);
  static const Color _textColor = Color(0xFFE6F0F8);
  static const Color _mutedTextColor = Color(0xFF9FB0C3);
  static const Color _accentColor = Color(0xFF3D8BFF);
  static const Color _onlineColor = Color(0xFF4ADE80);

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
        backgroundColor: _bgColor,
        body: Center(
          child: CircularProgressIndicator(color: _accentColor),
        ),
      );
    }

    if (userData == null) {
      return const Scaffold(
        backgroundColor: _bgColor,
        body: Center(
          child: Text(
            "Profile not found",
            style: TextStyle(color: _textColor),
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

    // Programs list -> "A, B, C"
    final programsList = data["programs"];
    final programs = programsList is List && programsList.isNotEmpty
        ? programsList.join(", ")
        : null;

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
                        _DetailRow(Icons.favorite_border, "Civil Status",
                            data["civilStatus"]),
                        _DetailRow(Icons.flag_outlined, "Nationality",
                            data["nationality"]),
                        _DetailRow(
                            Icons.cake_outlined, "Date of Birth", data["dob"]),
                        _DetailRow(Icons.email_outlined, "Email", data["email"]),
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
                _DetailRow(Icons.confirmation_number_outlined, "ID Number",
                    data["id number"]),
                _DetailRow(Icons.menu_book_outlined, "Major", data["major"]),
                _DetailRow(Icons.layers_outlined, "Programs", programs),
                _DetailRow(Icons.security_outlined, "Role", data["role"]),
                _DetailRow(
                    Icons.groups_outlined, "Year / Block", data["yearBlock"]),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
          _glowBorder(
            radius: 15,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                color: _cardColor,
                padding: const EdgeInsets.all(10),
                child: const Icon(
                  Icons.school_outlined,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "My Profile",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 5),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
        ],
      ),
    );
  }

  // ============================================================
  // AVATAR ZONE
  // ============================================================

  Widget _buildAvatarZone(String? imageUrl, Map<String, dynamic> data) {
    final fallbackAvatar = Container(
      color: _cardColor,
      child: const Icon(Icons.person, size: 44, color: _mutedTextColor),
    );

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
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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
          child: Container(
            height: 1,
            color: Colors.white.withOpacity(0.08),
          ),
        ),
      ],
    );
  }

  // ============================================================
  // DETAILS ZONE (inside the header card)
  // ============================================================

  Widget _buildDetailsZone({
    required String title,
    required IconData headerIcon,
    required List<_DetailRow> rows,
  }) {
    return Container(
      width: double.infinity,
      color: _cardColor,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(title, headerIcon),
          const SizedBox(height: 8),
          for (int i = 0; i < rows.length; i++)
            _buildDetail(rows[i], shaded: i.isOdd),
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
          colors: [
            _cardColor.withOpacity(0.9),
            _cardColor.withOpacity(0.55),
          ],
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

  // ============================================================
  // DETAIL ROW
  // ============================================================

  Widget _buildDetail(_DetailRow row, {required bool shaded}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: shaded ? Colors.white.withOpacity(0.03) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(row.icon, size: 16, color: _accentColor.withOpacity(0.8)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              row.label,
              style: const TextStyle(fontSize: 13, color: _mutedTextColor),
            ),
          ),
          Flexible(
            child: Text(
              (row.value ?? "N/A").toString(),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _textColor,
              ),
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