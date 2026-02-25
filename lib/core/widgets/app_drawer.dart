import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/auth/login_page.dart';
import '../services/auth_service.dart';
import '../../app.dart';
import '../../features/profile/edit_profile_page.dart';
import '../../features/profile/storage_page.dart';
import '../services/media_service.dart';

class AppDrawer extends StatefulWidget {
  const AppDrawer({super.key});

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  final _supabase = Supabase.instance.client;
  
  String _name = 'Loading...';
  String _email = '...';
  String? _avatarUrl;
  
  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final user = _supabase.auth.currentUser;
    if (user != null) {
      if (mounted) {
        setState(() {
          _email = user.email ?? '';
        });
      }
      
      try {
        final data = await _supabase
            .from('users')
            .select()
            .eq('id', user.id)
            .maybeSingle();
            
        if (data != null && mounted) {
          setState(() {
            _name = data['name'] ?? 'User';
            _avatarUrl = MediaService.getPublicUrl(data['avatar_url']);
          });
        }
        
        // No need to "refresh" since we use public CDN now
      } catch (e) {

      } catch (e) {
        // debugPrint('Error loading drawer profile: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          // User Info Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    if (_avatarUrl != null) {
                       showDialog(
                        context: context,
                        builder: (context) => Dialog(
                          backgroundColor: Colors.black, // 1. Black background
                          insetPadding: EdgeInsets.zero,
                          child: GestureDetector(
                            onTap: () => Navigator.pop(context), // 3. Tap anywhere to close
                            child: InteractiveViewer(
                              panEnabled: true,
                              boundaryMargin: const EdgeInsets.all(20),
                              minScale: 0.5,
                              maxScale: 4.0,
                              child: Center(
                                child: Image.network(
                                  _avatarUrl!,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                  },
                  child: CircleAvatar(
                    radius: 30,
                    backgroundImage: _avatarUrl != null 
                      ? NetworkImage(_avatarUrl!) 
                      : null,
                    backgroundColor: Colors.grey[300],
                    child: _avatarUrl == null
                        ? const Icon(Icons.person, color: Colors.grey, size: 30)
                        : null,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _email,
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const Divider(height: 1),
          
          // Menu Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 10),
              children: [
                _buildMenuItem(context, 'Edit Profile', Icons.edit_outlined),
                const Divider(indent: 20, endIndent: 20, height: 1),
                _buildMenuItem(context, 'Storage', Icons.storage_rounded),
                const Divider(indent: 20, endIndent: 20, height: 1),
                _buildDarkThemeItem(context),
              ],
            ),
          ),
          
          // Log Out Button
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: ElevatedButton.icon(
              onPressed: () async {
                // Handle logout logic here
                await AuthService().signOut();
                if (context.mounted) {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
                // The root StreamBuilder in app.dart will handle the redirect to LoginPage
              },
              icon: const Icon(Icons.logout),
              label: const Text('Log Out'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF4D4F), // Red
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
              ),
            ),
          ),
          // Add some bottom padding for safe area
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  Widget _buildMenuItem(BuildContext context, String title, IconData? icon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? Colors.white : Colors.black87;
    
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      leading: icon != null ? Icon(icon, color: color, size: 22) : const SizedBox(width: 22), 
      title: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: () async {
        if (title == 'Edit Profile') {
          // Wait for result from EditProfilePage
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const EditProfilePage()),
          );
          // Refresh profile when coming back
          if (mounted) {
             _loadUserProfile();
          }
        } else if (title == 'Storage') {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const StoragePage()),
          );
        }
      },
    );
  }

  Widget _buildDarkThemeItem(BuildContext context) {
    // Determine current theme state
    // We check if current brightness is dark. 
    // This allows it to work with system theme too initially.
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      leading: Icon(
         isDark ? Icons.nightlight_round : Icons.wb_sunny_rounded,
         color: isDark ? Colors.yellow[200] : Colors.orange,
         size: 22,
      ),
      title: Text(
        'Dark Theme',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
      trailing: Switch(
        value: isDark,
        activeColor: const Color(0xFF3B5BDB),
        onChanged: (val) {
          JourniApp.of(context).toggleTheme(val);
        },
      ),
      onTap: () {
         JourniApp.of(context).toggleTheme(!isDark);
      },
    );
  }
}

