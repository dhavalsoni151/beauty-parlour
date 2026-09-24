import 'package:flutter_test/flutter_test.dart';
import 'package:beauty_parlour/core/firestore/firestore_migration.dart';

void main() {
  test('builds deterministic idempotent operations and reconciles totals', () {
    final source = _normalizedSource();
    final planner = FirestoreMigrationPlanner();

    final first = planner.build(
      source,
      organizationId: 'priyanka-beauty-parlour',
    );
    final second = planner.build(
      source,
      organizationId: 'priyanka-beauty-parlour',
    );

    expect(first.isSafe, isTrue);
    expect(first.validation.sourceVisitsTotal, 100);
    expect(first.validation.sourcePaymentsTotal, 60);
    expect(first.validation.sourceExpensesTotal, 25);
    expect(first.validation.destinationVisitsTotal, 100);
    expect(first.validation.destinationPaymentsTotal, 60);
    expect(first.validation.destinationExpensesTotal, 25);
    expect(first.sourceFingerprint, second.sourceFingerprint);
    expect(
      first.operations.map((operation) => operation.relativePath),
      second.operations.map((operation) => operation.relativePath),
    );
    expect(
      first.operations.any(
        (operation) => operation.relativePath == 'visits/1/items/1',
      ),
      isTrue,
    );
    expect(
      first.operations
          .firstWhere(
            (operation) => operation.relativePath == 'visits/1/items/1',
          )
          .data['service_name_snapshot'],
      'Full Hands',
    );
  });

  test('rejects broken relationships before a migration can run', () {
    final source = _normalizedSource();
    (source['visits'] as List<Map<String, dynamic>>).first['customer_id'] = 999;

    final plan = FirestoreMigrationPlanner().build(
      source,
      organizationId: 'priyanka-beauty-parlour',
    );

    expect(plan.isSafe, isFalse);
    expect(
      plan.validation.errors,
      contains('visit:1 references missing customers id=999'),
    );
  });

  test('normalizes legacy flat categories into service types', () {
    final source = <String, dynamic>{
      'schemaVersion': 1,
      'categories': [
        {'id': 1, 'name': 'Wax', 'is_active': 1},
        {'id': 2, 'name': 'Rica Wax', 'is_active': 1},
      ],
      'services': [
        {
          'id': 1,
          'category_id': 2,
          'name': 'Full Hands',
          'default_price': 250.0,
          'is_active': 1,
        },
      ],
      'customers': <Map<String, dynamic>>[],
      'service_types': <Map<String, dynamic>>[],
    };

    final plan = FirestoreMigrationPlanner().build(
      source,
      organizationId: 'priyanka-beauty-parlour',
    );

    expect(plan.validation.errors, isEmpty);
    expect(
      plan.operations.any(
        (operation) => operation.relativePath == 'serviceTypes/2',
      ),
      isTrue,
    );
    final service = plan.operations.firstWhere(
      (operation) => operation.relativePath == 'services/1',
    );
    expect(service.data['category_id'], 1);
    expect(service.data['service_type_id'], 2);
  });

  test('excludes the legacy PIN settings and reports the decision', () {
    final source = _normalizedSource();
    final settings = source['settings'] as List<dynamic>;
    settings.addAll(<Map<String, dynamic>>[
      {'key': 'pin_hash', 'value': 'secret-hash'},
      {'key': 'pin_enabled', 'value': 'true'},
    ]);

    final plan = FirestoreMigrationPlanner().build(
      source,
      organizationId: 'priyanka-beauty-parlour',
    );

    expect(plan.isSafe, isTrue);
    expect(plan.validation.excludedSourceCounts['settings'], 2);
    expect(
      plan.operations.any((operation) => operation.data.containsKey('pin_hash')),
      isFalse,
    );
    expect(plan.validation.warnings, hasLength(2));
  });

  test('readback requires counts and totals to match the plan', () {
    final source = _normalizedSource();
    final plan = FirestoreMigrationPlanner().build(
      source,
      organizationId: 'priyanka-beauty-parlour',
    );
    final readback = FirestoreMigrationReadback(
      completed: true,
      missingPaths: const [],
      mismatchedPaths: const [],
      counts: plan.validation.destinationCounts,
      visitsTotal: 100,
      paymentsTotal: 60,
      expensesTotal: 25,
    );

    expect(readback.matchesPlan(plan), isTrue);
  });
}

Map<String, dynamic> _normalizedSource() => {
  'schemaVersion': 7,
  'settings': <Map<String, dynamic>>[
    {'key': 'currency', 'value': '₹'},
  ],
  'customers': [
    {'id': 1, 'name': 'Customer', 'is_active': 1, 'created_date': '2026-09-01'},
  ],
  'categories': [
    {'id': 1, 'name': 'Wax', 'is_active': 1, 'display_order': 1},
  ],
  'service_types': [
    {'id': 1, 'category_id': 1, 'name': 'Rica Wax', 'is_active': 1},
  ],
  'services': [
    {
      'id': 1,
      'category_id': 1,
      'service_type_id': 1,
      'name': 'Full Hands',
      'default_price': 100.0,
      'is_active': 1,
    },
  ],
  'packages': <Map<String, dynamic>>[],
  'package_services': <Map<String, dynamic>>[],
  'visits': [
    {
      'id': 1,
      'customer_id': 1,
      'final_total': 100.0,
      'total_paid': 60.0,
      'pending_amount': 40.0,
      'payment_status': 'PARTIALLY_PAID',
    },
  ],
  'visit_services': [
    {
      'id': 1,
      'visit_id': 1,
      'service_id': 1,
      'category_name_snapshot': 'Wax',
      'service_type_name_snapshot': 'Rica Wax',
      'service_name_snapshot': 'Full Hands',
      'price': 100.0,
      'total': 100.0,
    },
  ],
  'payments': [
    {'id': 1, 'visit_id': 1, 'amount': 60.0},
  ],
  'write_offs': <Map<String, dynamic>>[],
  'expense_categories': [
    {'id': 1, 'name': 'Products', 'is_active': 1},
  ],
  'expenses': [
    {'id': 1, 'expense_category_id': 1, 'amount': 25.0},
  ],
  'appointments': <Map<String, dynamic>>[],
  'appointment_services': <Map<String, dynamic>>[],
  'reminders': <Map<String, dynamic>>[],
};
