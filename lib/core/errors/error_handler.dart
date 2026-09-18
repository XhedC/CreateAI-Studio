import 'dart:async';
import 'dart:io';

import 'package:storage_client/storage_client.dart' as storage_client;
import 'package:supabase_flutter/supabase_flutter.dart'
    hide AuthException, StorageException;

import '../utils/logger.dart';
import 'app_exception.dart';

/// Converts any raw error thrown by Supabase, dart:io, or app code into a
/// friendly, typed [AppException] and logs the technical detail.
///
/// Every repository/service should route thrown errors through
/// [ErrorHandler.handle] instead of letting raw exceptions reach the UI.
class ErrorHandler {
  const ErrorHandler._();

  static AppException handle(Object error, [StackTrace? stackTrace]) {
    AppLogger.error('Unhandled error', error: error, stackTrace: stackTrace);

    if (error is AppException) return error;

    if (error is SocketException || error is TimeoutException) {
      return NetworkException(cause: error, stackTrace: stackTrace);
    }

    if (error is AuthApiException) {
      return AuthException(
        _friendlyAuthMessage(error.message),
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (error is PostgrestException) {
      return DatabaseException(cause: error, stackTrace: stackTrace);
    }

    if (error is storage_client.StorageException) {
      return StorageException(cause: error, stackTrace: stackTrace);
    }

    return UnknownException(cause: error, stackTrace: stackTrace);
  }

  static String _friendlyAuthMessage(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('invalid login credentials')) {
      return 'The email or password you entered is incorrect.';
    }
    if (lower.contains('email not confirmed')) {
      return 'Please confirm your email address before signing in.';
    }
    if (lower.contains('user already registered')) {
      return 'An account with this email already exists.';
    }
    if (lower.contains('password should be at least')) {
      return 'Your password is too short. Use at least 8 characters.';
    }
    if (lower.contains('rate limit')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    return 'We could not complete that request. Please try again.';
  }
}
