part of 'trip_detail_page.dart';

mixin TripDetailLogic on State<TripDetailPage> {
  final _supabase = Supabase.instance.client;
  _TripViewMode _currentMode = _TripViewMode.gallery;
  
  List<Map<String, dynamic>> _mediaItems = [];
  List<Map<String, dynamic>> _members = [];
  String? _creatorId;
  
  Set<String> _likedIds = {};
  Set<String> _downloadedIds = {};

  bool _isLoading = true;

  String? _coverUrl;
  late String _localTitle;
  late String _localDate;

  final _scrollController = ScrollController();
  int _page = 0;
  static const int _pageSize = 30;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  
  // Multi-select Delete
  bool _isMultiSelect = false;
  Set<String> _selectedIds = {};

  // Storage Calculation
  int? _totalStorageBytes;
  bool _isCalculatingStorage = false;

  Map<String, List<Map<String, dynamic>>> _groupedMedia = {};
  static final _groupDateFormatter = DateFormat('MMMM d, yyyy');



  @override
  void initState() {
    super.initState();
    _localTitle = widget.title;
    _localDate = widget.date;
    _tripNameController.text = _localTitle;
    _tripDateController.text = _localDate;
    _coverUrl = widget.coverUrl;
    _fetchTripData();
    
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
        if (!_isLoadingMore && _hasMore) {
          _fetchTripData(refresh: false);
        }
      }
    });
  }
  
  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchTripData({bool refresh = true}) async {
    if (refresh) {
       _page = 0;
       _hasMore = true;
       // Only show full loading spinner on initial load
       if (_mediaItems.isEmpty) setState(() => _isLoading = true);
    } else {
       if (_isLoadingMore || !_hasMore) return;
       setState(() => _isLoadingMore = true);
    }

    try {
      // 1. Fetch Trip Metadata (Cover + Creator) - Only on first load/refresh
      if (refresh) {
        final tripRes = await _supabase
            .from('trips')
            .select('cover_photo_url, created_by')
            .eq('id', widget.tripId)
            .single();
        
        final dbCover = tripRes['cover_photo_url'] as String?;
        _creatorId = tripRes['created_by'];
        _coverUrl = dbCover ?? _coverUrl;

        // 2. Fetch Members - Only on refresh/first load
        final membersRes = await _supabase
            .from('user_trips')
            .select('users(id, name, avatar_url)')
            .eq('trip_id', widget.tripId);
            
        _members = List<Map<String, dynamic>>.from(
          membersRes.map((e) => e['users']),
        );
        
        // Resolve Member Avatars
        for (var m in _members) {
           m['resolved_avatar'] = MediaService.getPublicUrl(m['avatar_url']);
        }
      }

      // 3. Fetch Media (Paginated)
      final start = _page * _pageSize;
      final end = start + _pageSize - 1;

      // NOTE: We select specific columns to optimize packet size as requested in Option 2
      final mediaRes = await _supabase
          .from('media')
          .select('id, b2_path, thumbnail_path, uploaded_at, media_type, user_trips!inner(trip_id, user_id, users(name, avatar_url))')
          .eq('user_trips.trip_id', widget.tripId)
          .order('uploaded_at', ascending: false)
          .range(start, end);
          
      var newItems = List<Map<String, dynamic>>.from(mediaRes);
      
      if (newItems.length < _pageSize) {
        _hasMore = false;
      }
      
      // Resolve Media Items (Sync)
      for (var item in newItems) {
        item['public_url'] = MediaService.getPublicUrl(item['b2_path']);
        
        final thumb = item['thumbnail_path'] as String?;
        if (thumb != null) {
           item['public_thumb_url'] = MediaService.getPublicUrl(thumb);
        }
        
        try {
           final u = item['user_trips']['users'];
           if (u != null) {
              u['resolved_avatar'] = MediaService.getPublicUrl(u['avatar_url']);
           }
        } catch (_) {}
      }

      // 4. Fetch Favorites for new items (Batch)
      final user = _supabase.auth.currentUser;
      Set<String> newLikes = {};
      
      if (user != null && newItems.isNotEmpty) {
        final mediaIds = newItems.map((e) => e['id']).toList();
        final favRes = await _supabase
            .from('favorites')
            .select('media_id')
            .eq('user_id', user.id)
            .filter('media_id', 'in', mediaIds);
            
        newLikes = (favRes as List).map((e) => e['media_id'] as String).toSet();
      }

      // If viewing favorites only, client-side filter (Supabase doesn't easy filtering on inner joins with pagination)
      // Note: Truly scalable "Favorites Only" needs a different query structure (querying favorites table first).
      // Given current structure, we just filter.
      if (widget.showFavoritesOnly) {
        newItems = newItems.where((m) => newLikes.contains(m['id']) || _likedIds.contains(m['id'])).toList();
      }

      if (mounted) {
        setState(() {
          if (refresh) {
            _mediaItems = newItems;
            _likedIds = newLikes;
             _isLoading = false;
             _totalStorageBytes = null; // Reset size cache on refresh
          } else {
            _mediaItems.addAll(newItems);
            _likedIds.addAll(newLikes);
            _isLoadingMore = false;
            _totalStorageBytes = null; // Reset size cache to trigger recalculation
          }
          _updateGroupedMedia();
          _page++;
        });

        // Background calculate storage if we're currently in settings
        if (_currentMode == _TripViewMode.settings && !_isCalculatingStorage) {
          _calculateStorage();
        }
      }
    } catch (e, stackTrace) {
      debugPrint('Error fetching trip details: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
        // Show error to user
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading media: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _calculateStorage() async {
    if (_mediaItems.isEmpty) {
      if (mounted) setState(() => _totalStorageBytes = 0);
      return;
    }
    
    setState(() => _isCalculatingStorage = true);
    
    int sum = 0;
    try {
      final futures = _mediaItems.map((item) async {
        final url = item['public_url'] as String?;
        if (url == null) return 0;
        try {
          final res = await http.head(Uri.parse(url));
          if (res.statusCode == 200) {
            return int.tryParse(res.headers['content-length'] ?? '0') ?? 0;
          }
        } catch (_) {}
        return 0;
      });
      
      final sizes = await Future.wait(futures);
      sum = sizes.fold(0, (prev, curr) => prev + curr);
    } catch (e) {
      debugPrint('Error calculating storage: $e');
    }
    
    if (mounted) {
      setState(() {
        _totalStorageBytes = sum;
        _isCalculatingStorage = false;
      });
    }
  }

  void _switchMode(_TripViewMode mode) {
    setState(() {
      if (_currentMode == mode) {
        _currentMode = _TripViewMode.gallery;
      } else {
        _currentMode = mode;
      }
    });

    if (_currentMode == _TripViewMode.settings && _totalStorageBytes == null && !_isCalculatingStorage) {
      _calculateStorage();
    }
  }

  String _formatSize(int? bytes) {
    if (bytes == null) return 'Calculating...';
    if (bytes == 0) return '0 MB';
    
    final double mb = bytes / (1024 * 1024);
    if (mb >= 1024) {
      return '${(mb / 1024).toStringAsFixed(2)} GB';
    }
    return '${mb.toStringAsFixed(2)} MB';
  }

  Future<void> _inviteMember() async {
    final List<Map<String, dynamic>>? selectedUsers = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => InvitePeoplePage(tripId: widget.tripId)),
    );

    if (selectedUsers != null && selectedUsers.isNotEmpty) {
      bool sent = false;
      int count = 0;
      for (var u in selectedUsers) {
        // Here we call the notification service to send the invite
        // We assume sender is current user
        try {
           await NotificationService.sendTripInvite(
             tripId: widget.tripId,
             tripName: widget.title,
             recipientId: u['id'],
           );
           sent = true;
           count++;
        } catch (e) {
           debugPrint('Failed to invite ${u['name']}: $e');
        }
      }
      
      if (mounted) {
         if (sent) {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text('Invitations sent to $count people!')),
           );
         } else {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Failed to send invitations')),
           );
         }
      }
    }
  }

  void _updateGroupedMedia() {
    _groupedMedia = groupBy(_mediaItems, (Map m) {
      var dateStr = m['uploaded_at'] as String;
      if (!dateStr.endsWith('Z') && !dateStr.contains('+')) {
        dateStr += 'Z';
      }
      final date = DateTime.parse(dateStr).toLocal();
      return _groupDateFormatter.format(date);
    });
  }



  Future<void> _toggleLike(String mediaId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    
    final isLiked = _likedIds.contains(mediaId);
    
    setState(() {
      if (isLiked) {
        _likedIds.remove(mediaId);
      } else {
        _likedIds.add(mediaId);
      }
    });

    try {
      if (isLiked) {
        await _supabase
            .from('favorites')
            .delete()
            .eq('user_id', user.id)
            .eq('media_id', mediaId);
      } else {
        await _supabase
            .from('favorites')
            .insert({'user_id': user.id, 'media_id': mediaId});
      }
    } catch (e) {
      // Revert if error
      setState(() {
         if (isLiked) _likedIds.add(mediaId); else _likedIds.remove(mediaId);
      });
      debugPrint('Error toggling like: $e');
    }
  }

  Future<void> _downloadMedia(String mediaId, String? url, bool isVideo, {bool showSnackbar = true}) async {
    if (url == null || _downloadedIds.contains(mediaId)) return;
    
    try {
       // Check Access
       if (!await Gal.hasAccess()) {
         await Gal.requestAccess();
       }
       
       if (showSnackbar && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Downloading...'), duration: Duration(seconds: 1)));

       // Download
       final response = await http.get(Uri.parse(url));
       if (response.statusCode != 200) throw 'Download failed';
       
       final tempDir = await getTemporaryDirectory();
       String ext = isVideo ? 'mp4' : 'jpg';
       // Try parse extension
       if (url.contains('.')) {
          final uri = Uri.parse(url);
          final last = uri.pathSegments.last;
          if (last.contains('.')) ext = last.split('.').last;
       }

       final file = File('${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.$ext');
       await file.writeAsBytes(response.bodyBytes);
       
       if (isVideo) {
         await Gal.putVideo(file.path);
       } else {
         await Gal.putImage(file.path);
       }
       
       await file.delete();
       
       if (mounted) {
         setState(() {
           _downloadedIds.add(mediaId);
         });
         if (showSnackbar) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved to Gallery!')));
       }
    } catch (e) {
      debugPrint('Error downloading: $e');
      if (showSnackbar && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Download failed')));
    }
  }

  Future<void> _downloadAllMedia() async {
    if (_mediaItems.isEmpty) return;
    
    if (!await Gal.hasAccess()) {
      await Gal.requestAccess();
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Starting bulk download... please wait.'), duration: Duration(seconds: 2))
      );
    }

    int successCount = 0;
    
    // We do them sequentially to avoid exhausting API connections/memory or use chunks, but sequential is safer for mobile bulk
    for (var item in _mediaItems) {
      final url = item['public_url'];
      final isVideo = item['media_type'] == 'video';
      if (url != null && !_downloadedIds.contains(item['id'])) {
        await _downloadMedia(item['id'], url, isVideo, showSnackbar: false);
        successCount++;
      }
    }

    if (mounted && successCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Successfully downloaded $successCount new items to Gallery!'))
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All items are already downloaded!'))
      );
    }
  }



  void _enterMultiSelect(String initialId, String ownerId) {
    if (ownerId != _supabase.auth.currentUser?.id) {
       HapticFeedback.heavyImpact();
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('You can only delete your own media')));
       return;
    }
    
    HapticFeedback.selectionClick();
    setState(() {
      _isMultiSelect = true;
      _selectedIds = {initialId};
    });
  }

  void _toggleSelection(String id, String ownerId) {
    if (ownerId != _supabase.auth.currentUser?.id) {
       HapticFeedback.heavyImpact();
       return; // Silent fail visually, but vibrate
    }
    
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _isMultiSelect = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }
  
  void _exitMultiSelect() {
    setState(() {
      _isMultiSelect = false;
      _selectedIds.clear();
    });
  }

  Future<void> _confirmDelete() async {
    final count = _selectedIds.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Media?'),
        content: Text('Are you sure you want to delete these $count items?\nThis action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
             onPressed: () => Navigator.pop(context, true), 
             style: TextButton.styleFrom(foregroundColor: Colors.red),
             child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // Capture IDs to delete locally before modifying state
      final idsToDelete = _selectedIds.toList();
      
      try {
        // 1. Gather paths to delete from cloud storage
        final List<String> pathsToDelete = [];
        for (var item in _mediaItems) {
           if (idsToDelete.contains(item['id'])) {
              if (item['b2_path'] != null) pathsToDelete.add(item['b2_path']);
              if (item['thumbnail_path'] != null) pathsToDelete.add(item['thumbnail_path']);
           }
        }

        debugPrint('Target IDs for deletion: $idsToDelete');
        
        // 0. Manual Cascade: Delete from 'favorites' first (to avoid FK constraints if ON DELETE CASCADE is missing)
        try {
           await _supabase.from('favorites').delete().filter('media_id', 'in', idsToDelete);
        } catch (e) {
           debugPrint('Error clearing favorites: $e'); // Non-fatal, might not exist
        }

        // 1. Delete from Database (Loop to isolate failures/syntax issues)
        int deletedCount = 0;
        for (final id in idsToDelete) {
           try {
             final res = await _supabase.from('media').delete().eq('id', id).select();
             if (res.isNotEmpty) deletedCount++;
           } catch (e) {
             debugPrint('Failed to delete media $id: $e');
           }
        }
            
        debugPrint('Deleted $deletedCount items from DB');

        if (deletedCount == 0 && idsToDelete.isNotEmpty) {
           throw 'Permission Denied: Unable to delete items. Check RLS Policies.';
        }

        // 3. Delete from Storage (Fire and Forget or Await)
        if (pathsToDelete.isNotEmpty) {
           await MediaService.deleteFiles(pathsToDelete);
        }

        if (mounted) {
          setState(() {
             _mediaItems.removeWhere((item) => idsToDelete.contains(item['id']));
             _selectedIds.clear();
             _isMultiSelect = false;
             _updateGroupedMedia();
             _totalStorageBytes = null; // Reset size cache
          });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted successfully')));
        }
      } catch (e) {
        debugPrint('Delete error: $e');
        if (e is PostgrestException) {
           debugPrint('Postgrest Error Code: ${e.code}, Message: ${e.message}, Details: ${e.details}, Hint: ${e.hint}');
        }
        final user = _supabase.auth.currentUser;
        debugPrint('Current User ID: ${user?.id}');

        if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }



  final _tripNameController = TextEditingController();
  final _tripDateController = TextEditingController();

  Future<void> _updateCoverPhoto() async {
    // Requires: import 'package:image_picker/image_picker.dart';
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    
    if (pickedFile != null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Updating cover...')));
      
      try {
        final file = File(pickedFile.path);
        // 1. Upload
        final path = await MediaService.uploadFile(file);
        
        if (path != null) {
           // 2. Update DB
           await _supabase.from('trips').update({
             'cover_photo_url': path // Storing PATH now, not URL
           }).eq('id', widget.tripId);
           
           // 3. Resolve for display
           final signedUrl = await MediaService.getSignedUrl(path);
           
           if (mounted) {
             setState(() {
               // Hacky way to update cover without refetching parent. 
               // Ideally parent should listen or we pop with result
               // For now, we unfortunately can't update 'widget.coverUrl' easily as it's final.
               // We need to move coverUrl to state if we want real-time update here.
               // But refetching data will update logic if we used a state variable.
               // Let's rely on _fetchTripData but we need to override the widget param.
               ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cover updated! Refresh to see changes.')));
             });
           }
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _updateTrip() async {
    try {
      final newTitle = _tripNameController.text.trim();
      await _supabase.from('trips').update({
        'trip_name': newTitle,
      }).eq('id', widget.tripId);
      
      if (mounted) {
        setState(() => _localTitle = newTitle);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Trip updated!')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _selectDate() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null) {
      final newStartDateStr = picked.start.toIso8601String();
      final newEndDateStr = picked.end.toIso8601String();
      final dateStr = '${DateFormat('MMM d, yyyy').format(picked.start)} - ${DateFormat('MMM d, yyyy').format(picked.end)}';
      
      try {
        await _supabase.from('trips').update({
          'start_date': newStartDateStr,
          'end_date': newEndDateStr,
        }).eq('id', widget.tripId);
        if (mounted) {
          setState(() {
             _localDate = dateStr;
             _tripDateController.text = _localDate;
          });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Date updated!')));
        }
      } catch (e) {
         if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating date: $e')));
      }
    }
  }

  Future<void> _removeMember(String memberId, String memberName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text('Are you sure you want to remove $memberName from this trip?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm != true) return;

    if (mounted) setState(() => _isLoading = true);
    
    try {
      await _supabase
          .from('user_trips')
          .delete()
          .eq('trip_id', widget.tripId)
          .eq('user_id', memberId);

      if (mounted) {
        setState(() {
          _members.removeWhere((m) => m['id'] == memberId);
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$memberName removed successfully.')));
        _fetchTripData(refresh: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error removing member: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _leaveTrip() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave Trip?'),
        content: const Text('Are you sure you want to leave this trip? You will no longer have access to its media unless invited again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
             onPressed: () => Navigator.pop(context, true), 
             style: TextButton.styleFrom(foregroundColor: Colors.red),
             child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      await _supabase.from('user_trips').delete().match({
        'user_id': user.id,
        'trip_id': widget.tripId,
      });

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error leaving trip: $e')));
    }
  }

  Future<void> _deleteTrip() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Trip?'),
        content: const Text('This will permanently delete the trip and all media uploaded to it. This action cannot be undone. Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
             onPressed: () => Navigator.pop(context, true), 
             style: TextButton.styleFrom(foregroundColor: Colors.red),
             child: const Text('Delete Trip'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleting trip entirely... this may take a moment.')));

      // Fetch paths of all media to delete from B2 storage
      final utRes = await _supabase.from('user_trips').select('id').eq('trip_id', widget.tripId);
      final utIds = (utRes as List).map((e) => e['id'] as String).toList();
      
      if (utIds.isNotEmpty) {
         final mediaRes = await _supabase.from('media').select('b2_path, thumbnail_path').filter('user_trip_id', 'in', utIds);
         final List<dynamic> mediaItems = mediaRes;
         
         if (mediaItems.isNotEmpty) {
            final paths = <String>[];
            for (var m in mediaItems) {
                if (m['b2_path'] != null) paths.add(m['b2_path'] as String);
                if (m['thumbnail_path'] != null) paths.add(m['thumbnail_path'] as String);
            }
            // Delete actual files from Backblaze B2/Storage bucket
            if (paths.isNotEmpty) await MediaService.deleteFiles(paths);
         }
      }

      await _supabase.from('trips').delete().eq('id', widget.tripId);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error deleting trip: ${e.toString()}')));
    }
  }

}
