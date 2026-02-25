import 'package:flutter/material.dart';
import '../../features/notifications/notifications_page.dart';
import '../services/notification_service.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final VoidCallback onNotificationReturn;

  const CustomAppBar({
    super.key,
    required this.onNotificationReturn,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
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
      leading: Builder(
        builder: (context) {
          return IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () {
              Scaffold.of(context).openDrawer();
            },
          );
        }
      ),
      actions: [
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: NotificationService.getNotificationsStream(),
          builder: (context, snapshot) {
            int unreadCount = 0;
            if (snapshot.hasData && snapshot.data != null) {
              unreadCount = snapshot.data!.where((n) => n['is_read'] != true).length;
            }

            return IconButton(
               onPressed: () async {
                 await Navigator.push(
                   context,
                   MaterialPageRoute(builder: (_) => const NotificationsPage()),
                 );
                 onNotificationReturn();
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
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
