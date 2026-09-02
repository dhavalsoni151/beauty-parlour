import 'package:flutter_test/flutter_test.dart';
import 'package:beauty_parlour/core/database/migration_mapping.dart';

void main() {
  group('resolveLegacyCategory', () {
    test('canonical categories stay top-level', () {
      for (final canonical in kCanonicalTopLevelCategories) {
        final r = resolveLegacyCategory(canonical);
        expect(r.isServiceType, isFalse, reason: '$canonical should be a category');
        expect(r.categoryName, canonical);
        expect(r.flaggedUnmapped, isFalse);
      }
    });

    test('Regular/Rica/Cream Wax become service types under Wax', () {
      for (final name in ['Regular Wax', 'Rica Wax', 'Cream Wax']) {
        final r = resolveLegacyCategory(name);
        expect(r.isServiceType, isTrue, reason: '$name should be a service type');
        expect(r.parentCategoryName, 'Wax');
        expect(r.serviceTypeName, name);
      }
    });

    test('explicit mapping is case-insensitive', () {
      final r = resolveLegacyCategory('rica wax');
      expect(r.isServiceType, isTrue);
      expect(r.parentCategoryName, 'Wax');
    });

    test('suffix heuristic nests "<Word> Wax" under Wax', () {
      final r = resolveLegacyCategory('French Wax');
      expect(r.isServiceType, isTrue);
      expect(r.parentCategoryName, 'Wax');
      expect(r.serviceTypeName, 'French Wax');
    });

    test('longest canonical suffix wins (Hair Spa over Hair)', () {
      final r = resolveLegacyCategory('Aroma Hair Spa');
      expect(r.isServiceType, isTrue);
      expect(r.parentCategoryName, 'Hair Spa');
    });

    test('unknown category kept as top-level and flagged', () {
      final r = resolveLegacyCategory('Nail Art Deluxe');
      expect(r.isServiceType, isFalse);
      expect(r.flaggedUnmapped, isTrue);
      expect(r.categoryName, 'Nail Art Deluxe');
    });
  });

  group('visit total math', () {
    // Mirrors the calculation used in the billing screen / VisitDao.
    double discountAmount(double subtotal, String type, double value) {
      if (type == 'PERCENT') return subtotal * value / 100.0;
      return value;
    }

    test('fixed discount', () {
      const subtotal = 1000.0;
      final disc = discountAmount(subtotal, 'FIXED', 150);
      final finalTotal = (subtotal - disc).clamp(0.0, double.infinity);
      expect(disc, 150);
      expect(finalTotal, 850);
    });

    test('percent discount', () {
      const subtotal = 2000.0;
      final disc = discountAmount(subtotal, 'PERCENT', 10);
      final finalTotal = subtotal - disc;
      expect(disc, 200);
      expect(finalTotal, 1800);
    });

    test('partial payment leaves pending', () {
      const finalTotal = 850.0;
      const paid = 500.0;
      final pending = (finalTotal - paid).clamp(0.0, double.infinity);
      expect(pending, 350);
    });

    test('overpayment never produces negative pending', () {
      const finalTotal = 850.0;
      const paid = 900.0;
      final pending = (finalTotal - paid).clamp(0.0, double.infinity);
      expect(pending, 0);
    });
  });

  group('distinct-service aggregation key', () {
    // Mirrors ReportDao._serviceGroupKey: identical service names under
    // different service types / categories must remain distinct.
    String groupKey(int? serviceId, String category, String? type, String name) {
      return '${serviceId?.toString() ?? 'x'}|$category|${type ?? ''}|$name';
    }

    test('same name under different service types stays distinct', () {
      final a = groupKey(null, 'Wax', 'Rica Wax', 'Full Arms');
      final b = groupKey(null, 'Wax', 'Regular Wax', 'Full Arms');
      expect(a == b, isFalse);
    });

    test('same name different service ids stay distinct', () {
      final a = groupKey(1, 'Wax', null, 'Full Arms');
      final b = groupKey(2, 'Wax', null, 'Full Arms');
      expect(a == b, isFalse);
    });

    test('identical rows collapse to the same key', () {
      final a = groupKey(5, 'Facial', 'Gold', 'Cleanup');
      final b = groupKey(5, 'Facial', 'Gold', 'Cleanup');
      expect(a == b, isTrue);
    });
  });
}
