// responsive_scaffold.dart
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

import 'profile_menu.dart';
import 'teacher_notification_bubble.dart';

class _TeacherNavItem {
  final String label;
  final String route;
  final IconData icon;

  const _TeacherNavItem(this.label, this.route, this.icon);
}

const List<_TeacherNavItem> _teacherNavItems = [
  _TeacherNavItem('Dashboard', '/teacher-dashboard', Icons.home_outlined),
  _TeacherNavItem('Exams', '/teacher-exams', Icons.assignment_outlined),
  _TeacherNavItem('Students', '/student-management', Icons.people_outline),
  _TeacherNavItem(
    'Schedule',
    '/teacher-schedule',
    Icons.calendar_month_outlined,
  ),
  _TeacherNavItem(
    'Monitoring',
    '/teacher-monitoring',
    Icons.visibility_outlined,
  ),
  _TeacherNavItem('Reports', '/teacher-reports', Icons.analytics_outlined),
  _TeacherNavItem('My Profile', '', Icons.person_outline),
];

class ResponsiveScaffold extends StatefulWidget {
  final Widget homePage;
  final Widget examPage;
  final Widget child;
  final Widget schedulePage;
  final int initialIndex;
  final Widget? detailPage;

  const ResponsiveScaffold({
    super.key,
    required this.child,
    required this.homePage,
    required this.examPage,
    required this.schedulePage,
    this.initialIndex = 0,
    this.detailPage,
  });

  @override
  State<ResponsiveScaffold> createState() => _ResponsiveScaffoldState();
}

class _ResponsiveScaffoldState extends State<ResponsiveScaffold> {
  static const Color _paper = Color(0xFFF7F8F6);
  static const Color _ink = Color(0xFF111217);
  static const Color _inkSoft = Color(0xFF1A1B20);
  static const Color _inkLine = Color(0xFF36373C);
  static const Color _muted = Color(0xFF777981);
  static const Color _line = Color(0xFFDCDDDC);
  static const Color _blue = Color(0xFF153CFF);
  static const Color _blueDark = Color(0xFF0727C7);
  static const Color _blueWash = Color(0xFFE9EDFF);

  String? profileImageUrl;
  String headerName = "Loading...";
  String headerSection = "";
  String? _userId;
  Map<String, dynamic>? _cachedProfile;
  late int selectedIndex;
  StreamSubscription<DocumentSnapshot>? _profileSubscription;

