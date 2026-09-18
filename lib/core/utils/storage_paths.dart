/// Builds the storage object paths used across Supabase Storage buckets.
///
/// Every path is namespaced under the owning user id so bucket-level RLS
/// policies (see supabase/migrations) can allow access only to
/// `auth.uid() = (storage.foldername(name))[1]`.
class StoragePaths {
  const StoragePaths._();

  static String avatar(String userId, String fileName) =>
      '$userId/avatars/$fileName';

  static String project(String userId, String projectId, String fileName) =>
      '$userId/projects/$projectId/$fileName';

  static String generation(
    String userId,
    String generationId,
    String fileName,
  ) =>
      '$userId/generations/$generationId/$fileName';

  static String upload(String userId, String fileName) =>
      '$userId/uploads/$fileName';
}
