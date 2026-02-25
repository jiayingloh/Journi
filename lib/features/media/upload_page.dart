import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'custom_gallery_picker.dart';
import '../../core/providers/upload_provider.dart';

class UploadPage extends StatefulWidget {
  final String tripId;
  const UploadPage({super.key, required this.tripId});

  @override
  State<UploadPage> createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  List<File> _selectedFiles = [];

  Future<void> _pickMedia() async {
    final List<File>? result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CustomGalleryPicker(),
      ),
    );

    if (result != null && result.isNotEmpty) {
      setState(() {
        _selectedFiles = [..._selectedFiles, ...result];
      });
    }
  }

  Future<void> _startUpload() async {
    if (_selectedFiles.isEmpty) return;
    
    // Hand off to Provider
    context.read<UploadProvider>().uploadFiles(_selectedFiles, widget.tripId);
    
    // Notify User
    if (mounted) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(
           content: Text('Upload started in background. You can navigate away.'),
           duration: Duration(seconds: 4),
         ),
       );
       
       // Close Page
       Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upload Media')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300, width: 2),
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.grey.shade50,
                ),
                child: _selectedFiles.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.perm_media_outlined, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text('Select photos & videos', style: TextStyle(color: Colors.grey.shade600)),
                          ],
                        ),
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: _selectedFiles.length,
                        itemBuilder: (context, index) {
                          final file = _selectedFiles[index];
                          final isVideo = file.path.toLowerCase().endsWith('.mp4') || 
                                          file.path.toLowerCase().endsWith('.mov');
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(file, fit: BoxFit.cover, errorBuilder: (_,__,___) {
                                   return Container(color: Colors.grey[300], child: const Icon(Icons.videocam));
                                }),
                              ),
                              if (isVideo)
                                const Center(child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 32)),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() => _selectedFiles.removeAt(index));
                                  },
                                  child: Container(
                                    decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                    child: const Icon(Icons.close, size: 16, color: Colors.white),
                                  ),
                                ),
                              )
                            ],
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(height: 24),
            
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _pickMedia,
                icon: const Icon(Icons.add_photo_alternate),
                label: const Text('Select Media'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _selectedFiles.isNotEmpty ? _startUpload : null,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
              ),
              child: Text('Upload ${_selectedFiles.isNotEmpty ? "(${_selectedFiles.length})" : ""}'),
            ),
          ],
        ),
      ),
    );
  }
}
