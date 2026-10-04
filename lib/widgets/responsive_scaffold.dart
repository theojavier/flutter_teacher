// responsive_scaffold.dart
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

import 'profile_menu.dart'; // ensure this resolves to your widgets/profile_menu.dart
import 'nav_header.dart'; 

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

  // Shared theme palette (matches student scaffold)
  static const Color _bgColor = Color(0xFF0B1220);
  static const Color _headerColor = Color(0xFF0F2B45);
  static const Color _headerColorLight = Color(0xFF17456F);
  static const Color _cardColor = Color(0xFF0F3B61);
  static const Color _textColor = Color(0xFFE6F0F8);
  static const Color _mutedTextColor = Color(0xFF9FB0C3);
  static const Color _accentColor = Color(0xFF3D8BFF);

  // Menu index -> route. Single source of truth for navigation.
  static const List<String> _routes = [
    '/teacher-dashboard',
    '/teacher-exams',
    '/teacher-monitoring',
  ];

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
  void _onSelectPage(int index) {
    setState(() => selectedIndex = index);
    _closeDrawerIfOpen();
    context.go(_routes[index]);
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

  Widget _buildSidebar(int activeIndex) {
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
            Positioned(top: -70, right: -70, child: _glowBlob(220, 0.22)),

            Positioned(bottom: 90, left: -100, child: _glowBlob(240, 0.10)),

            Positioned.fill(
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
        path.startsWith('/edit-question')) {
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: ProfileMenuTrigger(
                avatarUrl: profileImageUrl,
                name: headerName,
                idNumber: headerSection.isNotEmpty ? headerSection : null,
                // FIX: '/profile' isn't a route -> use the shared handler.
                onViewProfile: _goToProfile,
                onChangePassword: null,
                onLogout: _handleLogout,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: isDesktop ? null : _buildDrawer(context),
      body: Row(
        children: [
          // DESKTOP SIDEBAR
          if (isDesktop) _buildSidebar(_activeIndexFromRoute()),

          // PAGE CONTENT
          Expanded(child: widget.detailPage ?? widget.child),
        ],
      ),
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

    _menuTile(Icons.schedule, 'Monitoring', 2),
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
      padding: EdgeInsets.all(ring),
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - ring),
        child: Container(
          color: _cardColor,
          padding: EdgeInsets.all(padding),
          child: Icon(
            icon,
            size: iconSize,
            color: active ? Colors.white : _mutedTextColor,
          ),
        ),
      ),
    );
  }
}