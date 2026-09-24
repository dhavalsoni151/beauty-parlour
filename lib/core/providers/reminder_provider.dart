import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../firebase/firebase_service.dart';
import '../firestore/firestore_repositories.dart';
import '../models/customer_models.dart';
import '../models/reminder_models.dart';
import '../models/visit_models.dart';
import 'firebase_startup_provider.dart';

class ReminderProvider extends ChangeNotifier {
  ReminderProvider() {
    _customerSub = _customersRepo.watchAll(activeOnly: true).listen((items) {
      _cachedCustomers = items;
    });
    _visitSub = _visitsRepo.watchVisits().listen((items) {
      _cachedVisits = items;
    });
  }

  final FirestoreCustomerRepository _customersRepo = FirestoreCustomerRepository(
    FirestoreScope(
      firestore: FirebaseService.instance.firestore,
      organizationId: firebaseOrganizationId,
    ),
  );
  final FirestoreVisitRepository _visitsRepo = FirestoreVisitRepository(
    FirestoreScope(
      firestore: FirebaseService.instance.firestore,
      organizationId: firebaseOrganizationId,
    ),
  );
  final FirestoreReminderRepository _remindersRepo = FirestoreReminderRepository(
    FirestoreScope(
      firestore: FirebaseService.instance.firestore,
      organizationId: firebaseOrganizationId,
    ),
  );
  final FirestoreSettingsRepository _settingsRepo = FirestoreSettingsRepository(
    FirestoreScope(
      firestore: FirebaseService.instance.firestore,
      organizationId: firebaseOrganizationId,
    ),
  );

  int _daysSinceVisit = 25;
  double _minAmount = 300;
  bool _showNeverVisited = false;
  int? _categoryId;
  bool? _packageUsed;
  ReminderSort _sort = ReminderSort.daysDesc;

  int _suppressWithinDays = 15;
  String _messageTemplate = defaultTemplate;

