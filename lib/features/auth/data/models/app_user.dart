import 'package:equatable/equatable.dart';

/// The authenticated user, combining Supabase auth identity with the
/// `profiles` row. Kept separate from the raw Supabase [User] so the rest of
/// the app never depends directly on the Supabase SDK types.
class AppUser extends Equatable {
  const AppUser({
    required this.id,
    required this.email,
    this.fullName,
    this.avatarUrl,
  });

  final String id;
  final String email;
  final String? fullName;
  final String? avatarUrl;

  String get displayName {
    if (fullName != null && fullName!.trim().isNotEmpty) return fullName!;
    return email.split('@').first;
  }

  AppUser copyWith({String? fullName, String? avatarUrl}) => AppUser(
        id: id,
        email: email,
        fullName: fullName ?? this.fullName,
        avatarUrl: avatarUrl ?? this.avatarUrl,
      );

  @override
  List<Object?> get props => [id, email, fullName, avatarUrl];
}
