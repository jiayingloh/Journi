import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  static final _supabase = Supabase.instance.client;
  static final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const String channelId = 'journi_updates';
  static const String channelName = 'Journi Updates';
  static const String channelDesc = 'Notifications for trip invites and updates';

  static Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: DarwinInitializationSettings(),
    );

    // DYNAMIC DISPATCH TO BYPASS COMPILE ERRORS
    await (_flutterLocalNotificationsPlugin as dynamic).initialize(
      initializationSettings, 
      onDidReceiveNotificationResponse: (details) {
        debugPrint('Notification Tapped: ${details.payload}');
      },
    );

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      channelId,
      channelName,
      description: channelDesc,
      importance: Importance.high,
    );

    await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
        
    _listenForNotifications();
  }

  static void _listenForNotifications() {
    _supabase
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('recipient_id', _supabase.auth.currentUser?.id ?? '')
        .order('created_at')
        .listen((data) {});
        
    _supabase
        .channel('public:notifications')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_id',
            value: _supabase.auth.currentUser?.id ?? '',
          ),
          callback: (payload) {
             final newRecord = payload.newRecord;
             _showNotification(
               id: newRecord['id'].hashCode,
               title: 'New Invite',
               body: newRecord['message'] ?? 'You have a new notification',
               payload: newRecord['trip_id'],
             );
          },
        )
        .subscribe();
  }

// ...

  static Future<void> _showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    // DYNAMIC DISPATCH
    await (_flutterLocalNotificationsPlugin as dynamic).show(
      id,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDesc,
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: payload,
    );
  }

  // --- API Methods ---

  static Stream<List<Map<String, dynamic>>> getNotificationsStream() {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return Stream.value([]);
    
    return _supabase
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('recipient_id', userId)
        .order('created_at', ascending: false);
  }

  static Future<void> sendTripInvite({
    required String tripId,
    required String tripName,
    required String recipientId,
  }) async {
    final senderId = _supabase.auth.currentUser?.id;
    await _supabase.from('notifications').insert({
      'recipient_id': recipientId,
      'sender_id': senderId,
      'trip_id': tripId,
      'type': 'trip_invite',
      'message': 'Invited you to join trip "$tripName"',
      'status': 'pending',
    });
  }

  static Future<void> acceptInvite(String notificationId, String tripId) async {
    final userId = _supabase.auth.currentUser?.id;
    
    // 1. Add user to trip
    try {
      await _supabase.from('user_trips').insert({
        'user_id': userId,
        'trip_id': tripId,
      }); 
    } catch (e) {
      // Ignore if already joined (duplicate key)
    }

    // 2. Update notification status & read
    await _supabase
        .from('notifications')
        .update({
          'status': 'accepted',
          'is_read': true,
        })
        .eq('id', notificationId);
  }

  static Future<void> declineInvite(String notificationId) async {
    await _supabase
        .from('notifications')
        .update({
          'status': 'declined',
          'is_read': true,
        })
        .eq('id', notificationId);
  }

  static Future<void> markAsRead(String notificationId) async {
    await _supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('id', notificationId);
  }

  static Future<void> markAllAsRead() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    
    try {
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('recipient_id', userId);
    } catch (e) {
      debugPrint('Error marking all as read: $e');
    }
  }
}
