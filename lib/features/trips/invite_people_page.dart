import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import '../../core/services/media_service.dart';

class InvitePeoplePage extends StatefulWidget {
  final String? tripId;
  const InvitePeoplePage({super.key, this.tripId});

  @override
  State<InvitePeoplePage> createState() => _InvitePeoplePageState();
}

class _InvitePeoplePageState extends State<InvitePeoplePage> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();
  Timer? _debounce;
  
  List<Map<String, dynamic>> _users = [];
  final Set<String> _selectedUserIds = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _fetchUsers(_searchController.text);
    });
  }

  Future<void> _fetchUsers([String? query]) async {
    setState(() => _isLoading = true);
    try {
      final excludeIds = <String>{};
      
      // Add current user to exclude list
      final currentUser = _supabase.auth.currentUser;
      if (currentUser != null) {
        excludeIds.add(currentUser.id);
      }

      // If tripId is provided, fetch current members and add to exclude list
      if (widget.tripId != null) {
        final membersRes = await _supabase
            .from('user_trips')
            .select('user_id')
            .eq('trip_id', widget.tripId!);
            
        for (var row in (membersRes as List)) {
          if (row['user_id'] != null) {
            excludeIds.add(row['user_id'].toString());
          }
        }
      }

      // 1. Start with the base query builder (FilterBuilder)
      var builder = _supabase
          .from('users')
          .select('id, name, avatar_url');

      // 2. Apply Filters (still returns FilterBuilder)
      if (query != null && query.isNotEmpty) {
        builder = builder.ilike('name', '%$query%');
      }

      if (excludeIds.isNotEmpty) {
        builder = builder.not('id', 'in', excludeIds.toList());
      }
      
      // 3. Apply Transform (Limit) if needed and Execute
      // Note: We assign to a new variable or await directly because types change here
      final List<dynamic> response;
      if (query == null || query.isEmpty) {
        response = await builder.limit(50);
      } else {
        response = await builder;
      }
      
      if (mounted) {
        setState(() {
          _users = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Filter the users list locally to show selected ones at top or keep them?
    // For now, standard list.
    
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Invite People', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by name',
                prefixIcon: Icon(Icons.search, color: Theme.of(context).textTheme.bodySmall?.color),
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.dark 
                    ? Colors.grey[800] 
                    : Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),

          // Section Label
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _searchController.text.isNotEmpty ? 'Search Results' : 'Suggested People',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).textTheme.bodyLarge?.color,
                ),
              ),
            ),
          ),

          // Users List
          Expanded(
            child: _isLoading 
                ? const Center(child: CircularProgressIndicator())
                : _users.isEmpty 
                    ? const Center(child: Text('No users found'))
                    : ListView.builder(
                        itemCount: _users.length,
                        itemBuilder: (context, index) {
                          final user = _users[index];
                          final id = user['id'] as String;
                          final name = user['name'] as String? ?? 'Unknown';
                          final avatarUrl = user['avatar_url'] != null 
                              ? MediaService.getPublicUrl(user['avatar_url'] as String) 
                              : null;
                          final isSelected = _selectedUserIds.contains(id);
                          final initial = name.isNotEmpty ? name[0].toUpperCase() : 'U';

                          return ListTile(
                            leading: CircleAvatar(
                              radius: 24,
                              backgroundColor: Colors.blue[100],
                              backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                              child: (avatarUrl == null || avatarUrl.isEmpty) 
                                ? Text(initial, style: TextStyle(color: Colors.blue[900], fontSize: 20, fontWeight: FontWeight.bold)) 
                                : null,
                            ),
                            title: Text(
                              name,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            trailing: isSelected
                                ? Icon(Icons.check_circle, color: Theme.of(context).primaryColor)
                                : const Icon(Icons.circle_outlined, color: Colors.grey),
                            onTap: () {
                              setState(() {
                                if (isSelected) {
                                  _selectedUserIds.remove(id);
                                } else {
                                  _selectedUserIds.add(id);
                                }
                              });
                            },
                          );
                        },
                      ),
          ),

          // Bottom Button
          Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).brightness == Brightness.dark 
                      ? Colors.transparent 
                      : Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: _selectedUserIds.isEmpty
                  ? null
                  : () {
                      // Return full user objects for selected IDs
                      final selectedUsers = _users.where((u) => _selectedUserIds.contains(u['id'])).toList();
                      // Also need to include any previously selected users if they were passed in? 
                      // For now, just return what's selected from current view.
                      // Ideally we'd merge, but simplistic approach first.
                      Navigator.pop(context, selectedUsers);
                    },
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                backgroundColor: const Color(0xFF3B5BDB),
                disabledBackgroundColor: Theme.of(context).brightness == Brightness.dark 
                    ? Colors.grey[800] 
                    : Colors.grey[300],
              ),
              child: Text(
                'Invite (${_selectedUserIds.length})',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
