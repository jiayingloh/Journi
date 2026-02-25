import 'package:flutter/material.dart';
import '../../core/services/notification_service.dart';
import 'package:intl/intl.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final _service = NotificationService();

  @override
  void initState() {
    super.initState();
    // Mark all as read when opening the page
    NotificationService.markAllAsRead();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: NotificationService.getNotificationsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
             return Center(child: Text('Error: ${snapshot.error}'));
          }
          final items = snapshot.data ?? [];
          if (items.isEmpty) {
             return const Center(child: Text('No notifications'));
          }

          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final notif = items[index];
              return _buildNotificationItem(notif);
            },
          );
        },
      ),
    );
  }

  Widget _buildNotificationItem(Map<String, dynamic> notif) {
    final status = notif['status'] as String? ?? 'pending';
    final message = notif['message'] as String? ?? '';
    final type = notif['type'] as String? ?? '';
    final createdAt = DateTime.tryParse(notif['created_at'] ?? 'now') ?? DateTime.now();

    final isActionable = status == 'pending' && type == 'trip_invite';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_getIconForType(type), color: Colors.blue),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message, 
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                Text(
                  DateFormat.yMMMd().add_jm().format(createdAt),
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Status: ${status.toUpperCase()}', style: TextStyle(
              color: status == 'accepted' ? Colors.green : (status == 'declined' ? Colors.red : Colors.orange),
              fontWeight: FontWeight.bold,
              fontSize: 12,
            )),
            if (isActionable) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                   OutlinedButton(
                     onPressed: () => _decline(notif['id']),
                     child: const Text('Decline'),
                   ),
                   const SizedBox(width: 12),
                   ElevatedButton(
                     onPressed: () => _accept(notif['id'], notif['trip_id']),
                     child: const Text('Join Trip'),
                   ),
                ],
              )
            ]
          ],
        ),
      ),
    );
  }

  IconData _getIconForType(String type) {
    switch (type) {
      case 'trip_invite': return Icons.group_add;
      default: return Icons.notifications;
    }
  }

  Future<void> _accept(String id, String tripId) async {
    try {
      await NotificationService.acceptInvite(id, tripId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Joined Trip!')));
        Navigator.pop(context);
      }
    } catch (e) {
      // Ignore unique constraint errors
      debugPrint('Accept error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Joined Trip!')));
        Navigator.pop(context);
      }
    }
  }

  Future<void> _decline(String id) async {
    try {
      await NotificationService.declineInvite(id);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }
}
