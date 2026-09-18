import 'dart:developer' as developer;

/// Minimal structured logger. Technical details go here, never into the UI.
class AppLogger {
  const AppLogger._();

  static void info(String message) {
    developer.log(message, name: 'CreateAI', level: 800);
  }

  static void warning(String message) {
    developer.log(message, name: 'CreateAI', level: 900);
  }

  static void error(String message, {Object? error, StackTrace? stackTrace}) {
    developer.log(
      message,
      name: 'CreateAI',
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
