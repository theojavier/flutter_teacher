import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EditProfilePage extends StatefulWidget {
  final String teacherId;

  const EditProfilePage({super.key, required this.teacherId});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  // FOTS editorial layout (same as the student ProfilePage) in the teacher blue.
  static const Color _background = Color(0xFFF6F8FD);
  static const Color _ink = Color(0xFF111217);
  static const Color _muted = Color(0xFF6F7276);
  static const Color _blue = Color(0xFF153CFF);
  static const Color _blueMid = Color(0xFF5B7CFF); // lighter tint
  static const Color _cyan = Color(0xFF22B8CF); // accent tint
  static const Color _wash = Color(0xFFE9EDFF);
  static const Color _washBorder = Color(0xFFC9D3FF);
  static const Color _line = Color(0xFFE0E4F0);

  // Tints cycled across class cards: (main, soft background, border)
  static const List<(Color, Color, Color)> _tints = [
    (Color(0xFF153CFF), Color(0xFFE9EDFF), Color(0xFFC9D3FF)), // blue
    (Color(0xFF4F46E5), Color(0xFFEEEDFF), Color(0xFFD3D0FA)), // indigo
    (Color(0xFF0284C7), Color(0xFFE4F4FC), Color(0xFFBFE3F5)), // sky
    (Color(0xFF0F8B9C), Color(0xFFE2F5F7), Color(0xFFB8E2E8)), // teal
  ];

  Map<String, dynamic>? _userData;
  bool _loading = true;
  String? _error;

  List<_TeacherClass> _classes = const [];
  bool _classesLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.teacherId)
          .get();

      if (!mounted) return;
      setState(() {
        _userData = doc.exists ? doc.data() : null;
        _error = doc.exists ? null : 'Profile not found.';
        _loading = false;
      });
      if (doc.exists) _loadClasses(doc.data() ?? {});
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load your profile. Please try again.';
        _loading = false;
      });
    }
  }

  // ============================================================
  // CLASSES
  // ============================================================

  Future<void> _loadClasses(Map<String, dynamic> user) async {
    List<_TeacherClass> result = const [];
    try {
      result = await _fetchClasses(user);
    } catch (_) {
      // keep the empty list
    }
    if (!mounted) return;
    setState(() {
      _classes = result;
      _classesLoading = false;
    });
  }

  Future<List<_TeacherClass>> _fetchClasses(Map<String, dynamic> user) async {
    final fs = FirebaseFirestore.instance;
    final found = <String, Map<String, dynamic>>{};

    // 1) Class ids stored on the teacher's profile.
    final ids = <String>{};
    void addId(Object? v) {
      final s = v?.toString().trim();
      if (s != null && s.isNotEmpty) ids.add(s);
    }

    addId(user['classId']);
    final rawIds = user['classIds'];
    if (rawIds is Iterable) rawIds.forEach(addId);

    for (final id in ids) {
      try {
        final doc = await fs.collection('classes').doc(id).get();
        if (doc.exists && doc.data() != null) found[doc.id] = doc.data()!;
      } catch (_) {}
      try {
        final q = await fs
            .collection('classes')
            .where('classId', isEqualTo: id)
            .get();
        for (final d in q.docs) {
          found[d.id] = d.data();
        }
      } catch (_) {}
    }

    // 2) Classes that point at this teacher.
    final teacherKeys = <String>{
      widget.teacherId,
      if ('${user['ID'] ?? ''}'.trim().isNotEmpty) '${user['ID']}'.trim(),
    };
    for (final key in teacherKeys) {
      for (final query in [
        fs.collection('classes').where('teacherId', isEqualTo: key),
        fs.collection('classes').where('teacherIds', arrayContains: key),
      ]) {
        try {
          final snap = await query.get();
          for (final d in snap.docs) {
            found[d.id] = d.data();
          }
        } catch (_) {}
      }
    }

    // 3) Fallback: build the list from the teacher's own exams.
    if (found.isEmpty) {
      try {
        final snap = await fs
            .collection('exams')
            .where('teacherId', isEqualTo: widget.teacherId)
            .get();
        for (final d in snap.docs) {
          final data = d.data();
          final key =
              '${data['subject']}|${data['program']}|${data['yearBlock']}';
          found.putIfAbsent('exam-$key', () => data);
        }
      } catch (_) {}
    }

    final list = found.entries
        .map((e) => _classFromData(e.key, e.value))
        .toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return list;
  }

  _TeacherClass _classFromData(String id, Map<String, dynamic> data) {
    String pick(List<String> keys) {
      for (final k in keys) {
        final v = data[k]?.toString().trim() ?? '';
        if (v.isNotEmpty) return v;
      }
      return '';
    }

    final classCode = pick(['classId']);
    final title = pick(['subject', 'subjectName', 'name', 'className']);
    final program = pick(['programCode', 'program']);
    final yearBlock = pick(['yearBlock']);

    return _TeacherClass(
      title: title.isNotEmpty
          ? title
          : (classCode.isNotEmpty ? classCode : 'Untitled class'),
      subtitle: [
        if (program.isNotEmpty) program,
        if (yearBlock.isNotEmpty) yearBlock,
      ].join(' · '),
      schoolYear: pick(['schoolYear', 'academicYear']),
      classCode: title.isNotEmpty ? classCode : '',
    );
  }

  // ============================================================
  // HELPERS
  // ============================================================

  String _text(Object? value, [String fallback = 'N/A']) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  String _programs() {
    final list = _userData?['programs'];
    if (list is List && list.isNotEmpty) return list.join(', ');
    return 'N/A';
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty);
    if (parts.isEmpty) return 'TC';
    if (parts.length == 1) {
      final first = parts.first;
      return first
          .substring(0, first.length < 2 ? first.length : 2)
          .toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  String _normaliseImageUrl(String url) {
    if (url.isEmpty) return '';
    if (url.contains('imgur.com') && !url.contains('i.imgur.com')) {
      final clean = url.split('?').first;
      return '${clean.replaceAll('imgur.com', 'i.imgur.com')}.jpg';
    }
    return url;
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _background,
        body: Center(child: CircularProgressIndicator(color: _blue)),
      );
    }

    if (_error != null || _userData == null) {
      return Scaffold(
        backgroundColor: _background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.person_off_outlined, size: 42, color: _muted),
                const SizedBox(height: 12),
                Text(
                  _error ?? 'Profile not found.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _ink, fontSize: 14),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _loading = true;
                      _classesLoading = true;
                      _error = null;
                    });
                    _loadUserData();
                  },
                  style: OutlinedButton.styleFrom(foregroundColor: _blue),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final data = _userData!;
    final name = _text(data['name'] ?? data['displayName'], 'Teacher');
    final imageUrl = _normaliseImageUrl(_text(data['profileImage'], ''));
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 900;

    return Scaffold(
      backgroundColor: _background,
      body: Stack(
        children: [
          const Positioned(
            top: -120,
            right: -100,
            child: _BackgroundGlow(size: 340, color: _blueMid),
          ),
          const Positioned(
            bottom: -170,
            left: -140,
            child: _BackgroundGlow(size: 380, color: _cyan),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                width < 600 ? 16 : 32,
                width < 600 ? 22 : 34,
                width < 600 ? 16 : 32,
                40,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1250),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _Eyebrow('ACCOUNT  /  FACULTY RECORD'),
                      const SizedBox(height: 8),
                      const Text(
                        'My Profile',
                        style: TextStyle(
                          color: _ink,
                          fontSize: 36,
                          height: 1.12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.5,
                        ),
                      ),
                      const SizedBox(height: 9),
                      const Text(
                        'View your faculty details, classes and academic information.',
                        style: TextStyle(
                          color: _muted,
                          fontSize: 13,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 26),
                      if (wide)
                        SizedBox(
                          height: 430, // card height on wide screens
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                flex: 1,
                                child: _profileCard(name, imageUrl),
                              ),
                              const SizedBox(width: 16),
                              Expanded(flex: 2, child: _personalCard()),
                            ],
                          ),
                        )
                      else ...[
                        _profileCard(name, imageUrl),
                        const SizedBox(height: 16),
                        _personalCard(),
                      ],
                      const SizedBox(height: 18),
                      _classesCard(),
                      const SizedBox(height: 18),
                      _academicCard(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // PROFILE CARD (avatar + name + badge)
  // ============================================================

  Widget _profileCard(String name, String imageUrl) {
    final data = _userData!;
    return _Panel(
      padding: const EdgeInsets.all(26),
      child: Column(
        children: [
          Container(
            width: 92,
            height: 92,
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_blue, _cyan], // blue + cyan tint ring
              ),
            ),
            child: ClipOval(
              child: imageUrl.isNotEmpty
                  ? Image.network(
                      imageUrl,
                      width: 86,
                      height: 86,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _avatarFallback(name),
                    )
                  : _avatarFallback(name),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            name.toUpperCase(),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _ink,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -.3,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            _text(data['ID'], 'Teacher ID not set'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _muted,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: _wash,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: _washBorder),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_outlined, color: _blue, size: 14),
                SizedBox(width: 6),
                Text(
                  'TEACHER PROFILE',
                  style: TextStyle(
                    color: _blue,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const Divider(color: _line, height: 1),
          const SizedBox(height: 15),
          _miniInfo(
            Icons.security_outlined,
            'Role',
            _text(data['role'], 'Teacher'),
          ),
          const SizedBox(height: 13),
          _miniInfo(
            Icons.menu_book_outlined,
            'Major',
            _text(data['major'] ?? data['department']),
          ),
        ],
      ),
    );
  }

  Widget _avatarFallback(String name) {
    return Container(
      color: _wash,
      alignment: Alignment.center,
      child: Text(
        _initials(name),
        style: const TextStyle(
          color: _blue,
          fontSize: 25,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _miniInfo(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _blue, size: 17),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: _muted, fontSize: 10)),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // PERSONAL INFORMATION
  // ============================================================

  Widget _personalCard() {
    final data = _userData!;
    final fields = <(String, String, IconData)>[
      (
        'DISPLAY NAME',
        _text(data['name'] ?? data['displayName'], 'Teacher'),
        Icons.person_outline,
      ),
      ('EMAIL', _text(data['email']), Icons.email_outlined),
      ('GENDER', _text(data['gender']), Icons.wc_outlined),
      ('CIVIL STATUS', _text(data['civilStatus']), Icons.favorite_border),
      ('NATIONALITY', _text(data['nationality']), Icons.flag_outlined),
      ('DATE OF BIRTH', _text(data['dob']), Icons.cake_outlined),
    ];

    return _Panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelHeader(
            title: 'Personal information',
            subtitle: 'Your details used across the faculty portal',
            icon: Icons.person_outline,
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final twoColumns = constraints.maxWidth >= 520;
                final fieldWidth = twoColumns
                    ? (constraints.maxWidth - 14) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 14,
                  runSpacing: 16,
                  children: [
                    for (final f in fields)
                      SizedBox(
                        width: fieldWidth,
                        child: _readOnlyField(f.$1, f.$2, f.$3),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _readOnlyField(String label, String value, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label),
        Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: _line),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Icon(icon, size: 15, color: _blueMid),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // CLASSES
  // ============================================================

  Widget _classesCard() {
    final count = _classes.length;
    return _Panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelHeader(
            title: 'My classes',
            subtitle: _classesLoading
                ? 'Loading your classes…'
                : count == 0
                ? 'Classes you handle will appear here'
                : '$count ${count == 1 ? 'class' : 'classes'} you handle',
            icon: Icons.class_outlined,
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: _classesBody(),
          ),
        ],
      ),
    );
  }

  Widget _classesBody() {
    if (_classesLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2, color: _blue),
          ),
        ),
      );
    }

    if (_classes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _wash,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.class_outlined, color: _blue, size: 22),
            ),
            const SizedBox(height: 10),
            const Text(
              'No classes found',
              style: TextStyle(
                color: _ink,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'You have not been assigned to any class yet.',
              style: TextStyle(color: _muted, fontSize: 11),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720
            ? 3
            : (constraints.maxWidth >= 420 ? 2 : 1);
        const gap = 12.0;
        final itemWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: 12,
          children: [
            for (var i = 0; i < _classes.length; i++)
              SizedBox(
                width: itemWidth,
                child: _classTile(_classes[i], _tints[i % _tints.length]),
              ),
          ],
        );
      },
    );
  }

  Widget _classTile(_TeacherClass c, (Color, Color, Color) tint) {
    final (main, soft, border) = tint;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBFE),
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: soft,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: border),
            ),
            child: Icon(Icons.menu_book_outlined, color: main, size: 18),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                  ),
                ),
                if (c.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    c.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 10.5),
                  ),
                ],
                if (c.schoolYear.isNotEmpty || c.classCode.isNotEmpty) ...[
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (c.schoolYear.isNotEmpty)
                        _tag(c.schoolYear, main, soft, border),
                      if (c.classCode.isNotEmpty)
                        _tag(c.classCode, main, soft, border),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tag(String text, Color main, Color soft, Color border) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: border),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: main,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: .3,
        ),
      ),
    );
  }

  // ============================================================
  // ACADEMIC DETAILS
  // ============================================================

  Widget _academicCard() {
    final data = _userData!;
    final details = <(IconData, String, String)>[
      (Icons.badge_outlined, 'TEACHER ID', _text(data['ID'])),
      (
        Icons.confirmation_number_outlined,
        'ID NUMBER',
        _text(data['id number']),
      ),
      (Icons.menu_book_outlined, 'MAJOR', _text(data['major'])),
      (Icons.layers_outlined, 'PROGRAMS', _programs()),
      (Icons.security_outlined, 'ROLE', _text(data['role'])),
      (Icons.groups_outlined, 'YEAR / BLOCK', _text(data['yearBlock'])),
    ];

    return _Panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelHeader(
            title: 'Academic details',
            subtitle: 'Faculty and program information on record',
            icon: Icons.school_outlined,
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 720
                    ? 3
                    : (constraints.maxWidth >= 420 ? 2 : 1);
                const gap = 12.0;
                final itemWidth =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: 12,
                  children: [
                    for (var i = 0; i < details.length; i++)
                      SizedBox(
                        width: itemWidth,
                        child: _detailTile(
                          details[i].$1,
                          details[i].$2,
                          details[i].$3,
                          _tints[i % _tints.length],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailTile(
    IconData icon,
    String label,
    String value,
    (Color, Color, Color) tint,
  ) {
    final (main, soft, border) = tint;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBFE),
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: soft,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: border),
            ),
            child: Icon(icon, color: main, size: 18),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .5,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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
// MODEL
// ================================================================

class _TeacherClass {
  final String title;
  final String subtitle;
  final String schoolYear;
  final String classCode;

  const _TeacherClass({
    required this.title,
    required this.subtitle,
    required this.schoolYear,
    required this.classCode,
  });
}

// ================================================================
// SHARED WIDGETS (same structure as the student ProfilePage, in blue)
// ================================================================

class _Panel extends StatelessWidget {
  const _Panel({required this.child, required this.padding});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .96),
        border: Border.all(color: const Color(0xFFE0E4F0)),
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A153CFF),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 17),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE0E4F0))),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFE9EDFF),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: const Color(0xFF153CFF), size: 19),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF111217),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF6F7276),
                    fontSize: 10,
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

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF666970),
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: .6,
        ),
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF153CFF),
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
      ),
    );
  }
}

class _BackgroundGlow extends StatelessWidget {
  const _BackgroundGlow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: .13),
              color.withValues(alpha: .04),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }
}