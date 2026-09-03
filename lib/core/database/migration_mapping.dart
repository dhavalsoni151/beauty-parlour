/// Pure-Dart migration mapping logic for fixing the legacy
/// Category -> Service hierarchy into the normalized
/// Category -> ServiceType -> Service hierarchy.
///
/// This file contains NO Flutter / sqflite imports on purpose so that the
/// mapping heuristics and the [MigrationReport] can be unit-tested with plain
/// `dart test` (no Flutter bindings required). See test/migration_mapping_test.dart.
library;

/// Canonical top-level categories that the app seeds and treats as real
/// parent categories. Anything matching one of these by name is always kept
/// as a top-level category.
const List<String> kCanonicalTopLevelCategories = <String>[
  'Wax',
  'Facial',
  'Hair',
  'Manicure',
  'Pedicure',
  'Makeup',
  'Hair Spa',
  'Threading',
  'Other',
];

/// Explicit, configurable mapping table of legacy top-level category names that
/// should really be service types nested under a real parent category.
///
/// Seeded with the known examples from the field where users created
/// "Regular Wax" / "Rica Wax" / "Cream Wax" as top-level categories instead of
/// service types under "Wax".
///
/// Key   = legacy category name (as stored in the old flat schema)
/// Value = (parentCategoryName, serviceTypeName)
const Map<String, (String, String)> kDefaultLegacyCategoryMappings =
    <String, (String, String)>{
  'Regular Wax': ('Wax', 'Regular Wax'),
  'Rica Wax': ('Wax', 'Rica Wax'),
  'Cream Wax': ('Wax', 'Cream Wax'),
};

/// The result of resolving a single legacy category name.
class LegacyCategoryResolution {
  /// When true, the legacy category should become a service type nested under
  /// [parentCategoryName] with the name [serviceTypeName]. When false, it
  /// should be kept as a top-level category named [categoryName].
  final bool isServiceType;

  final String parentCategoryName;
  final String serviceTypeName;

  final String categoryName;

  /// True when the category was kept as a top-level category but did NOT match
  /// a canonical category or an explicit/heuristic mapping. These are surfaced
  /// in the migration report so nothing is silently dropped.
  final bool flaggedUnmapped;

  /// Human-readable explanation, primarily for the migration report.
  final String reason;

  const LegacyCategoryResolution.serviceType({
    required this.parentCategoryName,
    required this.serviceTypeName,
    required this.reason,
  })  : isServiceType = true,
        categoryName = '',
        flaggedUnmapped = false;

  const LegacyCategoryResolution.category({
    required this.categoryName,
    required this.reason,
    this.flaggedUnmapped = false,
  })  : isServiceType = false,
        parentCategoryName = '',
        serviceTypeName = '';
}

/// Resolves a single legacy category [name] into either a kept top-level
/// category or a service type nested under a canonical parent category.
///
/// Resolution order:
/// 1. Exact canonical top-level category (e.g. "Wax") -> kept as category.
/// 2. Explicit mapping table match (e.g. "Rica Wax") -> service type.
/// 3. Suffix-word heuristic: a multi-word name whose trailing word(s) equal a
///    canonical category (e.g. "French Wax" -> parent "Wax") -> service type.
/// 4. Otherwise -> kept as its own top-level category, flagged as unmapped so
///    it is reported (never dropped).
LegacyCategoryResolution resolveLegacyCategory(
  String name, {
  Map<String, (String, String)> explicitMappings =
      kDefaultLegacyCategoryMappings,
  List<String> canonicalCategories = kCanonicalTopLevelCategories,
}) {
  final trimmed = name.trim();

  // 1. Canonical top-level categories are always kept as categories.
  for (final canonical in canonicalCategories) {
    if (_eq(trimmed, canonical)) {
      return LegacyCategoryResolution.category(
        categoryName: canonical,
        reason: 'Canonical top-level category',
      );
    }
  }

  // 2. Explicit mapping table (case-insensitive on the key).
  for (final entry in explicitMappings.entries) {
    if (_eq(trimmed, entry.key)) {
      return LegacyCategoryResolution.serviceType(
        parentCategoryName: entry.value.$1,
        serviceTypeName: entry.value.$2,
        reason: 'Explicit mapping: "$trimmed" -> '
            '${entry.value.$1} / ${entry.value.$2}',
      );
    }
  }

  // 3. Suffix-word heuristic. Prefer the longest canonical suffix so
  //    "Hair Spa" wins over "Hair" for a name like "Aroma Hair Spa".
  final canonicalByLengthDesc = List<String>.from(canonicalCategories)
    ..sort((a, b) => b.length.compareTo(a.length));
  final lower = trimmed.toLowerCase();
  for (final canonical in canonicalByLengthDesc) {
    final suffix = ' ${canonical.toLowerCase()}';
    if (lower != canonical.toLowerCase() && lower.endsWith(suffix)) {
      return LegacyCategoryResolution.serviceType(
        parentCategoryName: canonical,
        serviceTypeName: trimmed,
        reason: 'Suffix heuristic: "$trimmed" nested under "$canonical"',
      );
    }
  }

  // 4. Unmapped: keep as its own top-level category and flag it.
  return LegacyCategoryResolution.category(
    categoryName: trimmed,
    reason: 'Kept as category (unmapped)',
    flaggedUnmapped: true,
  );
}

