/// Thrown by DAOs when a uniqueness constraint would be violated, so the UI can
/// show a friendly validation message instead of a raw SQLite error.
class DuplicateException implements Exception {
  final String message;
  const DuplicateException(this.message);
  @override
  String toString() => message;
}

/// Thrown by DAOs when a delete would orphan dependent rows (e.g. deleting a
/// category that still has service types/services, or a customer that still
/// has visits), so the UI can show a friendly validation message instead of a
/// raw SQLite foreign-key error.
class InUseException implements Exception {
  final String message;
  const InUseException(this.message);
  @override
  String toString() => message;
}
