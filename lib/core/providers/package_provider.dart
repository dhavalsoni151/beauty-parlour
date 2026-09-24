import 'dart:async';

import 'package:flutter/foundation.dart';

import '../database/daos/package_dao.dart';
import '../firebase/firebase_service.dart';
import '../firestore/firestore_repositories.dart';
import '../models/package_models.dart';
import 'firebase_startup_provider.dart';

class PackageProvider extends ChangeNotifier {
  final _reportDao = PackageDao();
  final FirestorePackageRepository _repository = FirestorePackageRepository(
    FirestoreScope(
      firestore: FirebaseService.instance.firestore,
      organizationId: firebaseOrganizationId,
    ),
  );

  List<Package> _packages = [];
  bool _isLoading = false;
  StreamSubscription<List<Package>>? _sub;

  List<Package> get packages => _packages;
  List<Package> get activePackages =>
      _packages.where((p) => p.isActive).toList();
  bool get isLoading => _isLoading;

  Future<void> loadPackages() async {
    _isLoading = true;
    notifyListeners();
    await _sub?.cancel();
    _sub = _repository.watchPackages().listen((items) {
      _packages = items;
      _isLoading = false;
      notifyListeners();
    });
  }

  Future<Package?> getPackage(int id) async {
    try {
      return _packages.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<List<Package>> getValidPackagesForDate(String date) async =>
      _packages.where((p) => p.isValidOn(date)).toList();

  Future<void> addPackage(Package package) => _repository.save(package);

  Future<void> updatePackage(Package package) => _repository.save(package);

  Future<void> toggleActive(Package package) =>
      _repository.save(package.copyWith(isActive: !package.isActive));

  Future<void> deletePackage(Package package) => _repository.delete(package.id!);

  Future<PackageValidationResult> validate(int packageId, String date) async {
    final pkg = await getPackage(packageId);
    if (pkg == null) return PackageValidationResult.fail('Package not found.');
    if (!pkg.isValidOn(date)) {
      return PackageValidationResult.fail('Package is not valid for selected date.');
    }
    return PackageValidationResult.ok(pkg);
  }

  Future<List<Map<String, dynamic>>> getSalesReport({
    String? startDate,
    String? endDate,
  }) =>
      _reportDao.getPackageSalesReport(startDate: startDate, endDate: endDate);

  Future<List<Map<String, dynamic>>> getUsageReport({int? packageId}) =>
      _reportDao.getPackageUsageReport(packageId: packageId);

  Future<Map<String, dynamic>> getDiscountSummary({
    String? startDate,
    String? endDate,
  }) =>
      _reportDao.getPackageDiscountSummary(startDate: startDate, endDate: endDate);

  Future<Map<String, List<Package>>> getExpiryReport(String today) async {
    final report = await _reportDao.getExpiryReport(today);
    final active = _packages.where((p) => p.isActive && p.isValidOn(today)).toList();
    return {
      'active': active,
      'upcoming': report['expiringSoon'] ?? const <Package>[],
      'expiring_soon': report['expiringSoon'] ?? const <Package>[],
      'expired': report['expired'] ?? const <Package>[],
      'expiringSoon': report['expiringSoon'] ?? const <Package>[],
    };
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
