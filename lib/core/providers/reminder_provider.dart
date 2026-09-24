import 'package:flutter/foundation.dart';

import '../database/database.dart';
import '../models/reminder_models.dart';

/// State for the Customer Reminders screen: search filters, the resulting
/// candidates, the current selection, and the message template / suppression
/// settings. All heavy filtering runs in SQL via [ReminderDao].
class ReminderProvider extends ChangeNotifier {
  final _reminderDao = ReminderDao();
  final _settingsDao = SettingsDao();

  // ── Search inputs ────────────────────────────────────────────────────────
  int _daysSinceVisit = 25;
  double _minAmount = 300;
  bool _showNeverVisited = false;
  int? _categoryId;
  bool? _packageUsed;
  ReminderSort _sort = ReminderSort.daysDesc;

  // ── Settings (persisted) ─────────────────────────────────────────────────
  int _suppressWithinDays = 15;
  String _messageTemplate = defaultTemplate;

  // ── Results ──────────────────────────────────────────────────────────────
  List<ReminderCandidate> _candidates = [];
  final Set<int> _selectedIds = {};
  bool _isLoading = false;
  bool _hasSearched = false;

  static const String defaultTemplate = '''Hi {customer_name} 😊

It's been {days_since_visit} days since your last visit to {parlour_name}.

Your last visit included:
{services}

We'd love to welcome you again. ❤️

Please feel free to contact us for your next visit.

Thank you,
{parlour_name}''';

  // Getters
  int get daysSinceVisit => _daysSinceVisit;
  double get minAmount => _minAmount;
  bool get showNeverVisited => _showNeverVisited;
  int? get categoryId => _categoryId;
  bool? get packageUsed => _packageUsed;
  ReminderSort get sort => _sort;
  int get suppressWithinDays => _suppressWithinDays;
  String get messageTemplate => _messageTemplate;
  List<ReminderCandidate> get candidates => _candidates;
  Set<int> get selectedIds => _selectedIds;
  bool get isLoading => _isLoading;
  bool get hasSearched => _hasSearched;
  int get selectedCount => _selectedIds.length;

  List<ReminderCandidate> get selectedCandidates =>
      _candidates.where((c) => _selectedIds.contains(c.customer.id)).toList();

  Future<void> loadSettings() async {
    final suppressRaw = await _settingsDao.getSetting('reminder_suppress_days');
    _suppressWithinDays = int.tryParse(suppressRaw ?? '') ?? 15;
    final template = await _settingsDao.getSetting('reminder_message_template');
    if (template != null && template.trim().isNotEmpty) {
      _messageTemplate = template;
    }
    notifyListeners();
  }

  Future<void> setSuppressWithinDays(int days) async {
    _suppressWithinDays = days;
    await _settingsDao.setSetting('reminder_suppress_days', '$days');
    notifyListeners();
  }

  Future<void> setMessageTemplate(String template) async {
    _messageTemplate = template;
    await _settingsDao.setSetting('reminder_message_template', template);
    notifyListeners();
  }

  void setDaysSinceVisit(int days) {
    _daysSinceVisit = days;
    notifyListeners();
  }

  void setMinAmount(double amount) {
    _minAmount = amount;
    notifyListeners();
  }

  void setCategory(int? categoryId) {
    _categoryId = categoryId;
    notifyListeners();
  }

  void setPackageUsed(bool? value) {
    _packageUsed = value;
    notifyListeners();
  }

  void setSort(ReminderSort sort) {
    _sort = sort;
    _sortCandidates();
    notifyListeners();
  }

