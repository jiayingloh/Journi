import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

class MediaService {
  static final SupabaseClient _supabase = Supabase.instance.client;
  static const String _functionUrl = '${SupabaseConfig.url}/functions/v1/smart-service'; // Default function name

  static const String _bucketName = 'travel-app-media';
  static const String _cdnUrl = 'https://cdn.journi.space';

  // ... uploadFile omitted ...

  /// Returns the PUBLIC CDN URL for a given PATH or full URL
  static String getPublicUrl(String? path) {
    if (path == null || path.isEmpty) {
      return '';
    }
    
    // At this point, path is guaranteed to be non-null and non-empty
    String workingPath = path;
    
    // 0. Decode: Handle cases where path is stored url-encoded
    try {
      workingPath = Uri.decodeFull(workingPath);
    } catch (_) {}

    // 1. Sanitize: Remove query parameters
    if (workingPath.contains('?')) {
      workingPath = workingPath.split('?').first;
    }

    // 2. Handle file:// protocol (local files - return empty for network images)
    if (workingPath.startsWith('file://')) {
      return ''; // Can't display local file paths in NetworkImage
    }

    // 3. Handle Full URLs
    if (workingPath.startsWith('http')) {
      if (workingPath.contains('cdn.journi.space')) {
        return workingPath;
      }
      
      // If B2 legacy, migrate trying to preserve /file/bucket structure
      if (workingPath.contains('backblazeb2.com')) {
         final fileIndex = workingPath.indexOf('/file/');
         if (fileIndex != -1) {
            // Extract /file/travel-app-media/users/...
            final pathFromSlashFile = workingPath.substring(fileIndex); 
            final result = '$_cdnUrl$pathFromSlashFile';
            return result;
         }
      }
      return workingPath;
    }
    
    var cleanPath = workingPath.startsWith('/') ? workingPath.substring(1) : workingPath;

    // 4. Construct Correct CDN URL
    // Ensure we have /file/travel-app-media/ prefix
    if (!cleanPath.startsWith('file/')) {
       cleanPath = 'file/$_bucketName/$cleanPath';
    }

    final result = '$_cdnUrl/$cleanPath';
    return result;
  }

  /// Uploads a generic file to Supabase Edge Function -> Backblaze B2
  /// Returns the relative PATH (key) of the uploaded file, NOT the full URL.
  static Future<String?> uploadFile(File file) async {
    final session = _supabase.auth.currentSession;
    if (session == null) throw 'No active session';

    final uri = Uri.parse(_functionUrl);
    final request = http.MultipartRequest('POST', uri);

    // Auth Headers
    request.headers['Authorization'] = 'Bearer ${session.accessToken}';
    request.headers['apikey'] = SupabaseConfig.anonKey;

    // Content Type Logic
    String? mimeType;
    final path = file.path.toLowerCase();
    if (path.endsWith('.png')) {
      mimeType = 'image/png';
    } else if (path.endsWith('.jpg') || path.endsWith('.jpeg')) {
      mimeType = 'image/jpeg';
    } else if (path.endsWith('.mp4')) {
      mimeType = 'video/mp4';
    } else if (path.endsWith('.mov')) {
      mimeType = 'video/quicktime';
    }
    
    final mediaType = mimeType != null ? MediaType.parse(mimeType) : MediaType('application', 'octet-stream');

    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        contentType: mediaType,
      ),
    );

    try {
      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        try {
          final json = jsonDecode(body);
          // Expecting { "path": "media/123_image.jpg" }
          if (json is Map && json['path'] != null) {
            return json['path'];
          }
           // Fallback if legacy
          if (json is Map && json['url'] != null) return json['url'];
        } catch (_) {}
        if (body.startsWith('http')) return body.trim();
        throw 'Server returned 200 but unexpected response: $body';
      } else {
        throw 'Upload failed: ${response.statusCode} - $body';
      }
    } catch (e) {
      debugPrint('MediaService Upload Error: $e');
      rethrow;
    }
  }

  /// Uploads avatar to Supabase Edge Function -> Backblaze B2
  static Future<String?> uploadAvatar(File imageFile) async {
    return uploadFile(imageFile);
  }

  /// Deletes files from B2 via Edge Function
  static Future<void> deleteFiles(List<String> paths) async {
     final session = _supabase.auth.currentSession;
     if (session == null || paths.isEmpty) return;

     final uri = Uri.parse(_functionUrl);
     
     // Switch to MultipartRequest as the server seems to expect form data
     final request = http.MultipartRequest('POST', uri);
     
     request.headers['Authorization'] = 'Bearer ${session.accessToken}';
     request.headers['apikey'] = SupabaseConfig.anonKey;
     
     request.fields['action'] = 'delete';
     request.fields['paths'] = jsonEncode(paths);
     
     // Add dummy file to satisfy "No file uploaded" check on backend
     request.files.add(
        http.MultipartFile.fromBytes(
          'file', 
          [],
          filename: 'dummy.txt',
          contentType: MediaType('text', 'plain'),
        )
     );

     try {
       final streamedResponse = await request.send();
       final response = await http.Response.fromStream(streamedResponse);
       
       if (response.statusCode != 200) {
         debugPrint('Delete B2 failed: ${response.statusCode} - ${response.body}');
       }
     } catch (e) {
       debugPrint('Delete B2 Exception: $e');
     }
  }



  // Deprecated shim
  static Future<String?> getSignedUrl(String? path) async {
    if (path == null) return null;
    return getPublicUrl(path);
  }

  /// Helper: Get Public Avatar URL using stored avatar_url 
  static Future<String?> getSignedAvatarUrl() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;
    
    // Check DB for current avatar path
    final data = await _supabase
        .from('users')
        .select('avatar_url')
        .eq('id', user.id)
        .maybeSingle();

    if (data != null && data['avatar_url'] != null) {
       return getPublicUrl(data['avatar_url']);
    }
    return null;
  }
}
