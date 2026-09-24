import 'package:cloud_firestore/cloud_firestore.dart';
import '../../firebase/firebase_service.dart';
import '../../firestore/firestore_repositories.dart';
import '../../models/customer_models.dart';
import '../../models/package_models.dart';
import '../../models/visit_models.dart';
import '../../providers/firebase_startup_provider.dart';

class PackageDao {
  PackageDao()
      : _scope = FirestoreScope(
          firestore: FirebaseService.instance.firestore,
          organizationId: firebaseOrganizationId,
        );

  final FirestoreScope _scope;

  Future<List<Visit>> _packageVisits({String? startDate, String? endDate}) async {
    Query<Map<String, dynamic>> query =
        _scope.collection(FirestoreCollectionNames.visits).where('package_id', isNull: false);
    if (startDate != null) {
      query = query.where('visit_date', isGreaterThanOrEqualTo: startDate);
    }
    if (endDate != null) {
      query = query.where('visit_date', isLessThan: endDate);
    }
    final snap = await query.get();
    return snap.docs.map(FirestoreModelCodec.withDocumentId).map(Visit.fromMap).toList();
  }

  Future<Map<int, Customer>> _customerMap() async {
    final snap = await _scope.collection(FirestoreCollectionNames.customers).get();
    final out = <int, Customer>{};
    for (final doc in snap.docs) {
      final c = Customer.fromMap(FirestoreModelCodec.withDocumentId(doc));
      if (c.id != null) out[c.id!] = c;
    }
    return out;
  }

  Future<List<Package>> _allPackages() async {
    final snap = await _scope.collection(FirestoreCollectionNames.packages).get();
    final list = <Package>[];
    for (final d in snap.docs) {
      final pkg = Package.fromMap(FirestoreModelCodec.withDocumentId(d));
      final items = await d.reference.collection('items').get();
      pkg.services = items.docs
          .map(FirestoreModelCodec.withDocumentId)
          .map(PackageService.fromMap)
          .toList();
      list.add(pkg);
    }
    return list;
  }

  Future<List<Map<String, dynamic>>> getPackageSalesReport({
    String? startDate,
    String? endDate,
  }) async {
    final visits = await _packageVisits(startDate: startDate, endDate: endDate);
    final out = <int, Map<String, dynamic>>{};
    for (final visit in visits) {
      if (visit.packageId == null) continue;
      final row = out.putIfAbsent(
        visit.packageId!,
        () => {
          'package_id': visit.packageId,
          'package_name': visit.packageNameSnapshot ?? 'Package #${visit.packageId}',
          'times_used': 0,
          'normal_value': 0.0,
          'revenue': 0.0,
          'discount': 0.0,
        },
      );
      row['times_used'] = (row['times_used'] as int) + 1;
      row['normal_value'] = (row['normal_value'] as double) + (visit.packageNormalTotal ?? 0);
      row['revenue'] = (row['revenue'] as double) + (visit.packagePrice ?? 0);
      row['discount'] = (row['discount'] as double) + (visit.packageDiscount ?? 0);
    }
    return out.values.toList()
      ..sort((a, b) => (b['times_used'] as int).compareTo(a['times_used'] as int));
  }

  Future<List<Map<String, dynamic>>> getPackageUsageReport({int? packageId}) async {
    final visits = await _packageVisits();
    final customers = await _customerMap();
    final filtered = visits.where((v) => packageId == null || v.packageId == packageId);
    return filtered
        .map((visit) => {
              'visit_id': visit.id,
              'visit_date': visit.visitDate,
              'customer_name': customers[visit.customerId]?.name ?? 'Customer #${visit.customerId}',
              'package_name': visit.packageNameSnapshot ?? 'Package #${visit.packageId}',
              'amount': visit.packagePrice ?? 0.0,
            })
        .toList()
      ..sort((a, b) => (b['visit_date'] as String).compareTo(a['visit_date'] as String));
  }

  Future<Map<String, dynamic>> getPackageDiscountSummary({
    String? startDate,
    String? endDate,
  }) async {
    final visits = await _packageVisits(startDate: startDate, endDate: endDate);
    final normal = visits.fold<double>(0, (s, v) => s + (v.packageNormalTotal ?? 0));
    final revenue = visits.fold<double>(0, (s, v) => s + (v.packagePrice ?? 0));
    final discount = visits.fold<double>(0, (s, v) => s + (v.packageDiscount ?? 0));
    return {
      'normal_value': normal,
      'revenue': revenue,
      'discount': discount,
    };
  }

  Future<Map<String, List<Package>>> getExpiryReport(String today) async {
    final base = DateTime.tryParse(today);
    final packages = await _allPackages();
    final expiringSoon = <Package>[];
    final expired = <Package>[];
    for (final pkg in packages.where((p) => p.isActive)) {
      final expiry = DateTime.tryParse(pkg.expiryDate);
      if (expiry == null || base == null) continue;
      final diff = expiry.difference(base).inDays;
      if (diff < 0) {
        expired.add(pkg);
      } else if (diff <= 7) {
        expiringSoon.add(pkg);
      }
    }
    return {
      'expiringSoon': expiringSoon,
      'expired': expired,
    };
  }

  Future<Map<String, dynamic>> getDashboardStats(
      String startDate, String endDate) async {
    final visitsInRange = await _packageVisits(startDate: startDate, endDate: endDate);
    final summary =
        await getPackageDiscountSummary(startDate: startDate, endDate: endDate);
    final expiry =
        await getExpiryReport(DateTime.now().toIso8601String().substring(0, 10));
    return {
      'packages_sold': visitsInRange.length,
      'package_revenue': (summary['revenue'] as num? ?? 0).toDouble(),
      'package_discount': (summary['discount'] as num? ?? 0).toDouble(),
      'active_packages': (await _allPackages())
          .where((p) => p.isActive && p.isValidOn(DateTime.now().toIso8601String().substring(0, 10)))
          .length,
      'expiring_soon': (expiry['expiringSoon'] ?? const <Package>[]).length,
      'packages_expiring_soon': (expiry['expiringSoon'] ?? const <Package>[]).length,
    };
  }
}
