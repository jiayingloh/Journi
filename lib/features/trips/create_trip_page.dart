import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_config.dart';
import '../../core/services/media_service.dart';
import '../../core/services/notification_service.dart';
import 'invite_people_page.dart';

class CreateTripPage extends StatefulWidget {
  const CreateTripPage({super.key});

  @override
  State<CreateTripPage> createState() => _CreateTripPageState();
}

class _CreateTripPageState extends State<CreateTripPage> {
  final _supabase = Supabase.instance.client;
  final _picker = ImagePicker();
  
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _startDateController = TextEditingController();
  final _endDateController = TextEditingController();
  
  File? _selectedImage;
  bool _isLoading = false;
  DateTime? _startDate;
  DateTime? _endDate;

  final List<Map<String, dynamic>> _invitedPeople = [];

  @override
  void dispose() {
    _nameController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Create New Trip', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildSectionLabel('Trip Name'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  hintText: 'e.g., European Grand Tour 2024',
                ),
                validator: (v) => v!.isEmpty ? 'Please enter a trip name' : null,
              ),
              
              const SizedBox(height: 24),
              _buildSectionLabel('Cover Photo'),
              const SizedBox(height: 12),
              
              // Photo Uploader Placeholder
              GestureDetector(
                onTap: _pickImage,
                child: Container(
                  height: 180,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!, style: BorderStyle.none),
                    image: _selectedImage != null
                        ? DecorationImage(
                            image: FileImage(_selectedImage!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: _selectedImage == null
                      ? CustomPaint(
                          painter: _DottedBorderPainter(),
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.image_outlined, size: 48, color: Colors.grey[600]),
                                const SizedBox(height: 8),
                                Text('Tap to select a photo', style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                        )
                      : null,
                ),
              ),

              const SizedBox(height: 24),
              _buildSectionLabel('Trip Dates'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _startDateController,
                      readOnly: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.calendar_today_outlined),
                        hintText: 'Start Date',
                      ),
                      validator: (v) => v!.isEmpty ? 'Select start date' : null,
                      onTap: () => _selectDate(isStart: true),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _endDateController,
                      readOnly: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.calendar_today_outlined),
                        hintText: 'End Date',
                      ),
                      validator: (v) => v!.isEmpty ? 'Select end date' : null,
                      onTap: () => _selectDate(isStart: false),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),
              _buildSectionLabel('Invite People'),
              const SizedBox(height: 12),
              
              // Invite Placeholder
              GestureDetector(
                onTap: () async {
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const InvitePeoplePage(),
                    ),
                  );
                  if (result != null && result is List<Map<String, dynamic>>) {
                    setState(() {
                      for (var user in result) {
                        if (!_invitedPeople.any((p) => p['id'] == user['id'])) {
                          _invitedPeople.add({
                            'id': user['id'],
                            'name': user['name'] ?? 'Unknown',
                            'avatar_url': user['avatar_url'] != null ? MediaService.getPublicUrl(user['avatar_url']!) : null,
                          });
                        }
                      }
                    });
                  }
                },
                child: Container(
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: CustomPaint(
                    painter: _DottedBorderPainter(),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF2563EB),
                            ),
                            child: const Icon(Icons.add, color: Colors.white),
                          ),
                          const SizedBox(height: 8),
                          Text('Tap to invite people', style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // Invitees List
              // Invitees List
              ..._invitedPeople.map((p) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle, color: Color(0xFFFF6B6B)),
                      onPressed: () {
                        setState(() => _invitedPeople.remove(p));
                      },
                    ),
                    const SizedBox(width: 8),
                    CircleAvatar(
                      backgroundColor: Colors.blue[100],
                      backgroundImage: p['avatar_url'] != null && p['avatar_url'].toString().isNotEmpty ? NetworkImage(p['avatar_url']) : null,
                      radius: 18,
                      child: (p['avatar_url'] == null || p['avatar_url'].toString().isEmpty) 
                          ? Text(p['name'].toString().isNotEmpty ? p['name'][0].toUpperCase() : 'U', style: TextStyle(color: Colors.blue[900], fontWeight: FontWeight.bold)) 
                          : null,
                    ),
                  ],
                ),
                title: Text(p['name']!, style: TextStyle(color: theme.textTheme.bodyLarge?.color ?? Colors.black87)),
              )).toList(),

              const SizedBox(height: 48),
              ElevatedButton(
                onPressed: _isLoading ? null : _createTrip,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56),
                  backgroundColor: const Color(0xFF3B5BDB),
                ),
                child: _isLoading 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Create Trip', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black87,
      ),
    );
  }

  // --- Logic Implementation ---

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
      });
    }
  }

  Future<void> _selectDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? DateTime.now() : (_startDate ?? DateTime.now()),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
          _startDateController.text = DateFormat('yyyy-MM-dd').format(picked);
          // Auto clear end date if it becomes invalid
          if (_endDate != null && _endDate!.isBefore(_startDate!)) {
            _endDate = null;
            _endDateController.clear();
          }
        } else {
          _endDate = picked;
          _endDateController.text = DateFormat('yyyy-MM-dd').format(picked);
        }
      });
    }
  }



  Future<void> _createTrip() async {
    if (!_formKey.currentState!.validate()) return;
    if (_endDate != null && _startDate != null && _endDate!.isBefore(_startDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('End date cannot be before start date')));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw 'Not logged in';

      // 1. Upload Cover Photo if selected
      String? coverUrl;
      if (_selectedImage != null) {
        coverUrl = await MediaService.uploadAvatar(_selectedImage!);
      }

      // 2. Insert Trip
      final tripRes = await _supabase.from('trips').insert({
        'trip_name': _nameController.text.trim(),
        'created_by': user.id,
        'start_date': _startDate?.toIso8601String(),
        'end_date': _endDate?.toIso8601String(),
        'cover_photo_url': coverUrl,
      }).select().single();

      final tripId = tripRes['id'];

      // 3. Add Creator to user_trips
      await _supabase.from('user_trips').insert({
        'user_id': user.id,
        'trip_id': tripId,
      });

      // 4. Handle Invites
      if (_invitedPeople.isNotEmpty) {
        for (var p in _invitedPeople) {
           try {
             await NotificationService.sendTripInvite(
               tripId: tripId,
               tripName: _nameController.text.trim(),
               recipientId: p['id'],
             );
           } catch (e) {
             debugPrint('Failed to send invite to ${p['id']}: $e');
           }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Trip created successfully!')));
        Navigator.pop(context, true); // Return success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error creating trip: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

class _DottedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey[300]!
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, size.width, size.height), const Radius.circular(12)), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
