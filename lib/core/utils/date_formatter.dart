import 'package:intl/intl.dart';

class DateFormatter {
  const DateFormatter._();

  static String relative(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
    return DateFormat.yMMMd().format(dateTime);
  }

  static String short(DateTime dateTime) => DateFormat.yMMMd().format(dateTime);

  static String full(DateTime dateTime) =>
      DateFormat.yMMMd().add_jm().format(dateTime);
}
