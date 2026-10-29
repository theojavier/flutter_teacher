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

  String _activeRouteKey() {
    final path = GoRouterState.of(context).uri.path;

    if (path.startsWith('/teacher-dashboard')) return '/teacher-dashboard';
    if (path.startsWith('/teacher-schedule')) return '/teacher-schedule';
    if (path.startsWith('/teacher-exams') ||
        path.startsWith('/edit-question')) {
      return '/teacher-exams';
    }
    if (path.startsWith('/teacher-monitoring') ||
        path.startsWith('/exam-monitoring')) {
      return '/teacher-monitoring';
    }
    if (path.startsWith('/student-management')) return '/student-management';
    if (path.startsWith('/teacher-reports')) return '/teacher-reports';
    if (path.startsWith('/teacher-notifications')) return 'notifications';
    if (path.startsWith('/teacherProfile')) return 'profile';
    // end of _activeRouteKey
return switch (selectedIndex) {
  1 => '/teacher-exams',
  2 => '/teacher-schedule',
  3 => '/teacher-monitoring',
  _ => '/teacher-dashboard',
};
  }

  String _initials() {
    final parts = headerName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'T';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : ''))
        .toUpperCase();
  }

  Widget _buildSidebar(String activeRoute) {
    return Container(
      width: 256,
      color: _ink,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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

  Widget _buildDesktopTopBar(String activeRoute) {
    final activeItem = _teacherNavItems.firstWhere(
      (item) => (item.route.isEmpty ? 'profile' : item.route) == activeRoute,
      orElse: () => _teacherNavItems.first,
    );
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 35),
      decoration: BoxDecoration(
        color: _paper,
        border: const Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          Text.rich(
            TextSpan(
              style: const TextStyle(fontSize: 11, letterSpacing: 0.7),
              children: [
                const TextSpan(
                  text: 'WORKSPACE / ',
                  style: TextStyle(color: _muted),
                ),
                TextSpan(
                  text: activeRoute == 'notifications'
                      ? 'NOTIFICATIONS'
                      : activeItem.label.toUpperCase(),
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _blueWash,
              border: Border.all(color: const Color(0xFFD7DEFF)),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'FACULTY WORKSPACE',
              style: TextStyle(
                color: _blueDark,
                fontSize: 10,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 12),
          _notificationButton(),
          const SizedBox(width: 12),
          _profileButton(),
        ],
      ),
    );
  }

  Widget _notificationButton() => const TeacherNotificationBubble();

  Widget _profileButton() {
    return ProfileMenuTrigger(
      avatarUrl: profileImageUrl,
      name: headerName,
      idNumber: headerSection.isNotEmpty ? headerSection : null,
      onViewProfile: _goToProfile,
      onChangePassword: null,
      onLogout: _handleLogout,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = _isDesktop(context);
    final activeRoute = _activeRouteKey();
    final page = widget.detailPage ?? widget.child;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _paper,
      appBar: isDesktop
          ? null
          : AppBar(
              toolbarHeight: 64,
              backgroundColor: _paper,
              foregroundColor: _ink,
              elevation: 0,
              scrolledUnderElevation: 0,
              automaticallyImplyLeading: false,
              titleSpacing: 0,
              leading: Builder(
                builder: (context) => IconButton(
                  tooltip: 'Open navigation',
                  icon: const Icon(Icons.menu_rounded),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
              title: GestureDetector(
                onTap: () => context.go('/teacher-dashboard'),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _TeacherLogo(size: 34),
                    SizedBox(width: 9),
                    Text(
                      'FOTS',
                      style: TextStyle(
                        color: _ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(width: 7),
                    Text(
                      'TEACHER',
                      style: TextStyle(
                        color: _blue,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ],
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
}

class _TeacherLogo extends StatelessWidget {
  final double size;

  const _TeacherLogo({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
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
