import 'package:flutter/material.dart';

class NavHeader extends StatelessWidget {
  final String name;
  final String section;
  final String? profileImageUrl;

  const NavHeader({
    super.key,
    required this.name,
    required this.section,
    this.profileImageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 160,
      width: double.infinity,
      child: UserAccountsDrawerHeader(
        margin: EdgeInsets.zero,
        decoration: const BoxDecoration(color: Color(0xFF0F2B45)),
        accountName: Text(
          name,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFFE6F0F8),
          ),
        ),
        accountEmail: Text(
          section,
          style: const TextStyle(color: Colors.white70),
        ),
        currentAccountPicture: CircleAvatar(
          backgroundColor: const Color(0xFF0F2B45),
          child: profileImageUrl != null
              ? ClipOval(
                  child: Image.network(
                    profileImageUrl!,
                    key: ValueKey(profileImageUrl),
                    fit: BoxFit.cover,
                    width: 80,
                    height: 80,
                  ),
                )
              : const Icon(Icons.person, size: 40, color: Colors.grey),
        ),
      ),
    );
  }
}
