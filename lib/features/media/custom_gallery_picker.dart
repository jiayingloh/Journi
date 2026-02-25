import 'dart:io';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

class CustomGalleryPicker extends StatefulWidget {
  final int maxCount;
  final RequestType requestType;

  const CustomGalleryPicker({
    super.key,
    this.maxCount = 99,
    this.requestType = RequestType.common,
  });

  @override
  State<CustomGalleryPicker> createState() => _CustomGalleryPickerState();
}

class _CustomGalleryPickerState extends State<CustomGalleryPicker> {
  List<AssetEntity> _entities = [];
  final List<AssetEntity> _selectedEntities = [];
  bool _isLoading = true;
  bool _hasPermission = false;

  int _currentPage = 0;
  final int _pageSize = 80;
  bool _hasMore = true;
  String _albumId = '';

  @override
  void initState() {
    super.initState();
    _fetchAssets();
  }

  Future<void> _fetchAssets({bool refresh = true}) async {
    if (refresh) {
      _entities.clear();
      _currentPage = 0;
      _hasMore = true;
    } else if (_isLoading) {
      return;
    }
    
    if (mounted) setState(() => _isLoading = true);
    
    // 1. Request Permission
    final result = await PhotoManager.requestPermissionExtend();
    if (!result.isAuth) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    _hasPermission = true;

    // 2. Fetch Albums (use only the first one "Recent" for now)
    List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
      type: widget.requestType,
      filterOption: FilterOptionGroup(
        containsPathModified: true, 
      ),
    );

    if (albums.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    // 3. Fetch Assets
    final recentAlbum = albums.first;
    _albumId = recentAlbum.id;
    
    final newAssets = await recentAlbum.getAssetListPaged(page: _currentPage, size: _pageSize);

    if (newAssets.isEmpty) {
      _hasMore = false;
    }

    if (mounted) {
      setState(() {
        _entities.addAll(newAssets);
        _isLoading = false;
        _currentPage++;
      });
    }
  }

  void _toggleSelection(AssetEntity entity) {
    setState(() {
      if (_selectedEntities.contains(entity)) {
        _selectedEntities.remove(entity);
      } else {
        if (_selectedEntities.length >= widget.maxCount) return;
        _selectedEntities.add(entity);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white24,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text('Photos/Videos', style: TextStyle(color: Colors.white, fontSize: 16)),
              SizedBox(width: 4),
              Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 18),
            ],
          ),
        ),
        centerTitle: true,
        actions: [
          if (_selectedEntities.isNotEmpty)
            TextButton(
              onPressed: () async {
                  // Convert to Files and return
                  List<File> files = [];
                  for (var e in _selectedEntities) {
                    final f = await e.originFile; // e.originFile retrieves uncompressed binary directly
                    if (f != null) files.add(f);
                  }
                  if (mounted) Navigator.pop(context, files);
              },
              child: Text(
                'Add (${_selectedEntities.length})',
                style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
        ],
      ),
      body: _isLoading && _entities.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : !_hasPermission 
             ? Center(
                 child: TextButton(
                   onPressed: () => _fetchAssets(refresh: true),
                   child: const Text('Grant Permission'),
                 ),
               )
             : NotificationListener<ScrollNotification>(
                 onNotification: (ScrollNotification scroll) {
                   if (!_isLoading && _hasMore &&
                       scroll.metrics.pixels >= scroll.metrics.maxScrollExtent - 200) {
                     _fetchAssets(refresh: false);
                   }
                   return false;
                 },
                 child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 2,
              mainAxisSpacing: 2,
            ),
            itemCount: _entities.length,
            itemBuilder: (context, index) {
              final entity = _entities[index];
              final isSelected = _selectedEntities.contains(entity);
              
              return GestureDetector(
                onTap: () => _toggleSelection(entity),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Thumbnail
                    AssetEntityImage(
                      entity,
                      isOriginal: false,
                      thumbnailSize: const ThumbnailSize.square(200),
                      fit: BoxFit.cover,
                    ),
                    
                    // Selected Overlay
                    if (isSelected)
                      Container(color: Colors.black45),

                    // Selection Circle (Top Right)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          color: isSelected ? Colors.blue : Colors.transparent,
                        ),
                        child: isSelected 
                            ? const Icon(Icons.check, size: 16, color: Colors.white)
                            : null,
                      ),
                    ),
                    
                    // Video Duration (Bottom Left)
                    if (entity.type == AssetType.video)
                      Positioned(
                        bottom: 4,
                        left: 4,
                        child: Text(
                          _formatDuration(entity.duration),
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, shadows: [
                             Shadow(blurRadius: 2, color: Colors.black, offset: Offset(0, 1))
                          ]),
                        ),
                      ),
                  ],
                ),
              );
            },
               ), // GridView
            ), // NotificationListener
    ); // Scaffold
  }

  String _formatDuration(int seconds) {
    if (seconds > 3600) {
      final h = seconds ~/ 3600;
      final m = (seconds % 3600) ~/ 60;
      final s = seconds % 60;
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    } else {
      final m = seconds ~/ 60;
      final s = seconds % 60;
      return '$m:${s.toString().padLeft(2, '0')}';
    }
  }
}
