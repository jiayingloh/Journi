import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/services/media_service.dart';
import '../trips/trip_detail_page.dart';  // Import for navigation
import '../../core/widgets/app_drawer.dart'; // Import AppDrawer
import '../../core/services/notification_service.dart';
import '../notifications/notifications_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _supabase = Supabase.instance.client;
  
  String _name = 'Loading...';
  String? _avatarUrl;
  int _tripCount = 0;
  int _photoCount = 0;
  int _videoCount = 0;
  List<Map<String, dynamic>> _myTrips = [];
  bool _isLoading = false;
  Map<String, String?> _dynamicCovers = {}; // To store dynamic covers per trip

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      // 1. Fetch User Data
      final userData = await _supabase
          .from('users')
          .select('name, avatar_url')
          .eq('id', user.id)
          .maybeSingle();

      if (userData != null) {
        _name = userData['name'] ?? 'No Name';
        _avatarUrl = MediaService.getPublicUrl(userData['avatar_url']);
      }

      // 2. Stats - Trips Joined
      final tripsCount = await _supabase
          .from('user_trips')
          .count(CountOption.exact)
          .eq('user_id', user.id);
      _tripCount = tripsCount;

      // 3. Stats - My Uploads (Photos & Videos)
      // First get my user_trip IDs
      final utRes = await _supabase
          .from('user_trips')
          .select('id')
          .eq('user_id', user.id);
      
      final myUserTripIds = (utRes as List).map((e) => e['id'] as String).toList();
      
      if (myUserTripIds.isNotEmpty) {
         _photoCount = await _supabase
            .from('media')
            .count(CountOption.exact)
            .eq('media_type', 'image')
            .inFilter('user_trip_id', myUserTripIds);
            
         _videoCount = await _supabase
            .from('media')
            .count(CountOption.exact)
            .eq('media_type', 'video')
            .inFilter('user_trip_id', myUserTripIds);
      } else {
         _photoCount = 0;
         _videoCount = 0;
      }

      // 4. Fetch Favorites (Grouped by Trip)
      // We want trips that have at least one favorite.
      // And for each trip, we want the LATEST favorite media as the cover.
      final data = await _supabase
          .from('favorites')
          .select('media!inner(b2_path, uploaded_at, user_trips!inner(trip_id, trips!inner(id, trip_name, start_date, cover_photo_url)))')
          .eq('user_id', user.id);
      
      // Sort by media uploaded_at descending (client-side sort since favorites has no timestamp)
      final List<dynamic> res = List.from(data);
      res.sort((a, b) {
        final dateA = DateTime.tryParse(a['media']['uploaded_at'] ?? '') ?? DateTime(0);
        final dateB = DateTime.tryParse(b['media']['uploaded_at'] ?? '') ?? DateTime(0);
        return dateB.compareTo(dateA);
      });
      
      final Map<String, Map<String, dynamic>> tripMap = {};

      for (var fav in res) {
        final media = fav['media'];
        if (media == null) continue;
        
        // Extract Nested Data
        final ut = media['user_trips']; // Map
        final trip = ut['trips'];       // Map
        final String tripId = trip['id'];
        
        // Since we ordered by created_at desc, the first time we see a tripId, it corresponds to the latest favorite!
        if (!tripMap.containsKey(tripId)) {
          tripMap[tripId] = {
            'id': tripId,
            'trip_name': trip['trip_name'],
            'start_date': trip['start_date'],
            'cover_photo_url': media['b2_path'], // The Latest Favorite Picture
            'original_cover': trip['cover_photo_url'],
          };
        }
      }

      _myTrips = tripMap.values.toList();

    } catch (e) {
      debugPrint('Error loading profile: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gridColors = [Colors.orange[200], Colors.red[200], Colors.blue[200], Colors.green[200]];

    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu), // 3 bar icon
            onPressed: () {
               // Open Drawer or similar if existed, or just show simple menu
               Scaffold.of(context).openDrawer(); 
            },
          ),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.explore, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 8),
            Text(
              'Journi',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: NotificationService.getNotificationsStream(),
            builder: (context, snapshot) {
              int unreadCount = 0;
              if (snapshot.hasData && snapshot.data != null) {
                unreadCount = snapshot.data!.where((n) => n['is_read'] != true).length;
              }

              return IconButton(
                onPressed: () {
                   Navigator.push(
                     context,
                     MaterialPageRoute(builder: (_) => const NotificationsPage()),
                   );
                },
                icon: Badge(
                  isLabelVisible: unreadCount > 0,
                  label: Text('$unreadCount'),
                  child: const Icon(Icons.notifications),
                ),
              );
            },
          ),
        ],
      ),
      // Use the proper AppDrawer widget
      drawer: const AppDrawer(),
      body: RefreshIndicator(
        onRefresh: _loadProfile,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              const SizedBox(height: 24),
              
              // Profile Avatar
              CircleAvatar(
                radius: 50,
                backgroundColor: Colors.grey[200],
                backgroundImage: (_avatarUrl != null && _avatarUrl!.startsWith('http'))
                    ? NetworkImage(_avatarUrl!) 
                    : null,
                child: _avatarUrl == null 
                    ? const Icon(Icons.person, size: 50, color: Colors.grey) 
                    : null,
              ),
              
              const SizedBox(height: 16),
              
              Text(
                _name,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Stats
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatColumn(Icons.map_outlined, '$_tripCount', 'Trips'),
                    _buildStatColumn(Icons.photo_camera_outlined, '$_photoCount', 'Photos'),
                    _buildStatColumn(Icons.videocam_outlined, '$_videoCount', 'Videos'),
                  ],
                ),
              ),
              
              const SizedBox(height: 32),
              
              // My Favourites Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                     Text(
                      'My Favourites',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 8),
              
              // Trips Grid
              if (_myTrips.isEmpty && !_isLoading)
                const Padding(
                  padding: EdgeInsets.all(32.0),
                  child: Text('No favorites yet. Go explore!'),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: _myTrips.length,
                    itemBuilder: (context, index) {
                      final trip = _myTrips[index];
                      // Cover URL is already the latest favorite media path from logic
                      final bgUrl = MediaService.getPublicUrl(trip['cover_photo_url']);
                      final color = gridColors[index % gridColors.length];
                      
                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TripDetailPage(
                                tripId: trip['id'],
                                title: trip['trip_name'] ?? 'Trip',
                                date: trip['start_date'] != null 
                                    ? trip['start_date'].toString().split('T').first 
                                    : 'No Date',
                                coverUrl: trip['original_cover'], // Keep original trip cover for detail header? Or use fav?
                                // User didn't specify detail page cover. But usually detail page shows trip cover. 
                                // I'll pass the 'original_cover' which implies I should fetch it too or just pass null/fav.
                                // Let's pass the fav cover for now as it looks nice, or better:
                                // The TripDetailPage fetches its own cover from DB (lines 60+ of TripDetail). 
                                // So what I pass here is just for "Hero" or provisional.
                                // I'll pass the fav media as coverUrl.
                                showFavoritesOnly: true,
                              ),
                            ),
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: color,
                            image: (bgUrl != null && bgUrl.startsWith('http')) ? DecorationImage(
                              image: NetworkImage(bgUrl),
                              fit: BoxFit.cover,
                            ) : null,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Stack(
                            children: [
                              if (bgUrl == null)
                                Center(
                                  child: Icon(
                                    Icons.map,
                                    size: 40,
                                    color: Colors.white.withOpacity(0.5),
                                  ),
                                ),
                              
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    borderRadius: const BorderRadius.only(
                                      bottomLeft: Radius.circular(16),
                                      bottomRight: Radius.circular(16),
                                    ),
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.transparent,
                                        Colors.black.withOpacity(0.8),
                                      ],
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        trip['trip_name'] ?? 'Untitled',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (trip['start_date'] != null)
                                        Text(
                                          trip['start_date'].toString().split('T').first,
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 10,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatColumn(IconData icon, String count, String label) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFF2563EB), size: 28),
        const SizedBox(height: 8),
        Text(
          count,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}
