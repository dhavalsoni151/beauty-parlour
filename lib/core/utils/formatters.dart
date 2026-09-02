import 'package:intl/intl.dart';

class AppFormatters {
  static final _currencyFormatter = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  static final _dateFormatter = DateFormat('dd-MMM-yyyy');
  static final _dateTimeFormatter = DateFormat('dd-MMM-yyyy hh:mm a');
  static final _monthYearFormatter = DateFormat('MMM yyyy');
  static final _dayMonthFormatter = DateFormat('dd MMM');

  static String formatCurrency(double amount) {
    return _currencyFormatter.format(amount);
  }

  static String formatDate(DateTime date) {
    return _dateFormatter.format(date);
  }

  static String formatDateTime(DateTime dateTime) {
    return _dateTimeFormatter.format(dateTime);
  }

  static String formatMonthYear(DateTime date) {
    return _monthYearFormatter.format(date);
  }

  static String formatDayMonth(DateTime date) {
    return _dayMonthFormatter.format(date);
  }

  static String formatBirthDate(String? birthDate) {
    if (birthDate == null || birthDate.isEmpty) return 'Not set';
    try {
      final date = DateTime.parse(birthDate);
      return DateFormat('dd MMMM').format(date);
    } catch (e) {
      return birthDate;
    }
  }

  static String timeAgo(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} weeks ago';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()} months ago';
    return '${(diff.inDays / 365).floor()} years ago';
  }
}

class DateRange {
  final DateTime start;
  final DateTime end;
  final String label;

  const DateRange({required this.start, required this.end, required this.label});

  /// Exclusive upper bound: the midnight that starts the day AFTER [end].
  /// Reporting queries use a half-open interval `>= start AND < endExclusive`
  /// so nothing is missed at the midnight boundary (sub-second timestamps on
  /// the final day are still included).
  DateTime get endExclusive =>
      DateTime(end.year, end.month, end.day).add(const Duration(days: 1));

  static DateRange today() {
    final now = DateTime.now();
    return DateRange(
      start: DateTime(now.year, now.month, now.day),
      end: DateTime(now.year, now.month, now.day, 23, 59, 59),
      label: 'Today',
    );
  }

  static DateRange yesterday() {
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    return DateRange(
      start: DateTime(yesterday.year, yesterday.month, yesterday.day),
      end: DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59),
      label: 'Yesterday',
    );
  }

  static DateRange thisWeek() {
    final now = DateTime.now();
    final start = now.subtract(Duration(days: now.weekday - 1));
    return DateRange(
      start: DateTime(start.year, start.month, start.day),
      end: DateTime(now.year, now.month, now.day, 23, 59, 59),
      label: 'This Week',
    );
  }

  static DateRange thisMonth() {
    final now = DateTime.now();
    return DateRange(
      start: DateTime(now.year, now.month, 1),
      end: DateTime(now.year, now.month, now.day, 23, 59, 59),
      label: 'This Month',
    );
  }

  static DateRange lastMonth() {
    final now = DateTime.now();
    final firstOfThisMonth = DateTime(now.year, now.month, 1);
    final firstOfLastMonth = DateTime(firstOfThisMonth.year, firstOfThisMonth.month - 1, 1);
    final lastOfLastMonth = firstOfThisMonth.subtract(const Duration(days: 1));
    return DateRange(
      start: firstOfLastMonth,
      end: DateTime(lastOfLastMonth.year, lastOfLastMonth.month, lastOfLastMonth.day, 23, 59, 59),
      label: 'Last Month',
    );
  }

  static DateRange thisYear() {
    final now = DateTime.now();
    return DateRange(
      start: DateTime(now.year, 1, 1),
      end: DateTime(now.year, now.month, now.day, 23, 59, 59),
      label: 'This Year',
    );
  }

  static DateRange custom(DateTime start, DateTime end) {
    return DateRange(
      start: DateTime(start.year, start.month, start.day),
      end: DateTime(end.year, end.month, end.day, 23, 59, 59),
      label: 'Custom',
    );
  }
}
