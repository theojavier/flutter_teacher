import 'package:flutter/material.dart';
import 'manage_activity.dart';
import 'flags.dart';
import 'history_track.dart';
import 'profile.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;

class TeacherDashboard extends StatefulWidget {
  const TeacherDashboard({super.key});

  @override
  State<TeacherDashboard> createState() => _TeacherDashboardState();
}

class _TeacherDashboardState extends State<TeacherDashboard> {
  int _selectedIndex = 0;

  static final List<Widget> _pages = <Widget>[
    const ManageActivityPage(),
    const FlagsPage(),
    const HistoryTrackPage(),
    const ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      body: SafeArea(
        child: Row(
          children: [
            if (isDesktop) _buildSidebar(context),
            Expanded(
              child: Column(
                children: [
                  _buildTopBar(),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      color: Colors.white,
                      child: _pages[_selectedIndex],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: !isDesktop ? _buildBottomNav() : null,
    );
  }

  // Sidebar for Desktop
  Widget _buildSidebar(BuildContext context) {
    return Container(
      width: 240,
      color: Colors.white,
      child: Column(
        children: [
          Container(
            height: 70,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerLeft,
            child: const Text(
              'Faculty Panel',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
            ),
          ),
          const Divider(),
          _buildNavItem(Icons.edit, "Manage", 0),
          _buildNavItem(Icons.flag, "Flags", 1),
          _buildNavItem(Icons.history, "History", 2),
          _buildNavItem(Icons.person, "Profile", 3),
          const Spacer(),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text("Logout"),
            onTap: () {
              Navigator.pushReplacementNamed(context, '/login');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    final selected = _selectedIndex == index;
    return ListTile(
      leading: Icon(
        icon,
        color: selected ? Colors.deepPurple : Colors.grey[700],
      ),
      title: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.deepPurple : Colors.grey[700],
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      tileColor: selected ? Colors.deepPurple.withOpacity(0.1) : null,
      onTap: () => setState(() => _selectedIndex = index),
    );
  }

  // Top bar for desktop
  Widget _buildTopBar() {
    return Container(
      height: 60,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Text(
            _getPageTitle(),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const Spacer(),
          Row(
            children: const [
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.deepPurple,
                child: Icon(Icons.person, color: Colors.white),
              ),
              SizedBox(width: 8),
              Text("Teacher User"),
            ],
          ),
        ],
      ),
    );
  }

  // Bottom navigation bar for mobile
  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _selectedIndex,
      selectedItemColor: Colors.deepPurple,
      unselectedItemColor: Colors.grey,
      onTap: (i) => setState(() => _selectedIndex = i),
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.edit), label: 'Manage'),
        BottomNavigationBarItem(icon: Icon(Icons.flag), label: 'Flags'),
        BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
        BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
      ],
    );
  }

  String _getPageTitle() {
    switch (_selectedIndex) {
      case 0:
        return 'Manage Activities';
      case 1:
        return 'Flags';
      case 2:
        return 'History Tracking';
      case 3:
        return 'Profile';
      default:
        return '';
    }
  }
}
