import 'package:supabase_flutter/supabase_flutter.dart';
import '../../features/trips/trip_model.dart';
import '../utils/logger.dart';

class TripService {
  final SupabaseClient _client = Supabase.instance.client;

  // Table name
  static const String _table = 'trips';

  /// Fetch all trips for the current user
  Future<List<TripModel>> getTrips() async {
    try {
      final response = await _client
          .from(_table)
          .select()
          .order('date', ascending: false);

      // Map dynamic list to TripModel list
      return (response as List).map((e) => TripModel.fromMap(e)).toList();
    } catch (e) {
      AppLogger.log('Error fetching trips: $e');
      rethrow;
    }
  }

  /// Create a new trip
  Future<void> createTrip(TripModel trip) async {
    try {
      await _client.from(_table).insert(trip.toMap());
    } catch (e) {
      AppLogger.log('Error creating trip: $e');
      rethrow;
    }
  }

  /// Delete a trip
  Future<void> deleteTrip(String tripId) async {
    try {
      await _client.from(_table).delete().eq('id', tripId);
    } catch (e) {
      AppLogger.log('Error deleting trip: $e');
      rethrow;
    }
  }
}
