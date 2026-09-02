/// Thrown by DAOs when a uniqueness constraint would be violated, so the UI can
/// show a friendly validation message instead of a raw SQLite error.
class DuplicateException implements Exception {
  final String message;
  const DuplicateException(this.message);
  @override
  String toString() => message;
}
