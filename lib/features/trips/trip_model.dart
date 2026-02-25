class TripModel {
  final String id;
  final String userId;
  final String title;
  final DateTime date;
  final String? coverImageUrl;

  TripModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.date,
    this.coverImageUrl,
  });

  // Convert from database map (JSON)
  factory TripModel.fromMap(Map<String, dynamic> map) {
    return TripModel(
      id: map['id'] ?? '',
      userId: map['user_id'] ?? '',
      title: map['title'] ?? '',
      date: DateTime.parse(map['date']),
      coverImageUrl: map['cover_image_url'],
    );
  }

  // Convert to database map (JSON)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'title': title,
      'date': date.toIso8601String(),
      'cover_image_url': coverImageUrl,
    };
  }
}