bool _eq(String a, String b) => a.trim().toLowerCase() == b.trim().toLowerCase();

/// Aggregated result of a migration run (legacy sqflite DB or legacy JSON).
/// Carries counts, flagged records, and pre/post financial totals so callers
/// can surface mismatches instead of silently discarding data.
class MigrationReport {
  int customers = 0;
  int categories = 0;
  int serviceTypes = 0;
  int services = 0;
  int visits = 0;
  int visitItems = 0;
  int payments = 0;
  int writeOffs = 0;
  int expenseCategories = 0;
  int expenses = 0;
  int appointments = 0;
  int appointmentServices = 0;
  int packages = 0;
  int packageServices = 0;

  /// Records that could not be cleanly mapped (each with a reason).
  final List<String> flagged = <String>[];

  // Financial totals computed from the ORIGINAL legacy source.
  double sourceVisitsTotal = 0;
  double sourcePaymentsTotal = 0;
  double sourceExpensesTotal = 0;

  // Financial totals recomputed from the MIGRATED data.
  double migratedVisitsTotal = 0;
  double migratedPaymentsTotal = 0;
  double migratedExpensesTotal = 0;

  /// A small epsilon avoids false mismatches from floating point noise.
  static const double _eps = 0.01;

  bool get financialMatches =>
      (sourceVisitsTotal - migratedVisitsTotal).abs() <= _eps &&
      (sourcePaymentsTotal - migratedPaymentsTotal).abs() <= _eps &&
      (sourceExpensesTotal - migratedExpensesTotal).abs() <= _eps;

  void addFlag(String message) => flagged.add(message);

  String buildSummary() {
    final b = StringBuffer();
    b.writeln('Migration complete.');
    b.writeln('');
    b.writeln('Records migrated:');
    b.writeln('  Customers: $customers');
    b.writeln('  Categories: $categories');
    b.writeln('  Service Types: $serviceTypes');
    b.writeln('  Services: $services');
    b.writeln('  Visits: $visits');
    b.writeln('  Visit Items: $visitItems');
    b.writeln('  Payments: $payments');
    b.writeln('  Write-offs: $writeOffs');
    b.writeln('  Expense Categories: $expenseCategories');
    b.writeln('  Expenses: $expenses');
    b.writeln('  Appointments: $appointments');
    b.writeln('  Appointment Services: $appointmentServices');
    b.writeln('  Packages: $packages');
    b.writeln('  Package Services: $packageServices');
    b.writeln('');
    b.writeln('Financial reconciliation (source -> migrated):');
    b.writeln('  Bills total: '
        '${sourceVisitsTotal.toStringAsFixed(2)} -> '
        '${migratedVisitsTotal.toStringAsFixed(2)}');
    b.writeln('  Payments total: '
        '${sourcePaymentsTotal.toStringAsFixed(2)} -> '
        '${migratedPaymentsTotal.toStringAsFixed(2)}');
    b.writeln('  Expenses total: '
        '${sourceExpensesTotal.toStringAsFixed(2)} -> '
        '${migratedExpensesTotal.toStringAsFixed(2)}');
    b.writeln(financialMatches
        ? '  ✓ Totals reconcile.'
        : '  ⚠ Totals DO NOT reconcile — please review.');
    if (flagged.isNotEmpty) {
      b.writeln('');
      b.writeln('Flagged records (${flagged.length}):');
      for (final f in flagged) {
        b.writeln('  • $f');
      }
    }
    return b.toString();
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'customers': customers,
        'categories': categories,
        'serviceTypes': serviceTypes,
        'services': services,
        'visits': visits,
        'visitItems': visitItems,
        'payments': payments,
        'writeOffs': writeOffs,
        'expenseCategories': expenseCategories,
        'expenses': expenses,
        'flagged': flagged,
        'sourceVisitsTotal': sourceVisitsTotal,
        'sourcePaymentsTotal': sourcePaymentsTotal,
        'sourceExpensesTotal': sourceExpensesTotal,
        'migratedVisitsTotal': migratedVisitsTotal,
        'migratedPaymentsTotal': migratedPaymentsTotal,
        'migratedExpensesTotal': migratedExpensesTotal,
        'financialMatches': financialMatches,
      };

  static MigrationReport fromJson(Map<String, dynamic> json) {
    final r = MigrationReport();
    int i(String k) => (json[k] as num? ?? 0).toInt();
    double d(String k) => (json[k] as num? ?? 0).toDouble();
    r.customers = i('customers');
    r.categories = i('categories');
    r.serviceTypes = i('serviceTypes');
    r.services = i('services');
    r.visits = i('visits');
    r.visitItems = i('visitItems');
    r.payments = i('payments');
    r.writeOffs = i('writeOffs');
    r.expenseCategories = i('expenseCategories');
    r.expenses = i('expenses');
    r.sourceVisitsTotal = d('sourceVisitsTotal');
    r.sourcePaymentsTotal = d('sourcePaymentsTotal');
    r.sourceExpensesTotal = d('sourceExpensesTotal');
    r.migratedVisitsTotal = d('migratedVisitsTotal');
    r.migratedPaymentsTotal = d('migratedPaymentsTotal');
    r.migratedExpensesTotal = d('migratedExpensesTotal');
    for (final f in (json['flagged'] as List<dynamic>? ?? const [])) {
      r.flagged.add(f.toString());
    }
    return r;
  }
}
