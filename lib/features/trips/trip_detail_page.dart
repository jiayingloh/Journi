import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart'; 
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:sliver_tools/sliver_tools.dart';


import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http; 
import 'package:flutter/services.dart';
import '../media/upload_page.dart';
import '../media/media_viewer_page.dart';
import '../notifications/notifications_page.dart';
import '../../core/services/notification_service.dart';
import 'invite_people_page.dart';
import '../../core/services/media_service.dart';

part 'trip_detail_logic.dart';

class TripDetailPage extends StatefulWidget {
  final String tripId;
  final String title;
  final String date;
  final Color? coverColor;
  final String? coverUrl;
  final bool showFavoritesOnly;

  const TripDetailPage({
    super.key,
    required this.tripId,
    required this.title,
    required this.date,
    this.coverColor,
    this.coverUrl,
    this.showFavoritesOnly = false,
  });

  @override
  State<TripDetailPage> createState() => _TripDetailPageState();
}

enum _TripViewMode { gallery, members, settings }

class _TripDetailPageState extends State<TripDetailPage> with AutomaticKeepAliveClientMixin, TripDetailLogic {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final isGallery = _currentMode == _TripViewMode.gallery;
    
    // 1. Favorites-Only Mode (Simplified)
    if (widget.showFavoritesOnly) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
             // Add icon requested by user (e.g. Info or Favorite icon to indicate mode)
          ],
        ),
        body: _isLoading 
            ? const Center(child: CircularProgressIndicator())
            : _mediaItems.isEmpty 
                ? const Center(child: Text('No favorites yet!'))
                : CustomScrollView(
                    slivers: [
                      ..._groupedMedia.entries.map((entry) {
                        return _buildDateSection(context, entry.key, entry.value);
                      }),
                      const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
                    ],
                  ),
      );
    }

    // 2. Standard Mode (Cover, Tabs, FAB)
    return PopScope(
      canPop: !_isMultiSelect,
      onPopInvoked: (didPop) {
         if (didPop) return;
         _exitMultiSelect();
      },
      child: Scaffold(
        floatingActionButton: _isMultiSelect
            ? FloatingActionButton.extended(
                onPressed: _selectedIds.isEmpty ? null : _confirmDelete,
                backgroundColor: Colors.red,
                icon: const Icon(Icons.delete, color: Colors.white),
                label: Text('Delete (${_selectedIds.length})', style: const TextStyle(color: Colors.white)),
              )
            : (isGallery
                ? FloatingActionButton(
                    onPressed: () async {
                      final success = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => UploadPage(tripId: widget.tripId),
                        ),
                      );
                      
                      // Refresh if upload was successful
                      if (success == true) {
                        _fetchTripData();
                      }
                    },
                    backgroundColor: theme.primaryColor,
                    child: const Icon(Icons.add, color: Colors.white),
                  )
                : null),
      body: RefreshIndicator(
        onRefresh: () async {
          await _fetchTripData(refresh: true);
        },
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(), // Always allow scrolling for refresh
          slivers: [
            // 1. Header with Image & Title
            SliverAppBar(
              expandedHeight: 250,
              pinned: true,
              leading: IconButton(
                icon: Icon(_isMultiSelect ? Icons.close : Icons.arrow_back_ios_new, color: Colors.white),
                onPressed: () {
                  if (_isMultiSelect) {
                    _exitMultiSelect();
                  } else {
                    Navigator.pop(context);
                  }
                },
              ),
              actions: [
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      color: widget.coverColor ?? Colors.blue,
                      child: _coverUrl != null
                          ? RepaintBoundary(
                              child: CachedNetworkImage(
                                imageUrl: MediaService.getPublicUrl(_coverUrl!),
                                fit: BoxFit.cover,
                                memCacheHeight: 400,
                              ),
                            )
                          : const Icon(Icons.image, size: 100, color: Colors.white24),
                    ),
                    Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black54],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 20,
                      left: 20,
                      right: 20,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _localTitle,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _localDate,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Small avatars row (always visible in header)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ..._members.take(4).map((m) => Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: _buildUserAvatar(m['resolved_avatar'] as String?, (m['name'] ?? '').toString()),
                              )),
                              if (_members.length > 4)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.3),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text('+${_members.length - 4}', style: const TextStyle(color: Colors.white)),
                                )
                            ],
                          )
                        ],
                      ),
                    ),
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 8,
                      right: 16,
                      child: CircleAvatar(
                        backgroundColor: Colors.black45,
                        child: IconButton(
                          icon: const Icon(Icons.edit, color: Colors.white, size: 20),
                          onPressed: _updateCoverPhoto,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
  
            // 2. Tab Buttons (Members & Settings)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                     Expanded(child: _buildTabButton('Members', Icons.people_outline, _TripViewMode.members)),
                     const SizedBox(width: 16),
                     Expanded(child: _buildTabButton('Settings', Icons.settings_outlined, _TripViewMode.settings)),
                  ],
                ),
              ),
            ),
  
            // 3. Dynamic Content
            if (_currentMode == _TripViewMode.gallery) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    'Gallery',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              if (_isLoading)
                 const SliverFillRemaining(child: Center(child: CircularProgressIndicator())),
              if (!_isLoading && _mediaItems.isEmpty)
                 const SliverFillRemaining(
                   child: Center(
                     child: Text('No media yet. Tap + to upload!', style: TextStyle(color: Colors.grey)),
                   ),
                 ),
              
              // Loop through groups
              ..._groupedMedia.entries.map((entry) {
                return _buildDateSection(context, entry.key, entry.value);
              }),
              
              const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
            ] else if (_currentMode == _TripViewMode.members) ...[
              _buildMembersList(),
            ] else if (_currentMode == _TripViewMode.settings) ...[
              _buildSettingsList(),
            ],
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildTabButton(String label, IconData icon, _TripViewMode mode) {
    final isSelected = _currentMode == mode;
    final theme = Theme.of(context);
    
    return ElevatedButton.icon(
      onPressed: () => _switchMode(mode),
      icon: Icon(icon, color: isSelected ? Colors.white : Colors.black87),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? const Color(0xFF2563EB) : Colors.grey[100],
        foregroundColor: isSelected ? Colors.white : Colors.black87,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
  
  CircleAvatar _buildUserAvatar(String? url, String name) {
    return CircleAvatar(
      radius: 14,
      backgroundColor: Colors.white,
      child: CircleAvatar(
        radius: 12,
        backgroundColor: Colors.blue[100],
        backgroundImage: url != null && url.isNotEmpty ? CachedNetworkImageProvider(url) : null,
        child: (url == null || url.isEmpty) 
          ? Text(
              name.isNotEmpty ? name[0].toUpperCase() : 'U', 
              style: TextStyle(fontSize: 10, color: Colors.blue[900], fontWeight: FontWeight.bold)
            ) 
          : null,
      ),
    );
  }

  Widget _buildGridAvatar(Map<String, dynamic> item) {
    String? url;
    String name = '';
    
    try {
       final ut = item['user_trips'];
       if (ut != null) {
          final u = ut['users'];
          if (u != null) {
             name = u['name']?.toString() ?? '';
             final rawUrl = u['avatar_url'];
             if (rawUrl != null) {
                url = MediaService.getPublicUrl(rawUrl);
             }
          }
       }
    } catch (_) {}
    
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';
    
    return CircleAvatar(
      radius: 12, // Slightly smaller than header avatars
      backgroundColor: Colors.white,
      child: CircleAvatar(
        radius: 10.5,
        backgroundColor: Colors.blue[100],
        backgroundImage: url != null && url.isNotEmpty ? CachedNetworkImageProvider(url) : null,
        child: (url == null || url.isEmpty) 
          ? Text(initial, style: TextStyle(color: Colors.blue[900], fontSize: 9, fontWeight: FontWeight.bold)) 
          : null,
      ),
    );
  }


  Widget _buildDateSection(BuildContext context, String date, List<Map<String, dynamic>> items) {
    return SliverPadding(
      padding: const EdgeInsets.all(16.0),
      sliver: MultiSliver(
        children: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Text(
                date,
                style: TextStyle(
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 2,
              mainAxisSpacing: 2,
              childAspectRatio: 0.8, // Increased height for rectangular boxes
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final item = items[index];
                final url = item['public_url']; // Use resolved URL
                final thumb = item['public_thumb_url'];
                final isVideo = item['media_type'] == 'video';
                
                // Effective Image URL: The photo itself, or the video thumbnail
                // Prioritize THUMBNAIL for grid view if available (even for images)
                final displayImageUrl = thumb ?? url;
                
                final ownerId = item['user_trips']['user_id'];
                final isSelected = _selectedIds.contains(item['id']);
                
                 return RepaintBoundary(
                   child: GestureDetector(
                     onLongPress: () => _enterMultiSelect(item['id'], ownerId),
                     onTap: () async {
                        if (_isMultiSelect) {
                           _toggleSelection(item['id'], ownerId);
                        } else {
                            final globalIndex = _mediaItems.indexOf(item);
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => MediaViewerPage(
                                  mediaItems: _mediaItems,
                                  initialIndex: globalIndex,
                                ),
                              ),
                            );
                            // Refresh valid for syncing favorites from viewer
                            _fetchTripData();
                        }
                     },
                     child: Container(
                       clipBehavior: Clip.antiAlias,
                       decoration: BoxDecoration(
                         color: Colors.grey[300],
                         border: isSelected ? Border.all(color: Colors.blue, width: 3) : null,
                         gradient: (isVideo && thumb == null) 
                             ? const LinearGradient(
                                 begin: Alignment.topLeft,
                                 end: Alignment.bottomRight,
                                 colors: [Color(0xFF2C3E50), Color(0xFF4CA1AF)],
                               ) 
                             : null,
                       ),
                       child: Stack(
                           fit: StackFit.expand,
                           children: [
                             if (displayImageUrl != null)
                               CachedNetworkImage(
                                 imageUrl: displayImageUrl,
                                 fit: BoxFit.cover,
                                 memCacheWidth: 400, // Reduced from 600 for smoother scrolling on 3-col grid
                                 placeholder: (context, url) => Container(color: Colors.grey[200]),
                                 errorWidget: (context, url, error) => const Center(child: Icon(Icons.error, color: Colors.grey)),
                               ),
                             
                             if (!isVideo && url == null)
                               const Center(child: Icon(Icons.image, color: Colors.grey)),
                             
                             if (isVideo)
                                const Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 40)),
   
                             // Selection Overlay
                             if (_isMultiSelect) 
                               Container(
                                 color: isSelected ? Colors.blue.withOpacity(0.3) : Colors.black12,
                                 child: isSelected 
                                     ? const Center(child: Icon(Icons.check_circle, color: Colors.white, size: 48))
                                     : null,
                               ),
   
                             if (!_isMultiSelect) ...[
                               // Favorite Icon (Bottom Right)
                               Positioned(
                                 bottom: 8,
                                 right: 8,
                                 child: GestureDetector(
                                   onTap: () => _toggleLike(item['id']),
                                   child: Icon(
                                     _likedIds.contains(item['id']) ? Icons.favorite : Icons.favorite_border,
                                     color: _likedIds.contains(item['id']) ? Colors.red : Colors.white,
                                     size: 20
                                   ),
                                 ),
                               ),
   
                               // Uploader Avatar (Bottom Left)
                               Positioned(
                                 bottom: 8,
                                 left: 8,
                                 child: _buildGridAvatar(item),
                               ),
                             ],
                           ],
                       ),
                     ),
                   ),
                 );
              },
              childCount: items.length,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildMembersList() {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      sliver: MultiSliver(
        children: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios, size: 16),
                      onPressed: () => _switchMode(_TripViewMode.gallery),
                    ),
                    Text(
                      'Participants (${_members.length})',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                TextButton.icon(
                   onPressed: _inviteMember,
                   icon: const Icon(Icons.person_add),
                   label: const Text('Invite'),
                ),
              ],
            ),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final m = _members[index];
                final userId = m['id'] ?? '';
                final name = m['name'] ?? m['email'] ?? 'User ${userId.substring(0, 8)}';
                final avatar = m['resolved_avatar'];
                final isCreator = userId == _creatorId;
                
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 24,
                      backgroundImage: (avatar != null && avatar.isNotEmpty) 
                          ? NetworkImage(avatar) 
                          : null,
                      backgroundColor: Colors.blue[100],
                      child: (avatar == null || avatar.isEmpty) 
                          ? Text(
                              name.isNotEmpty ? name[0].toUpperCase() : 'U',
                              style: TextStyle(
                                color: Colors.blue[900],
                                fontWeight: FontWeight.bold,
                              ),
                            ) 
                          : null,
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            name, 
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (isCreator)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.blue[200]!),
                            ),
                            child: Text(
                              'Creator',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.blue[900],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    subtitle: m['email'] != null && m['name'] != null
                        ? Text(
                            m['email'],
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          )
                        : null,
                    trailing: !isCreator
                        ? IconButton(
                            icon: const Icon(Icons.person_remove_outlined, color: Colors.red),
                            onPressed: () {
                              // TODO: Implement remove member
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Remove member feature coming soon')),
                              );
                            },
                          )
                        : null,
                  ),
                );
              },
              childCount: _members.length,
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
          /* Invite button moved to header actions or top of list for cleaner UI */
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildSettingsList() {
    final isCreator = _creatorId != null && _supabase.auth.currentUser?.id == _creatorId;

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      sliver: MultiSliver(
        children: [
           SliverToBoxAdapter(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios, size: 16),
                  onPressed: () => _switchMode(_TripViewMode.gallery),
                ),
                const Text(
                  'Trip Settings',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                const Text('Trip Name', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _tripNameController,
                  enabled: isCreator, // Only creator can edit name
                  decoration: InputDecoration(
                    suffixIcon: isCreator ? IconButton(
                       icon: const Icon(Icons.check, color: Colors.blue),
                       onPressed: _updateTrip,
                    ) : null,
                  ),
                ),
                const SizedBox(height: 24),
                
                const Text('Trip Dates', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _tripDateController,
                  readOnly: true,
                  onTap: isCreator ? _selectDate : null,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.calendar_today, size: 20),
                  ),
                ),
                 const SizedBox(height: 32),
                 
                 // Storage Card
                 Container(
                   padding: const EdgeInsets.all(16),
                   decoration: BoxDecoration(
                     border: Border.all(color: Colors.grey.shade200),
                     borderRadius: BorderRadius.circular(12),
                   ),
                   child: Column(
                     crossAxisAlignment: CrossAxisAlignment.start,
                     children: [
                       const Text('Storage & Download Options', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                       const SizedBox(height: 8),
                       Text(
                         '${_mediaItems.length} items stored in cloud. Total Size: ${_formatSize(_totalStorageBytes)}', 
                         style: TextStyle(color: Colors.grey[600])
                       ),
                       const SizedBox(height: 16),
                       OutlinedButton(
                         onPressed: _downloadAllMedia,
                         style: OutlinedButton.styleFrom(
                           minimumSize: const Size(double.infinity, 48),
                           side: BorderSide(color: Colors.grey.shade300),
                           shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                         ),
                         child: Text('Download All Media', 
                           style: TextStyle(
                             color: Theme.of(context).brightness == Brightness.dark 
                                 ? Colors.white 
                                 : Colors.black87
                           ),
                         ),
                       ),
                     ],
                   ),
                 ),

                 const SizedBox(height: 32),
                 
                 // Danger Zone
                 // Leave Trip - Always visible
                 SizedBox(
                   width: double.infinity,
                   child: ElevatedButton(
                    onPressed: _leaveTrip,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.grey[100],
                      foregroundColor: Colors.black,
                      elevation: 0,
                    ),
                    child: const Text('Leave Trip'),
                   ),
                 ),

                 if (isCreator) ...[
                   const SizedBox(height: 16),
                   SizedBox(
                     width: double.infinity,
                     child: ElevatedButton(
                      onPressed: _deleteTrip,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: const Color(0xFFFF4D4F), // Red
                        foregroundColor: Colors.white,
                        elevation: 0,
                      ),
                      child: const Text('Delete Trip'),
                     ),
                   ),
                 ],
                 const SizedBox(height: 40),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class MultiSliver extends StatelessWidget {
  final List<Widget> children;
  const MultiSliver({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return SliverMainAxisGroup(slivers: children);
  }
}
