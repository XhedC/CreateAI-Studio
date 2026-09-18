import 'package:equatable/equatable.dart';

class UserSettingsModel extends Equatable {
  const UserSettingsModel({
    required this.id,
    required this.userId,
    required this.themeMode,
    required this.language,
    required this.notificationsEnabled,
  });

  final String id;
  final String userId;
  final String themeMode;
  final String language;
  final bool notificationsEnabled;

  factory UserSettingsModel.fromJson(Map<String, dynamic> json) => UserSettingsModel(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        themeMode: json['theme_mode'] as String? ?? 'system',
        language: json['language'] as String? ?? 'en',
        notificationsEnabled: json['notifications_enabled'] as bool? ?? true,
      );

  @override
  List<Object?> get props => [id, userId, themeMode, language, notificationsEnabled];
}
