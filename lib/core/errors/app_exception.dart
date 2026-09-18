/// Base type for all handled errors in the app.
///
/// [message] is always a friendly, user-safe string. The original technical
/// error is preserved in [cause]/[stackTrace] for logging only - it must
/// never be shown in the UI.
sealed class AppException implements Exception {
  const AppException(this.message, {this.cause, this.stackTrace, this.code});

  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  /// The backend's machine-readable error code (e.g. `INSUFFICIENT_CREDITS`,
  /// `DUPLICATE_REQUEST`), when the failure came from an Edge Function -
  /// null for purely client-side failures. Lets the UI branch on specific,
  /// known failure reasons without parsing [message].
  final String? code;

  @override
  String toString() => message;
}

class NetworkException extends AppException {
  const NetworkException({
    String message = 'You are currently offline. Please check your connection.',
    super.cause,
    super.stackTrace,
  }) : super(message);
}

class AuthException extends AppException {
  const AuthException(super.message, {super.cause, super.stackTrace});
}

class ValidationException extends AppException {
  const ValidationException(super.message, {super.cause, super.stackTrace});
}

class DatabaseException extends AppException {
  const DatabaseException({
    String message = 'Something went wrong. Please try again.',
    super.cause,
    super.stackTrace,
  }) : super(message);
}

class StorageException extends AppException {
  const StorageException({
    String message = 'We could not upload or access that file. Please try again.',
    super.cause,
    super.stackTrace,
  }) : super(message);
}

class GenerationException extends AppException {
  const GenerationException({
    String message = 'Generation failed. Please try again.',
    super.cause,
    super.stackTrace,
    super.code,
  }) : super(message);
}

/// A funnel publish/unpublish/republish request was rejected - e.g. failed
/// validation, or the requested public slug could not be reserved.
class PublishException extends AppException {
  const PublishException({
    String message = 'Something went wrong while publishing. Please try again.',
    super.cause,
    super.stackTrace,
    super.code,
  }) : super(message);
}

class UnknownException extends AppException {
  const UnknownException({
    String message = 'Something went wrong. Please try again.',
    super.cause,
    super.stackTrace,
  }) : super(message);
}
