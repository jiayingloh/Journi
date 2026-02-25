import 'package:flutter/material.dart';
import '../trips/trip_detail_page.dart';
import '../../core/widgets/app_drawer.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../trips/create_trip_page.dart';
import '../../core/services/media_service.dart';
import '../../core/widgets/custom_app_bar.dart';

class GalleryPage extends StatefulWidget {
  final bool isMainFeed;
  const GalleryPage({super.key, this.isMainFeed = false});

  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _trips = [];
  bool _isLoading = true;
  String _searchQuery = '';

  List<Map<String, dynamic>> get _filteredTrips {
    if (_searchQuery.isEmpty) return _trips;
    return _trips.where((trip) {
      final title = (trip['trip_name'] ?? '').toString().toLowerCase();
      return title.contains(_searchQuery.toLowerCase());
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _fetchJoinedTrips();
  }

  Future<void> _fetchJoinedTrips() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      // Fetch trips and their members via user_trips junction table
      final response = await _supabase
          .from('user_trips')
          .select('trips(*, user_trips(users(id, name, avatar_url)))')
          .eq('user_id', user.id)
          .order('joined_at', ascending: false);

      if (mounted) {
        setState(() {
          _trips = List<Map<String, dynamic>>.from(
            response.map((e) => e['trips']),
          );
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        // debugPrint('Error fetching trips: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: CustomAppBar(
        onNotificationReturn: _fetchJoinedTrips,
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() => _isLoading = true);
          await _fetchJoinedTrips();
        },
        child: Column(
          children: [
            // Search Bar (Can be wired up later)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: TextField(
                onChanged: (value) {
                  setState(() => _searchQuery = value);
                },
                decoration: InputDecoration(
                  hintText: 'Search trips',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Theme.of(context).cardColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.withOpacity(0.2)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.withOpacity(0.2)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
              ),
            ),
            
            // Grid Content
            Expanded(
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator()) 
                : _filteredTrips.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.flight_takeoff, size: 64, color: Colors.grey[300]),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isEmpty ? 'No trips joined yet' : 'No trips found',
                            style: TextStyle(color: Colors.grey[500], fontSize: 16),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _filteredTrips.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        final trip = _filteredTrips[index];
                        final title = trip['trip_name'] ?? 'Untitled Trip';
                        final startDate = trip['start_date'] != null 
                            ? DateFormat('MMM d').format(DateTime.parse(trip['start_date'])) 
                            : 'TBD';
                        final endDate = trip['end_date'] != null 
                            ? DateFormat('MMM d, yyyy').format(DateTime.parse(trip['end_date'])) 
                            : '';
                        final dateStr = (startDate == 'TBD') ? startDate : '$startDate - $endDate';
                        final coverUrl = MediaService.getPublicUrl(trip['cover_photo_url']);

                        // Extract member avatars
                        final members = <Map<String, String?>>[];
                        try {
                          final uts = trip['user_trips'] as List?;
                          if (uts != null) {
                            for (var ut in uts) {
                              final u = ut['users'];
                              if (u != null) {
                                members.add({
                                  'url': u['avatar_url'] != null ? MediaService.getPublicUrl(u['avatar_url']) : null,
                                  'name': u['name']?.toString() ?? '',
                                });
                              }
                            }
                          }
                        } catch (e) {
                           // Safe fallback
                        }

                        return _buildTripCard(
                          context, 
                          trip['id'],
                          title, 
                          dateStr,
                          coverUrl,
                          members,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          // Navigate to create trip and refresh on return
           await Navigator.push(
             context,
             MaterialPageRoute(builder: (_) => const CreateTripPage()),
           );
           _fetchJoinedTrips();
        },
        label: const Text('New Trip'),
        icon: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildTripCard(BuildContext context, String tripId, String title, String date, String? coverUrl, List<Map<String, String?>> memberAvatars) {
    return GestureDetector(
      onTap: () async {
        // Navigate to trip detail (to be updated with real ID)
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => TripDetailPage(
              tripId: tripId, // Pass ID
              title: title,
              date: date,
              coverUrl: coverUrl,
              coverColor: const Color(0xFFFFEE8C), // Fallback color
            ),
          ),
        );
        _fetchJoinedTrips();
      },
      child: Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Image Area
          Container(
            height: 200, // Fixed height for image
            width: double.infinity,
            decoration: BoxDecoration(
              color: (coverUrl == null || coverUrl.isEmpty) ? const Color(0xFFFFEE8C) : Colors.grey[200],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              image: (coverUrl != null && coverUrl.isNotEmpty) 
                ? DecorationImage(
                    image: NetworkImage(coverUrl),
                    fit: BoxFit.cover,
                  )
                : null,
            ),
            child: (coverUrl == null || coverUrl.isEmpty) 
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24.0),
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ) 
                : null,
          ),
          
          // Text Area
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        date,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Avatars Area
                if (memberAvatars.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 12.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ...memberAvatars.take(4).map((member) {
                          final url = member['url'];
                          final name = member['name'] ?? '';
                          final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';
                          
                          return Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: CircleAvatar(
                              radius: 14,
                              backgroundColor: Colors.blue[100],
                              backgroundImage: url != null && url.isNotEmpty ? NetworkImage(url) : null,
                              child: (url == null || url.isEmpty) 
                                ? Text(initial, style: TextStyle(color: Colors.blue[900], fontSize: 12, fontWeight: FontWeight.bold)) 
                                : null,
                            ),
                          );
                        }),
                        if (memberAvatars.length > 4)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: CircleAvatar(
                              radius: 14,
                              backgroundColor: Colors.grey[200],
                              child: Text(
                                '+${memberAvatars.length - 4}', 
                                style: const TextStyle(fontSize: 10, color: Colors.black87, fontWeight: FontWeight.bold)
                              ),
                            ),
                          )
                      ],
                    ),
                  )
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
}
