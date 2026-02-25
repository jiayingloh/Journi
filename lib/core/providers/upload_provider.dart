import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../services/media_service.dart';

class UploadProvider extends ChangeNotifier {
  final List<String> _logs = [];
  bool _isUploading = false;
  
  // Progress
  int _totalFiles = 0;
  int _completedFiles = 0;
  
  // Status message
  String _statusMessage = '';

  bool get isUploading => _isUploading;
  double get progress => _totalFiles == 0 ? 0 : _completedFiles / _totalFiles;
  String get statusMessage => _statusMessage;
  
  final _supabase = Supabase.instance.client;

  Future<void> uploadFiles(List<File> files, String tripId) async {
    if (files.isEmpty) return;
    
    _isUploading = true;
    _totalFiles = files.length;
    _completedFiles = 0;
    _statusMessage = 'Starting upload...';
    notifyListeners();
    
    // Prevent screen from sleeping to ensure upload continues
    WakelockPlus.enable();
    
    // Start Foreground Notification
    FlutterBackgroundService().startService();

    // Process safely in background 
    // We launch the async process but 'await' here so we can track it.
    // The UI calling this should NOT await if it wants to leave immediately, 
    // OR we just manage state here.
    
    _processQueue(files, tripId);
  }

  Future<void> _processQueue(List<File> files, String tripId) async {
    // Determine userId for user_trips link
    // We need to find the user_trip_id for this trip and user
    // We'll do it once per batch to save time
    
    String? userTripId;
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw 'No User';

      final res = await _supabase
          .from('user_trips')
          .select('id')
          .eq('user_id', user.id)
          .eq('trip_id', tripId)
          .maybeSingle();
      
      if (res != null) {
        userTripId = res['id'];
      }
    } catch (e) {
      debugPrint('Error getting user_trip_id: $e');
    }

    if (userTripId == null) {
      _finish(false, 'Could not verify trip membership.');
      return;
    }

    // Process parallel or sequential? 
    // Sequential is safer for reliability, parallel is faster.
    // Let's do batches of 3 for compromise.
    
    // Chunked Concurrent Processing with Auto-Retry (Fast + Safe)
    int processed = 0;
    final safeUserTripId = userTripId!;
    const int batchSize = 3; // Upload 3 files at same time
    
    for (var i = 0; i < files.length; i += batchSize) {
      final end = (i + batchSize < files.length) ? i + batchSize : files.length;
      final batch = files.sublist(i, end);
      
      _statusMessage = 'Uploading ${i + 1}-$end of $_totalFiles...';
      notifyListeners();
      FlutterBackgroundService().invoke('updateNotification', {'message': _statusMessage});

      await Future.wait(batch.map((file) async {
        bool success = false;
        int retries = 3;
        
        while (retries > 0 && !success) {
          success = await _processSingleFile(file, safeUserTripId);
          if (!success) {
             retries--;
             if (retries > 0) {
                // If Edge Function rate limits, wait up to 1 second before silent retry
                await Future.delayed(const Duration(milliseconds: 1000));
             }
          }
        }
        
        if (success) {
          processed++;
          _completedFiles = processed;
          notifyListeners(); 
        } else {
          debugPrint('Failed to upload ${file.path} permanently after 3 retries.');
        }
      }));
      
      // Small baseline 400ms delay between *batches* to keep the server stable
      await Future.delayed(const Duration(milliseconds: 400));
    }
    
    _finish(true, 'Upload complete!');
  }

  // ... _processSingleFile ...

  void _finish(bool success, String msg) {
    WakelockPlus.disable(); // Allow screen to sleep again running
    FlutterBackgroundService().invoke('stopService');
    _statusMessage = msg;
    Future.delayed(const Duration(seconds: 3), () {
      _isUploading = false;
      notifyListeners();
    });
    notifyListeners();
  }


  Future<bool> _processSingleFile(File file, String userTripId) async {
    try {
      // Determine type
      String mediaType = 'image';
      String? thumbB2Path;
      
      final path = file.path.toLowerCase();
      final isVideo = path.endsWith('.mp4') || path.endsWith('.mov') || path.endsWith('.avi');

      if (isVideo) {
         mediaType = 'video';
         try {
           final uint8list = await VideoThumbnail.thumbnailData(
             video: file.path,
             imageFormat: ImageFormat.JPEG,
             maxWidth: 512, // Decent size for covers
             quality: 75,
           );

           if (uint8list != null) {
             final temp = await getTemporaryDirectory();
              final thumbFile = File('${temp.path}/${DateTime.now().millisecondsSinceEpoch}_${file.hashCode}_thumb.jpg');
             await thumbFile.writeAsBytes(uint8list);
             
             // Upload Thumbnail
             thumbB2Path = await MediaService.uploadFile(thumbFile);
             
             await thumbFile.delete();
           }
         } catch (e) {
           debugPrint('Thumbnail generation failed: $e');
         }
      } else {
         // IMAGE OPTIMIZATION LOGIC
         
         // 1. Generate Small Thumbnail (Grid) - Aggressive compression
         try {
           final temp = await getTemporaryDirectory();
           final thumbName = '${DateTime.now().millisecondsSinceEpoch}_${file.hashCode}_thumb_img.jpg';
           final targetPath = '${temp.path}/$thumbName';
           
           final result = await FlutterImageCompress.compressAndGetFile(
             file.absolute.path,
             targetPath,
             quality: 50, 
             minWidth: 400, 
             minHeight: 400,
           );
           
           if (result != null) {
              final compressedFile = File(result.path);
              thumbB2Path = await MediaService.uploadFile(compressedFile);
              if (await compressedFile.exists()) await compressedFile.delete();
           }
         } catch (e) {
            debugPrint('Image thumbnail generation failed: $e');
         }

         // Original file is uploaded directly to retain original quality.
         // (Only thumbnail compression logic is kept above for fast UI rendering)
      }

      // Upload file to B2 via Edge Function
      final url = await MediaService.uploadFile(file);
      
      if (url != null) {
        // Insert into media table
        await _supabase.from('media').insert({
          'user_trip_id': userTripId,
          'b2_path': url,
          'media_type': mediaType,
          if (thumbB2Path != null) 'thumbnail_path': thumbB2Path,
        });
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Upload Fail for ${file.path}: $e');
      return false;
    }
  }


}
