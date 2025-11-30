import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class EditProfilePage extends StatefulWidget {
  final String teacherId;

  const EditProfilePage({super.key, required this.teacherId});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  Map<String, dynamic>? userData;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final doc = await FirebaseFirestore.instance
        .collection("users")
        .doc(widget.teacherId)
        .get();

    if (doc.exists) {
      setState(() {
        userData = doc.data()!;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (userData == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Profile image handling
    String? imageUrl = userData?["profileImage"];
    if (imageUrl != null &&
        imageUrl.contains("imgur.com") &&
        !imageUrl.contains("i.imgur.com")) {
      imageUrl = "${imageUrl.replaceAll("imgur.com", "i.imgur.com")}.jpg";
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: const Color(0xFF0F2B45),
              child: const Text(
                "Profile",
                style: TextStyle(
                  color: Color(0xFFE6F0F8),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Card
            Card(
              color: const Color(0xFF0F3B61),
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Profile Image
                    CircleAvatar(
                      radius: 50,
                      backgroundImage: (imageUrl != null && imageUrl.isNotEmpty)
                          ? NetworkImage(imageUrl)
                          : null,
                      backgroundColor: Colors.grey[300],
                      child: (imageUrl == null || imageUrl.isEmpty)
                          ? const Icon(Icons.person, size: 50, color: Colors.white)
                          : null,
                    ),
                    const SizedBox(height: 16),
                    // Personal Details Section
                    _buildSectionTitle("Personal Details"),
                    _buildDetail("ID", userData?["ID"]),
                    _buildDetail("UID", userData?["UID"]),
                    _buildDetail("Name", userData?["name"]),
                    _buildDetail("Gender", userData?["gender"]),
                    _buildDetail("Date of Birth", userData?["dob"] ?? "N/A"),
                    _buildDetail("Civil Status", userData?["civilStatus"]),
                    _buildDetail("Nationality", userData?["nationality"]),
                    _buildDetail("Email", userData?["email"]),
                    const SizedBox(height: 8),
                    // Academic Details Section
                    _buildSectionTitle("Academic Details"),
                    _buildDetail("ID Number", userData?["id number"]),
                    _buildDetail("Major", userData?["major"]),
                    _buildDetail(
                        "Programs", (userData?["programs"] as List?)?.join(", ")),
                    _buildDetail("Role", userData?["role"]),
                    _buildDetail("Year/Block", userData?["yearBlock"]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFFE6F0F8),
          ),
        ),
      );

  Widget _buildDetail(String label, dynamic value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              "$label: ${value ?? 'N/A'}",
              style: const TextStyle(fontSize: 14, color: Color(0xFFE6F0F8)),
            ),
          ),
          const Divider(height: 1, color: Colors.grey),
        ],
      );
}