  List<ReminderCandidate> _candidates = [];
  List<Customer> _cachedCustomers = [];
  List<Visit> _cachedVisits = [];
  StreamSubscription<List<Customer>>? _customerSub;
  StreamSubscription<List<Visit>>? _visitSub;
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
    final values = await _settingsRepo.getAll();
    _suppressWithinDays = int.tryParse(values['reminder_suppress_days'] ?? '') ?? 15;
    final template = values['reminder_message_template'];
    if (template != null && template.trim().isNotEmpty) {
      _messageTemplate = template;
    }
    notifyListeners();
  }

  Future<void> setSuppressWithinDays(int days) async {
    _suppressWithinDays = days;
    await _settingsRepo.set('reminder_suppress_days', '$days');
    notifyListeners();
  }

  Future<void> setMessageTemplate(String template) async {
    _messageTemplate = template;
    await _settingsRepo.set('reminder_message_template', template);
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

  void setShowNeverVisited(bool value) {
    _showNeverVisited = value;
    notifyListeners();
    if (_hasSearched) search();
  }

  Future<void> search() async {
    _isLoading = true;
    _hasSearched = true;
    notifyListeners();
    try {
      if (_cachedCustomers.isEmpty) {
        _cachedCustomers = await _customersRepo.watchAll(activeOnly: true).first;
      }
      if (_cachedVisits.isEmpty) {
        _cachedVisits = await _visitsRepo.watchVisits().first;
      }
      final customers = _cachedCustomers;
      final visitsByCustomer = HashMap<int, List<Visit>>();
      for (final visit in _cachedVisits) {
        visitsByCustomer.putIfAbsent(visit.customerId, () => []).add(visit);
      }

      final now = DateTime.now();
      _candidates = [];
      for (final customer in customers) {
        final customerVisits = visitsByCustomer[customer.id ?? -1] ?? const [];
        if (customerVisits.isEmpty) {
          if (_showNeverVisited) {
            _candidates.add(
              ReminderCandidate(
                customer: CustomerInfo(
                  id: customer.id!,
                  name: customer.name,
                  phone: customer.phone,
                ),
              ),
            );
          }
          continue;
        }

        customerVisits.sort((a, b) => b.visitDate.compareTo(a.visitDate));
        final latest = customerVisits.first;
        final latestDate = DateTime.tryParse(latest.visitDate);
        if (latestDate == null) continue;
        final days = now.difference(latestDate).inDays;
        if (!_showNeverVisited && days < _daysSinceVisit) continue;
        if (!_showNeverVisited && latest.finalTotal < _minAmount) continue;
        if (_categoryId != null || _packageUsed != null) {
          final full = await _visitsRepo.get(latest.id!);
          if (full == null) continue;
          if (_packageUsed != null && _packageUsed != full.hasPackage) continue;
          if (_categoryId != null &&
              !full.services.any((s) => s.categoryId == _categoryId)) {
            continue;
          }
          _candidates.add(
            ReminderCandidate(
              customer: CustomerInfo(
                  id: customer.id!, name: customer.name, phone: customer.phone),
              lastVisitId: latest.id,
              lastVisitDate: latestDate,
              lastVisitAmount: latest.finalTotal,
              daysSinceVisit: days,
              services: full.services,
              packageId: full.packageId,
              packageName: full.packageNameSnapshot,
              packageNormalTotal: full.packageNormalTotal,
              packagePrice: full.packagePrice,
              packageDiscount: full.packageDiscount,
              visitTotalPaid: full.totalPaid,
              visitPendingAmount: full.pendingAmount,
            ),
          );
          continue;
        }

        _candidates.add(
          ReminderCandidate(
            customer: CustomerInfo(
                id: customer.id!, name: customer.name, phone: customer.phone),
            lastVisitId: latest.id,
            lastVisitDate: latestDate,
            lastVisitAmount: latest.finalTotal,
            daysSinceVisit: days,
          ),
        );
      }
      _sortCandidates();
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

  String renderMessage(ReminderCandidate c, {required String parlourName}) {
    final services = c.services.map((s) => '• ${s.pathLabel}').join('\n');
    final vars = <String, String>{
      '{customer_name}': c.customer.name,
      '{days_since_visit}': '${c.daysSinceVisit ?? 0}',
      '{last_visit_date}': c.lastVisitDate != null ? _fmtDate(c.lastVisitDate!) : '',
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

  Future<int> recordActivity(
    ReminderCandidate c,
    ReminderStatus status,
  ) {
    return _remindersRepo.save(Reminder(
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


  Future<List<Reminder>> getForCustomer(int customerId) =>
      _remindersRepo.getForCustomer(customerId);

  Future<Map<int, int>> getDueCounts(List<int> buckets) async {
    if (_cachedCustomers.isEmpty) {
      _cachedCustomers = await _customersRepo.watchAll(activeOnly: true).first;
    }
    if (_cachedVisits.isEmpty) {
      _cachedVisits = await _visitsRepo.watchVisits().first;
    }
    final latestByCustomer = <int, Visit>{};
    for (final visit in _cachedVisits) {
      final current = latestByCustomer[visit.customerId];
      if (current == null || visit.visitDate.compareTo(current.visitDate) > 0) {
        latestByCustomer[visit.customerId] = visit;
      }
    }
    final now = DateTime.now();
    final out = <int, int>{for (final b in buckets) b: 0};
    for (final customer in _cachedCustomers) {
      final latest = latestByCustomer[customer.id ?? -1];
      if (latest == null) continue;
      final date = DateTime.tryParse(latest.visitDate);
      if (date == null) continue;
      final days = now.difference(date).inDays;
      for (final b in buckets) {
        if (days >= b) out[b] = (out[b] ?? 0) + 1;
      }
    }
    return out;
  }

  Future<List<ReminderCandidate>> findMonthlyAnniversaryCandidates() async {
    if (_cachedCustomers.isEmpty) {
      _cachedCustomers = await _customersRepo.watchAll(activeOnly: true).first;
    }
    if (_cachedVisits.isEmpty) {
      _cachedVisits = await _visitsRepo.watchVisits().first;
    }
    final latestByCustomer = <int, Visit>{};
    for (final visit in _cachedVisits) {
      final current = latestByCustomer[visit.customerId];
      if (current == null || visit.visitDate.compareTo(current.visitDate) > 0) {
        latestByCustomer[visit.customerId] = visit;
      }
    }
    final now = DateTime.now();
    final lastDayCurrent = DateTime(now.year, now.month + 1, 0).day;
    final result = <ReminderCandidate>[];
    for (final customer in _cachedCustomers) {
      final latest = latestByCustomer[customer.id ?? -1];
      if (latest == null) continue;
      final d = DateTime.tryParse(latest.visitDate);
      if (d == null) continue;
      final monthDiff = (now.year - d.year) * 12 + (now.month - d.month);
      final normalizedDay = d.day > lastDayCurrent ? lastDayCurrent : d.day;
      if (monthDiff == 1 && normalizedDay == now.day) {
        result.add(ReminderCandidate(
          customer: CustomerInfo(id: customer.id!, name: customer.name, phone: customer.phone),
          lastVisitId: latest.id,
          lastVisitDate: d,
          lastVisitAmount: latest.finalTotal,
          daysSinceVisit: now.difference(d).inDays,
        ));
      }
    }
    return result;
  }

  @override
  void dispose() {
    _customerSub?.cancel();
    _visitSub?.cancel();
    super.dispose();
  }

  String _fmtDate(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${d.day.toString().padLeft(2, '0')}-${months[d.month - 1]}-${d.year}';
  }
}
