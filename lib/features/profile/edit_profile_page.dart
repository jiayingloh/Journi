import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart'; 
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';
import '../../core/services/media_service.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final _picker = ImagePicker();
  final _supabase = Supabase.instance.client;
  
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  
  bool _isLoading = false;
  String? _avatarUrl;
  File? _selectedImage;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final user = _supabase.auth.currentUser;
    if (user != null) {
      _emailController.text = user.email ?? '';
      
      // 1. Load from DB (Cache)
      final data = await _supabase
          .from('users')
          .select()
          .eq('id', user.id)
          .maybeSingle();
          
      if (data != null && mounted) {
        setState(() {
          _nameController.text = data['name'] ?? '';
          _avatarUrl = MediaService.getPublicUrl(data['avatar_url']);
        });
      }
    }
  }

  // 1. Pick Image
  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );

    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
      });
      // Show confirm dialog immediately after picking
      _showConfirmDialog(
        'Update Profile Picture?',
        'Do you want to upload this image as your new profile picture?',
        () => _saveField('avatar'),
      );
    }
  }

  // 2. Upload to Supabase Edge Function -> Backblaze B2
  Future<String?> _uploadAvatar(File imageFile) async {
    try {
      return await MediaService.uploadAvatar(imageFile);
    } catch (e) {
      debugPrint('Upload Error: $e');
      if (e.toString().contains('401')) {
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Session expired. Please Log Out and Log In again.')),
           );
        }
      }
      rethrow;
    }
  }



  Future<void> _saveField(String field) async {
    setState(() => _isLoading = true);
    try {
       final user = _supabase.auth.currentUser;
       if (user == null) return;
       
       if (field == 'name') {
         await _supabase.from('users').update({
           'name': _nameController.text.trim(),
         }).eq('id', user.id);
       } else if (field == 'email') {
         await _supabase.auth.updateUser(UserAttributes(email: _emailController.text.trim()));
       } else if (field == 'password') {
         if (_passwordController.text.isNotEmpty) {
           await _supabase.auth.updateUser(UserAttributes(password: _passwordController.text));
         }
       } else if (field == 'avatar' && _selectedImage != null) {
          final newUrl = await _uploadAvatar(_selectedImage!);
          if (newUrl != null) {
            await _supabase.from('users').update({
             'avatar_url': newUrl,
           }).eq('id', user.id);
           setState(() => _avatarUrl = newUrl);
          }
       }
       
       String message = 'Updated successfully!';
       if (field == 'email') {
         message = 'Please check your email to verify the new address.';
       }

       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
       }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showConfirmDialog(String title, String content, VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onConfirm();
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  String? _editingField; // Tracks which field is being edited

  // ... (rest of methods)

  Widget _buildEditableField({
    required String fieldKey,
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    String? Function(String?)? validator,
    String? helperText,
  }) {
    final isEditing = _editingField == fieldKey;
    
    return Stack(
      alignment: Alignment.centerRight,
      children: [
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          enabled: isEditing, // Only editable when active
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon),
            helperText: helperText, // Keep helper text logic if any
            hintText: obscureText && !isEditing ? '**********' : null, // Show asterisks as hint when not editing
            hintStyle: const TextStyle(letterSpacing: 2.0), // Make asterisks look nice
            floatingLabelBehavior: FloatingLabelBehavior.always, // Keep label up
            border: isEditing ? const OutlineInputBorder() : InputBorder.none,
            filled: isEditing,
          ),
          validator: validator,
        ),
        IconButton(
          icon: Icon(isEditing ? Icons.check : Icons.edit, color: isEditing ? Colors.green : Colors.grey),
          onPressed: () {
            if (isEditing) {
              // Finish Editing -> Show Confirm
              _showConfirmDialog(
                'Update $label?',
                'Are you sure you want to update this?',
                () {
                  _saveField(fieldKey);
                  setState(() => _editingField = null); // Exit edit mode
                },
              );
            } else {
              // Start Editing
              setState(() => _editingField = fieldKey);
            }
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Current theme colors
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Profile'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Avatar (Keep existing logic)
              GestureDetector(
                onTap: _pickImage,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 60,
                      backgroundColor: (_selectedImage == null && (_avatarUrl == null || _avatarUrl!.isEmpty)) ? Colors.blue[100] : Colors.transparent,
                      backgroundImage: _selectedImage != null
                          ? FileImage(_selectedImage!) as ImageProvider
                          : ((_avatarUrl != null && _avatarUrl!.isNotEmpty) ? NetworkImage(_avatarUrl!) as ImageProvider : null),
                      child: (_selectedImage == null && (_avatarUrl == null || _avatarUrl!.isEmpty))
                          ? Text(
                              _nameController.text.isNotEmpty ? _nameController.text[0].toUpperCase() : 'U',
                              style: TextStyle(
                                color: Colors.blue[900],
                                fontSize: 48,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                        ),
                        child: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              _buildEditableField(
                fieldKey: 'name',
                controller: _nameController,
                label: 'Full Name',
                icon: Icons.person_outline,
                validator: (v) => v!.isEmpty ? 'Name required' : null,
              ),
              
              const SizedBox(height: 20),
              
              _buildEditableField(
                fieldKey: 'email',
                controller: _emailController,
                label: 'Email Address',
                icon: Icons.email_outlined,
                validator: (v) => v!.contains('@') ? null : 'Invalid email',
              ),
              
              const SizedBox(height: 20),
              
              _buildEditableField(
                fieldKey: 'password',
                controller: _passwordController,
                label: 'New Password',
                icon: Icons.lock_outline,
                obscureText: true,
              ),
              
              const SizedBox(height: 48),
              
              // Save Button Removed
              if (_isLoading)
                 const Center(child: CircularProgressIndicator()),
              
              // Add extra spacing at bottom for scrolling
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}