  // Needed to close the drawer: this State's context sits ABOVE the Scaffold,
  // so Scaffold.of(context) can't find it.
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    selectedIndex = widget.initialIndex;
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) {
      setState(() {
        headerName = "No user";
        profileImageUrl = null;
        headerSection = "";
      });
      return;
    }

    _userId = firebaseUser.uid;

    if (_cachedProfile != null) {
      _updateProfileUI(_cachedProfile!);
    }

    await _profileSubscription?.cancel();
    _profileSubscription = FirebaseFirestore.instance
        .collection("users")
        .doc(_userId)
        .snapshots()
        .listen((doc) {
          if (!doc.exists) return;
          final data = doc.data()!;
          _updateProfileUI(data);
        });
  }

  void _updateProfileUI(Map<String, dynamic> data) {
    if (!mounted) return;

    var url = (data['profileImage'] as String?) ?? '';
    if (url.isNotEmpty &&
        url.contains('imgur.com') &&
        !url.contains('i.imgur.com')) {
      url = '${url.replaceAll('imgur.com', 'i.imgur.com')}.jpg';
    }

    final newName = data['name'] ?? 'No Name';
    final newSection =
        '${data['program'] ?? ''} ${data['yearBlock'] ?? ''} (${data['semester'] ?? ''})'
            .trim();
    final newImageUrl = url.isNotEmpty ? url : null;

    if (newName != headerName ||
        newSection != headerSection ||
        newImageUrl != profileImageUrl) {
      setState(() {
        headerName = newName;
        headerSection = newSection;
        profileImageUrl = newImageUrl;
        _cachedProfile = Map<String, dynamic>.from(data);
      });
    } else {
      _cachedProfile = Map<String, dynamic>.from(data);
    }
  }

  @override
  void dispose() {
    _profileSubscription?.cancel();
    super.dispose();
  }

  bool _isDesktop(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (kIsWeb) return width >= 900;
    try {
      return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    } catch (_) {
      return false;
    }
  }

  void _closeDrawerIfOpen() {
    final state = _scaffoldKey.currentState;
    if (state != null && state.isDrawerOpen) state.closeDrawer();
  }

  // FIX: context.go() replaces the location, so the browser URL changes and a
  // reload lands on the same page. (context.push() didn't update the URL.)
  void _onSelectPage(_TeacherNavItem item) {
    final route = item.route.isNotEmpty
        ? item.route
        : '/teacherProfile/${_userId ?? FirebaseAuth.instance.currentUser?.uid ?? ''}';
    if (route.endsWith('/')) return;

    setState(() {
      // in _onSelectPage
      selectedIndex = switch (item.route) {
        '/teacher-dashboard' => 0,
        '/teacher-exams' => 1,
        '/teacher-schedule' => 2,
        '/teacher-monitoring' => 3,
        _ => -1,
      };
    });
    _closeDrawerIfOpen();
    context.go(route);
  }

  // Shared handler so both the AppBar's ProfileMenuTrigger and the
  // NavHeader's "My Profile" dropdown option go to the same place.
  void _goToProfile() {
    _loadUserProfile();
    _closeDrawerIfOpen();
    final uid = _userId ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) context.go('/teacherProfile/$uid');
  }

  Future<void> _logout(BuildContext context) async {
    try {
      await FirebaseAuth.instance.signOut();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      await _profileSubscription?.cancel();
      _cachedProfile = null;
      profileImageUrl = null;
      headerName = "Logged out";
      if (mounted) context.go('/login');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Logout failed")));
      }
    }
  }

  Widget _buildSidebar(String activeRoute) {
    return Container(
      width: 276,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.zero,
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_headerColor, _bgColor],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.zero,
        child: Stack(
          children: [
            GestureDetector(
              onTap: () => context.go('/teacher-dashboard'),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(2, 0, 2, 20),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: _inkLine)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Image.asset(
                        'assets/images/teacher-removebg-preview.png',
                        width: 36,
                        height: 36,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'FOTS',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            height: 1,
                          ),
                        ),
                        SizedBox(height: 7),
                        Text(
                          'FACE ON THE SCREEN',
                          style: TextStyle(
                            color: Color(0xFFA1A2AC),
                            fontSize: 9,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(vertical: 20),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _inkSoft,
                border: Border.all(color: _inkLine),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 19,
                    backgroundColor: _blue,
                    backgroundImage:
                        profileImageUrl != null && profileImageUrl!.isNotEmpty
                        ? NetworkImage(profileImageUrl!)
                        : null,
                    child: profileImageUrl == null || profileImageUrl!.isEmpty
                        ? Text(
                            _initials(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          headerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          headerSection.isEmpty
                              ? 'Faculty member'
                              : headerSection,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFFA1A2AA),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(6, 0, 6, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'NAVIGATION',
                    style: TextStyle(
                      color: Color(0xFF9C9DA5),
                      fontSize: 10,
                      letterSpacing: 1,
                    ),
                  ),
                  Text(
                    '01 - 06',
                    style: TextStyle(color: Color(0xFF63646C), fontSize: 10),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: _teacherNavItems.length,
                itemBuilder: (context, index) {
                  final item = _teacherNavItems[index];
                  final itemRoute = item.route.isEmpty ? 'profile' : item.route;
                  final selected = activeRoute == itemRoute;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: SizedBox(
                      height: 46,
                      child: Material(
                        color: selected ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        child: InkWell(
                          onTap: () => _onSelectPage(item),
                          borderRadius: BorderRadius.circular(6),
                          hoverColor: selected
                              ? Colors.transparent
                              : const Color(0xFF23242B),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              children: [
                                Icon(
                                  item.icon,
                                  size: 19,
                                  color: selected
                                      ? _ink
                                      : const Color(0xFFA1A2AB),
                                ),
                                const SizedBox(width: 13),
                                Expanded(
                                  child: Text(
                                    item.label,
                                    style: TextStyle(
                                      color: selected
                                          ? _ink
                                          : const Color(0xFFA1A2AB),
                                      fontSize: 13,
                                      fontWeight: selected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${index + 1}'.padLeft(2, '0'),
                                  style: TextStyle(
                                    color: selected
                                        ? const Color(0xFF62646A)
                                        : const Color(0xFF84858C),
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(top: 16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: _inkLine)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: 4, right: 9),
                    child: Icon(
                      Icons.circle,
                      size: 8,
                      color: Color(0xFF6FE4AA),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TEACHER WORKSPACE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            letterSpacing: 0.5,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          'FACULTY ACCESS / 2026',
                          style: TextStyle(
                            color: Color(0xFFA2A2AA),
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Which menu item is highlighted, taken from the CURRENT URL
  // (so it stays right after a reload). -1 = nothing highlighted.
  int _activeIndexFromRoute() {
    final path = GoRouterState.of(context).uri.path;

    if (path.startsWith('/teacher-dashboard')) return 0;
    if (path.startsWith('/teacher-exams') ||
        path.startsWith('/edit-exam') ||
        path.startsWith('/edit-question') ||
        path.startsWith('/exam-clips')) {
      return 1;
    }
    if (path.startsWith('/teacher-monitoring') ||
        path.startsWith('/exam-monitoring')) {
      return 2;
    }

    return -1; // profile, student-management, etc.
  }

  List<Widget> _buildActions(BuildContext context) {
    return [
      Padding(
        padding: const EdgeInsets.only(right: 12),
        child: ProfileMenuTrigger(
          avatarUrl: profileImageUrl,
          name: headerName,
          idNumber: headerSection,
          onViewProfile: _goToProfile,
          onChangePassword: () {
            confirmChangePassword(context);
          },
          onLogout: () => _logout(context),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = _isDesktop(context);
    final activeRoute = _activeRouteKey();
    final page = widget.detailPage ?? widget.child;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _headerColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: !isDesktop,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_headerColorLight, _headerColor],
            ),
            border: Border(
              bottom: BorderSide(color: Colors.white.withOpacity(0.08)),
            ),
          ),
        ),
        title: GestureDetector(
          // FIX: '/Dashboard' isn't a route -> use the real one.
          onTap: () => context.go('/teacher-dashboard'),
          child: Image.asset(
            'assets/images/fots_teacher.png',
            height: 80,
            width: 120,
          ),
        ),
        leading: isDesktop
            ? null
            : Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu, color: Colors.white),
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
        actions: [
          _notificationButton(),
          const SizedBox(width: 8),
          _profileButton(),
          const SizedBox(width: 12),
        ],
      ),
      drawer: isDesktop
          ? null
          : Drawer(
              width: 284,
              backgroundColor: _ink,
              shape: const RoundedRectangleBorder(),
              child: SafeArea(child: _buildSidebar(activeRoute)),
            ),
      body: isDesktop
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSidebar(activeRoute),
                Expanded(
                  child: Column(
                    children: [
                      _buildDesktopTopBar(activeRoute),
                      Expanded(child: page),
                    ],
                  ),
                ),
              ],
            )
          : page,
    );
  }

  Future<void> _handleLogout() async {
    try {
      await FirebaseAuth.instance.signOut();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      _cachedProfile = null;
      profileImageUrl = null;
      headerName = "Logged out";
      headerSection = "";
      await Future.delayed(const Duration(milliseconds: 50));
      if (!mounted) return;
      context.go('/login');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Logout failed: $e')));
    }
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      backgroundColor: _headerColor,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          NavHeader(
            name: headerName,
            section: headerSection,
            profileImageUrl: profileImageUrl,
            onProfileTap: _goToProfile,
          ),

          const Divider(height: 1, color: Colors.white24),

          ..._menuTiles(),
        ],
      ),
    );
  }

  List<Widget> _menuTiles() => [
    _menuTile(Icons.home, 'Dashboard', 0),
    _menuTile(Icons.event, 'Exams', 1),
    if (_showMonitoringMenu) _menuTile(Icons.schedule, 'Monitoring', 2),
  ];

  Widget _menuTile(IconData icon, String title, int index) {
    final activeIndex = _activeIndexFromRoute();
    final selected = activeIndex == index;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: selected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _accentColor.withOpacity(0.28),
                    _accentColor.withOpacity(0.06),
                  ],
                )
              : null,
          border: Border.all(
            color: selected
                ? _accentColor.withOpacity(0.5)
                : Colors.transparent,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _onSelectPage(index),
            borderRadius: BorderRadius.circular(16),
            splashColor: _accentColor.withOpacity(0.15),
            hoverColor: Colors.white.withOpacity(0.04),
            highlightColor: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 12, 8),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 26,
                    decoration: BoxDecoration(
                      color: selected ? _accentColor : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  const SizedBox(width: 8),

                  _glowChip(icon, active: selected),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: selected
                            ? FontWeight.bold
                            : FontWeight.w600,
                        color: selected
                            ? _textColor
                            : _textColor.withOpacity(0.85),
                      ),
                    ),
                  ),

                  if (selected)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _accentColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _accentColor.withOpacity(0.6),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    )
                  else
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: _mutedTextColor.withOpacity(0.6),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _glowBlob(double size, double opacity) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              _accentColor.withOpacity(opacity),
              _accentColor.withOpacity(0),
            ],
          ),
        ),
      ),
    );
  }

  Widget _glowChip(
    IconData icon, {
    double iconSize = 18,
    double padding = 8,
    double ring = 2,
    double radius = 12,
    bool active = true,
  }) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: active
              ? [_accentColor.withOpacity(0.9), _accentColor.withOpacity(0.25)]
              : [
                  Colors.white.withOpacity(0.18),
                  Colors.white.withOpacity(0.05),
                ],
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: _accentColor.withOpacity(0.35),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Image.asset(
        'assets/images/teacher-removebg-preview.png',
        width: size * 0.86,
        height: size * 0.86,
        fit: BoxFit.contain,
      ),
    );
  }
}
