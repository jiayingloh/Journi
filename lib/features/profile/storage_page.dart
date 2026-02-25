import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class StoragePage extends StatefulWidget {
  const StoragePage({super.key});

  @override
  State<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends State<StoragePage> {
  int _cacheSize = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _calculateCache();
  }

  Future<void> _calculateCache() async {
    setState(() => _isLoading = true);
    try {
      final tempDir = await getTemporaryDirectory();
      int size = await _getDirSize(tempDir);
      
      // Also calculate application documents if needed, but temp is usually cache.
      if (mounted) {
        setState(() {
          _cacheSize = size;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error calculating cache: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<int> _getDirSize(Directory dir) async {
    int total = 0;
    try {
      if (dir.existsSync()) {
        await for (var entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            total += await entity.length();
          }
        }
      }
    } catch (e) {
      debugPrint('Error getting size: $e');
    }
    return total;
  }

  Future<void> _clearCache() async {
    setState(() => _isLoading = true);
    try {
      final tempDir = await getTemporaryDirectory();
      if (tempDir.existsSync()) {
        await for (var entity in tempDir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            await entity.delete();
          } else if (entity is Directory) {
            await entity.delete(recursive: true);
          }
        }
      }
      
      await _calculateCache();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cache completely cleared!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error clearing cache: $e')));
      }
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Storage & Cache Settings'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('App Cache', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('Temporary files (like image thumbnails and media caching) used to make the app run faster. You can safely clear these.', style: TextStyle(color: Colors.grey[600], fontSize: 14)),
                  const SizedBox(height: 24),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade200)
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      leading: const Icon(Icons.storage_rounded, size: 30),
                      title: const Text('Cached Data', style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(_formatSize(_cacheSize), style: const TextStyle(fontSize: 16)),
                      trailing: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Colors.red,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        // Only disable if exactly 0 B
                        onPressed: _cacheSize > 0 ? _clearCache : null,
                        child: const Text('Clear'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
