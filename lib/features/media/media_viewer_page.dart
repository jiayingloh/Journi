import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/media_service.dart';

/// Requests gallery save permission, handling iOS-specific quirks.
/// Returns true if the app can save to the gallery.
/// Shows a Settings dialog if permission is permanently denied.
Future<bool> _requestGalPermission(BuildContext context) async {
  // On iOS, Gal.hasAccess() checks for "Add Photos Only" auth.
  // If the user only granted "Limited" library access (not add-only),
  // this returns false. We must call requestAccess() which may show the
  // system prompt. If it still fails, the only recourse is Settings.
  try {
    if (await Gal.hasAccess()) return true;
    if (await Gal.requestAccess()) return true;
  } catch (_) {}

  // Permission denied — guide user to Settings
  if (context.mounted) {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permission Required'),
        content: const Text(
          'Journi needs permission to save photos & videos to your library.\n\n'
          'Please go to Settings → Journi → Photos and choose "Add Photos Only" or "All Photos".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              // Open app settings so the user can change the permission
              Gal.open(); 
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
  return false;
}

class MediaViewerPage extends StatefulWidget {
  final List<Map<String, dynamic>> mediaItems;
  final int initialIndex;

  const MediaViewerPage({
    super.key,
    required this.mediaItems,
    required this.initialIndex,
  });

  @override
  State<MediaViewerPage> createState() => _MediaViewerPageState();
}

class _MediaViewerPageState extends State<MediaViewerPage> {
  late PageController _pageController;
  int _currentIndex = 0;
  bool _isLiked = false;
  final _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _checkFavoriteStatus();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _checkFavoriteStatus() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final item = widget.mediaItems[_currentIndex];
      final mediaId = item['id'];

      final res = await _supabase
          .from('favorites') 
          .select('user_id')
          .eq('user_id', user.id)
          .eq('media_id', mediaId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _isLiked = res != null;
        });
      }
    } catch (e) {
      // Table might not exist or other error
      debugPrint('Error checking favorite: $e');
    }
  }

  Future<void> _toggleFavorite() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final item = widget.mediaItems[_currentIndex];
      final mediaId = item['id'];

      if (_isLiked) {
        // Unlike
        await _supabase
            .from('favorites')
            .delete()
            .eq('user_id', user.id)
            .eq('media_id', mediaId);
            
        item['favorite_count'] = (item['favorite_count'] as int? ?? 1) - 1;
      } else {
        // Like
        await _supabase
            .from('favorites')
            .insert({'user_id': user.id, 'media_id': mediaId});
            
        item['favorite_count'] = (item['favorite_count'] as int? ?? 0) + 1;
      }

      if (mounted) {
        setState(() {
          _isLiked = !_isLiked;
        });
      }
    } catch (e) {
      debugPrint('Error toggling favorite: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _downloadMedia() async {
    try {
      final item = widget.mediaItems[_currentIndex];
      final url = item['public_url'] as String? ?? MediaService.getPublicUrl(item['b2_path']);
      final type = item['media_type'] as String?; // 'image' or 'video'

      if (url == null || url.isEmpty) return;

      // Check / request permission (shows Settings dialog if denied)
      final hasAccess = await _requestGalPermission(context);
      if (!hasAccess) return;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('Downloading...')),
        );
      }

      // 1. Download File
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) throw 'Failed to download file';

      final tempDir = await getTemporaryDirectory();
      
      String ext = type == 'video' ? 'mp4' : 'jpg';
      final contentType = response.headers['content-type']?.toLowerCase() ?? '';
      if (contentType.contains('png')) ext = 'png';
      else if (contentType.contains('jpeg') || contentType.contains('jpg')) ext = 'jpg';
      else if (contentType.contains('heic')) ext = 'heic';
      else if (contentType.contains('webp')) ext = 'webp';
      else if (contentType.contains('gif')) ext = 'gif';
      else if (contentType.contains('mp4')) ext = 'mp4';
      else if (contentType.contains('mov') || contentType.contains('quicktime')) ext = 'mov';
      else if (url.contains('.')) {
         final uri = Uri.parse(url);
         final lastSegment = uri.pathSegments.last;
         if (lastSegment.contains('.')) {
           ext = lastSegment.split('.').last.toLowerCase();
         }
      }
      
      final file = File('${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.$ext');
      await file.writeAsBytes(response.bodyBytes);

      // 2. Save to Gallery
      if (type == 'video') {
         await Gal.putVideo(file.path);
      } else {
         await Gal.putImage(file.path);
      }
      
      // Cleanup temp file
      await file.delete();

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved to Gallery!')),
        );
      }
    } catch (e) {
      debugPrint('Error downloading: $e');
      if (mounted) {
         ScaffoldMessenger.of(context).hideCurrentSnackBar();
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Media Pager
          PageView.builder(
            controller: _pageController,
            itemCount: widget.mediaItems.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
                _isLiked = false; // Reset while fetching
              });
              _checkFavoriteStatus();
            },
            itemBuilder: (context, index) {
              final item = widget.mediaItems[index];
              // Try public_url first (set by parent), fallback to resolving b2_path
              final url = item['public_url'] as String? ?? MediaService.getPublicUrl(item['b2_path']);
              final type = item['media_type'] as String?;

              if (url == null) return const Center(child: Icon(Icons.broken_image, color: Colors.white));

              if (type == 'video') {
                return _VideoViewer(url: url);
              } else {
                return InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: Center(
                    child: CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.contain,
                      // Removed cacheWidth to allow full resolution zoom
                      placeholder: (context, url) {
                         // Show thumbnail while loading full res (Instant if cached from grid)
                         final thumb = item['public_thumb_url'] as String?;
                         if (thumb != null) {
                            return CachedNetworkImage(
                               imageUrl: thumb,
                               fit: BoxFit.contain,
                            );
                         }
                         return const Center(child: CircularProgressIndicator(color: Colors.white));
                      },
                      errorWidget: (context, error, stackTrace) => const Icon(Icons.error, color: Colors.red),
                    ),
                  ),
                );
              }
            },
          ),
          
          // 2. Top Bar (Close)
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 10,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // 3. Bottom Overlays
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildOverlayInfo(),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlayInfo() {
    final item = widget.mediaItems[_currentIndex];
    
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 60, 20, 40),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // User Info & Date (Bottom Left)
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                 CircleAvatar(
                   backgroundColor: Colors.grey,
                   backgroundImage: _getAvatarImage(item), 
                   radius: 20,
                   child: _getAvatarImage(item) == null ? const Icon(Icons.person, color: Colors.white, size: 20) : null,
                 ),
                 const SizedBox(width: 12),
                 Column(
                   mainAxisSize: MainAxisSize.min,
                   crossAxisAlignment: CrossAxisAlignment.start,
                   children: [
                     Text(
                       _getUserName(item),
                       style: const TextStyle(
                         color: Colors.white, 
                         fontWeight: FontWeight.bold, 
                         fontSize: 16, 
                         shadows: [Shadow(blurRadius: 4, color: Colors.black)]
                       ),
                     ),
                     const SizedBox(height: 4),
                     Text(
                       _getFormattedDate(item['uploaded_at']),
                       style: const TextStyle(
                         color: Colors.white70,
                         fontSize: 12,
                         shadows: [Shadow(blurRadius: 4, color: Colors.black)]
                       ),
                     ),
                   ],
                 ),
              ],
            ),
          ),

          // Actions (Bottom Right)
          Row(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if ((item['favorite_count'] ?? 0) > 0)
                    Text(
                      '${item['favorite_count']}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                      ),
                    ),
                  IconButton(
                    icon: Icon(
                      _isLiked ? Icons.favorite : Icons.favorite_border,
                      color: _isLiked ? Colors.red : Colors.white,
                      size: 30,
                    ),
                    onPressed: _toggleFavorite,
                  ),
                ],
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.download, color: Colors.white, size: 30),
                onPressed: _downloadMedia,
              ),
            ],
          )
        ],
      ),
    );
  }

  ImageProvider? _getAvatarImage(Map<String, dynamic> item) {
     try {
       final u = item['user_trips']['users'];
       if (u != null) {
          // Check for 'resolved_avatar' first (if populated by parent), otherwise resolve on fly
          final url = u['resolved_avatar'] ?? MediaService.getPublicUrl(u['avatar_url']);
          if (url != null && url.isNotEmpty) {
             return NetworkImage(url);
          }
       }
     } catch (_) {}
     return null;
  }

  String _getUserName(Map<String, dynamic> item) {
    // ... existing code ...
    try {
       final u = item['user_trips']['users'];
       if (u != null) return u['name'] ?? 'Unknown';
    } catch (_) {}
    return 'Unknown';
  }

  String _getFormattedDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      // Ensure UTC
      if (!dateStr.endsWith('Z') && !dateStr.contains('+')) {
         dateStr += 'Z';
      }
      final date = DateTime.parse(dateStr).toLocal();
      return DateFormat('MMM d, yyyy • h:mm a').format(date);
    } catch (e) {
      return '';
    }
  }
}

class _VideoViewer extends StatefulWidget {
  final String url;
  const _VideoViewer({required this.url});

  @override
  State<_VideoViewer> createState() => _VideoViewerState();
}

class _VideoViewerState extends State<_VideoViewer> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        setState(() {});
        _controller.play();
        _controller.setLooping(true);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    return GestureDetector(
      onTap: () {
        _controller.value.isPlaying ? _controller.pause() : _controller.play();
      },
      child: Center(
        child: AspectRatio(
          aspectRatio: _controller.value.aspectRatio,
          child: VideoPlayer(_controller),
        ),
      ),
    );
  }
}
