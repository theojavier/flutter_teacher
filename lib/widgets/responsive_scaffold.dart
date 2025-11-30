// responsive_scaffold.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'nav_header.dart';
import 'package:go_router/go_router.dart';
import 'dart:async';

//  Platform + Web detection
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

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
  bool _isDrawerOpen = false;
  late int selectedIndex;

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    selectedIndex = widget.initialIndex;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 50));
    });
    _loadUserProfile();
  }

  StreamSubscription<DocumentSnapshot>? _profileSubscription;

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

  // Show cached profile if exists
  if (_cachedProfile != null) {
    _updateProfileUI(_cachedProfile!);
  }

  // Cancel previous subscription
  await _profileSubscription?.cancel();

  // Subscribe to Firestore profile
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


  void _refreshProfile() async {
    if (_userId == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(_userId)
        .get();
    if (doc.exists) {
      _updateProfileUI(doc.data()!);
    }
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

    //  only update UI if something actually changed
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
      // still update cache silently, without rebuild
      _cachedProfile = Map<String, dynamic>.from(data);
    }
  }
  //'assets/images/fots_teacher.png'

  @override
  void dispose() {
    _profileSubscription?.cancel();
    super.dispose();
  }

  void _onSelectPage(int index) {
    setState(() => selectedIndex = index);

    switch (index) {
      case 0:
        context.go('/teacher-dashboard');
        break;
      case 1:
        context.go('/teacher-exams');
        break;
      case 2:
        context.go('/teacher-monitoring');
        break;
    }

    // close drawer on mobile
    if (!_isDesktop(context)) {
      Navigator.pop(context);
    }
  }

  //  Centralized desktop detection
    //  Centralized desktop detection
  bool _isDesktop(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    if (kIsWeb) return width >= 900;

    try {
      return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = _isDesktop(context);
    bool isExamHtmlPage = GoRouterState.of(
      context,
    ).uri.path.contains('examhtml');
    const topColor = Color(0xFF0F2B45);

    return Scaffold(
      backgroundColor: Color(0xFF0F2B45),
      appBar: isDesktop
          ? AppBar(
              backgroundColor: topColor,
              elevation: 0,
              centerTitle: true,
              automaticallyImplyLeading: false,
              title: GestureDetector(
                onTap: () => context.go('/teacher-dashboard'),
                child: Image.asset(
                  'assets/images/fots_teacher.png',
                  height: 80,
                  width: 120,
                ),
              ),
              actions: _buildActions(context),
            )
          : AppBar(
              backgroundColor: topColor,
              centerTitle: true,
              automaticallyImplyLeading: false,
              title: GestureDetector(
                onTap: () => context.go('/teacher-dashboard'),
                child: Image.asset(
                  'assets/images/fots_teacher.png',
                  height: 80,
                  width: 120,
                ),
              ),
              leading: (!isDesktop && isExamHtmlPage)
                  ? IgnorePointer(
                      child: IconButton(
                        icon: const Icon(Icons.menu, color: Colors.white),
                        onPressed: () {},
                      ),
                    )
                  : Builder(
                      builder: (ctx) => IconButton(
                        icon: const Icon(Icons.menu, color: Colors.white),
                        onPressed: () => Scaffold.of(ctx).openDrawer(),
                      ),
                    ),

              actions: _buildActions(context),
            ),
      drawer: (!isDesktop && !isExamHtmlPage) ? _buildDrawer(context) : null,
      //drawer: isDesktop ? null : _buildDrawer(context),
      onDrawerChanged: (isOpen) {
        setState(() {
          _isDrawerOpen = isOpen;
        });
      },
      body: Row(
        children: [
          // Desktop sidebar
          if (isDesktop)
            Container(
              width: 260,
              color: Color.fromARGB(255, 17, 50, 80),
              child: Column(
                children: [
                  NavHeader(
                    name: headerName,
                    section: headerSection,
                    profileImageUrl: profileImageUrl,
                    onProfileTap: () {
                      _refreshProfile();
                      context.go('/teacherProfile/$_userId');
                    },
                    // onHistoryTap: () async {
                    //   final prefs = await SharedPreferences.getInstance();
                    //   final studentId = prefs.getString('studentId');
                    //   context.go(
                    //     '/exam-history',
                    //     extra: {'studentId': studentId},
                    //   );
                    // },
                  ),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: _menuTiles(),
                    ),
                  ),
                ],
              ),
            ),

          // Main content
          Expanded(
            child: Stack(
              children: [
                // Your content/iframe
                widget.child,

                // Only block interaction when drawer is open (mobile)
                if (_isDrawerOpen && !isDesktop)
                  IgnorePointer(
                    ignoring: false, // blocks taps below
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(context).maybePop(); // closes drawer
                      },
                      behavior: HitTestBehavior.opaque,
                      child: Container(color: Colors.transparent),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  List<Widget> _menuTiles() => [
    ListTile(
      tileColor: Color(0xFF0F2B45),
      leading: const Icon(Icons.home, color: Colors.white),
      title: const Text('Dashboard', style: TextStyle(color: Color(0xFFE6F0F8))),
      onTap: () => _onSelectPage(0),
    ),
    ListTile(
      tileColor: Color(0xFF0F2B45),
      leading: const Icon(Icons.event, color: Colors.white),
      title: const Text('Exams', style: TextStyle(color: Color(0xFFE6F0F8))),
      onTap: () => _onSelectPage(1),
    ),
    ListTile(
      tileColor: Color(0xFF0F2B45),
      leading: const Icon(Icons.schedule, color: Colors.white),
      title: const Text(
        'Monitoring',
        style: TextStyle(color: Color(0xFFE6F0F8)),
      ),
      onTap: () async {
        if (!mounted) return;
        _onSelectPage(2);
      },
    ),
  ];
  void _logout(BuildContext context) async {
    try {
      // Sign out from Firebase
      await FirebaseAuth.instance.signOut();

      //Clear local storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      //Cancel Firestore subscription to avoid stale data
      await _profileSubscription?.cancel();
      _cachedProfile = null;

      //Navigate to login (optional if GoRouter redirect works)
      if (mounted) {
        context.go('/login');
      }
    } catch (e) {
      debugPrint("Logout failed: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Logout failed")));
      }
    }
  }

  List<Widget> _buildActions(BuildContext context) {
    return [
      PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, color: Colors.white),
        onSelected: (value) {
          if (value == 'logout') {
            _logout(context);
          }
        },
        itemBuilder: (ctx) => const [
          PopupMenuItem(value: 'logout', child: Text('Logout')),
        ],
      ),
    ];
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          NavHeader(
            name: headerName,
            section: headerSection,
            profileImageUrl: profileImageUrl,
            onProfileTap: () {
              if (_userId != null) {
                context.go('/teacherProfile/$_userId');
              }
            },
            // onHistoryTap: () async {
            //   context.go('/exam-history');
            // },
          ),
          ..._menuTiles(),
        ],
      ),
    );
  }
}
