import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

class EditProfilePage extends StatefulWidget {
  final String teacherId;

  const EditProfilePage({super.key, required this.teacherId});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _formKey = GlobalKey<FormState>();

  String? userId;
  Map<String, dynamic>? userData;

  TextEditingController nameController = TextEditingController();
  TextEditingController idNumberController = TextEditingController();
  TextEditingController genderController = TextEditingController();
  TextEditingController dobController = TextEditingController();
  TextEditingController civilStatusController = TextEditingController();
  TextEditingController nationalityController = TextEditingController();
  TextEditingController imageController = TextEditingController();

  File? pickedImage;

  @override
  void initState() {
    super.initState();
    _loadUserId();
  }

  Future<void> _loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    userId = prefs.getString("userId");

    if (userId != null) {
      final doc = await FirebaseFirestore.instance
          .collection("users")
          .doc(userId)
          .get();

      if (doc.exists) {
        userData = doc.data()!;
        _fillUserData();
        setState(() {});
      }
    }
  }

  void _fillUserData() {
    nameController.text = userData?["name"] ?? "";
    idNumberController.text = userData?["id number"] ?? "";
    genderController.text = userData?["gender"] ?? "";
    dobController.text = userData?["dob"] ?? "";
    civilStatusController.text = userData?["civilStatus"] ?? "";
    nationalityController.text = userData?["nationality"] ?? "";
    imageController.text = userData?["profileImage"] ?? "";
  }

  Future<void> pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);

    if (picked != null) {
      setState(() {
        pickedImage = File(picked.path);
      });
    }
  }

  Future<void> saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    final ref = FirebaseFirestore.instance.collection("users").doc(userId);

    await ref.update({
      "name": nameController.text,
      "id number": idNumberController.text,
      "gender": genderController.text,
      "dob": dobController.text,
      "civilStatus": civilStatusController.text,
      "nationality": nationalityController.text,
      "profileImage": imageController.text, // Can be Imgur URL
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Profile updated successfully!")),
      );

      context.go('/teacher-dashboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (userData == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Edit Profile"),
        backgroundColor: Colors.blue[800],
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.go('/teacher-dashboard'),
        ),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Profile image preview
              Center(
                child: CircleAvatar(
                  radius: 55,
                  backgroundImage: pickedImage != null
                      ? FileImage(pickedImage!)
                      : (imageController.text.isNotEmpty
                                ? NetworkImage(imageController.text)
                                : null)
                            as ImageProvider?,
                  backgroundColor: Colors.grey[300],
                  child: (imageController.text.isEmpty && pickedImage == null)
                      ? const Icon(Icons.person, size: 60, color: Colors.white)
                      : null,
                ),
              ),

              const SizedBox(height: 10),

              ElevatedButton.icon(
                icon: const Icon(Icons.image),
                label: const Text("Choose Image"),
                onPressed: pickImage,
              ),

              const SizedBox(height: 20),

              _buildField("Full Name", nameController),
              _buildField("ID Number", idNumberController),
              _buildField("Gender", genderController),
              _buildField("Date of Birth", dobController),
              _buildField("Civil Status", civilStatusController),
              _buildField("Nationality", nationalityController),

              // Image URL input
              _buildField("Profile Image URL (Imgur)", imageController),

              const SizedBox(height: 25),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[800],
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: saveProfile,
                  child: const Text(
                    "Save Changes",
                    style: TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        validator: (value) {
          if (value == null || value.isEmpty) return "Required field";
          return null;
        },
      ),
    );
  }
}