  void _sortCandidates() {
    int byName(ReminderCandidate a, ReminderCandidate b) =>
        a.customer.name.toLowerCase().compareTo(b.customer.name.toLowerCase());
    switch (_sort) {
      case ReminderSort.daysDesc:
        _candidates.sort((a, b) {
          final c = (b.daysSinceVisit ?? -1).compareTo(a.daysSinceVisit ?? -1);
          return c != 0 ? c : byName(a, b);
        });
        break;
      case ReminderSort.dateAsc:
        _candidates.sort((a, b) {
          final ad = a.lastVisitDate;
          final bd = b.lastVisitDate;
          if (ad == null && bd == null) return byName(a, b);
          if (ad == null) return 1;
          if (bd == null) return -1;
          final c = ad.compareTo(bd);
          return c != 0 ? c : byName(a, b);
        });
        break;
      case ReminderSort.amountDesc:
        _candidates.sort((a, b) {
          final c = (b.lastVisitAmount ?? -1).compareTo(a.lastVisitAmount ?? -1);
          return c != 0 ? c : byName(a, b);
        });
        break;
      case ReminderSort.nameAsc:
        _candidates.sort(byName);
        break;
    }
  }

  /// Toggles between the normal "inactive customers" search and the separate
  /// "customers with no visit" list.
  void setShowNeverVisited(bool value) {
    _showNeverVisited = value;
    notifyListeners();
    if (_hasSearched) search();
  }

  /// Runs the search with the current filters.
  Future<void> search() async {
    _isLoading = true;
    _hasSearched = true;
    notifyListeners();
    try {
      var results = await _reminderDao.findCandidates(
        minDaysSinceVisit: _daysSinceVisit,
        minAmount: _showNeverVisited ? 0 : _minAmount,
        includeNeverVisited: _showNeverVisited,
        categoryId: _showNeverVisited ? null : _categoryId,
        packageUsed: _showNeverVisited ? null : _packageUsed,
        suppressContactedWithinDays: _suppressWithinDays,
        sort: _sort,
      );
      results = await _reminderDao.attachServices(results);
      _candidates = results;
      // Drop any selection that no longer appears in the results.
      _selectedIds.removeWhere((id) => !_candidates.any((c) => c.customer.id == id));
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void toggleSelect(int customerId) {
    if (!_selectedIds.add(customerId)) {
      _selectedIds.remove(customerId);
    }
    notifyListeners();
  }

  void selectAll() {
    for (final c in _candidates) {
      _selectedIds.add(c.customer.id);
    }
    notifyListeners();
  }

  void clearSelection() {
    _selectedIds.clear();
    notifyListeners();
  }

  bool get allSelected =>
      _candidates.isNotEmpty && _selectedIds.length == _candidates.length;

  /// Renders the message template for a candidate, replacing the supported
  /// variables. Never exposes internal database IDs.
  String renderMessage(ReminderCandidate c, {required String parlourName}) {
    final services = c.services
        .map((s) => '• ${s.pathLabel}')
        .join('\n');
    final vars = <String, String>{
      '{customer_name}': c.customer.name,
      '{days_since_visit}': '${c.daysSinceVisit ?? 0}',
      '{last_visit_date}':
          c.lastVisitDate != null ? _fmtDate(c.lastVisitDate!) : '',
      '{visit_amount}': c.lastVisitAmount != null
          ? '₹${c.lastVisitAmount!.toStringAsFixed(0)}'
          : '',
      '{services}': services.isEmpty ? '• (your recent services)' : services,
      '{parlour_name}': parlourName,
    };
    var message = _messageTemplate;
    vars.forEach((key, value) {
      message = message.replaceAll(key, value);
    });
    return message;
  }

  /// Records a reminder action for the customer (suggested/previewed/opened/
  /// dismissed) so repeat contact is visible and suppressible.
  Future<int> recordActivity(
    ReminderCandidate c,
    ReminderStatus status,
  ) async {
    return _reminderDao.insertReminder(Reminder(
      customerId: c.customer.id,
      reminderDate: DateTime.now().toIso8601String(),
      status: status,
      reason: _showNeverVisited
          ? 'No visit yet'
          : '${_daysSinceVisit}+ days since last visit',
      lastVisitId: c.lastVisitId,
      daysSinceVisit: c.daysSinceVisit,
    ));
  }

  String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day.toString().padLeft(2, '0')}-${months[d.month - 1]}-${d.year}';
  }
}
