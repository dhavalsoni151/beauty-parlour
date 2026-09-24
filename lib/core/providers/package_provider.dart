import 'package:flutter/foundation.dart';
import '../database/database.dart';
import '../models/package_models.dart';

class PackageProvider extends ChangeNotifier {
  final _packageDao = PackageDao();

  List<Package> _packages = [];
  bool _isLoading = false;

  List<Package> get packages => _packages;
  List<Package> get activePackages =>
      _packages.where((p) => p.isActive).toList();
  bool get isLoading => _isLoading;

  Future<void> loadPackages() async {
    _isLoading = true;
    notifyListeners();
    _packages = await _packageDao.getAll();
    _isLoading = false;
    notifyListeners();
  }

  Future<Package?> getPackage(int id) => _packageDao.get(id);

  /// Packages that can actually be used/selected for [date] (yyyy-MM-dd or
  /// any ISO date/datetime string).
  Future<List<Package>> getValidPackagesForDate(String date) =>
      _packageDao.getValidForDate(date);

  Future<void> addPackage(Package package) async {
    await _packageDao.insert(package);
    await loadPackages();
  }

  Future<void> updatePackage(Package package) async {
    await _packageDao.update(package);
    await loadPackages();
  }

  Future<void> toggleActive(Package package) async {
    await _packageDao.toggleActive(package.id!, !package.isActive);
    await loadPackages();
  }

  Future<void> deletePackage(Package package) async {
    await _packageDao.delete(package.id!);
    await loadPackages();
  }

  /// Re-validates a package's applicability for [date]. Must be called again
  /// right before an appointment/visit that uses the package is actually
  /// processed — not only when it is first selected — since the package (or
  /// the target date) may have changed since selection.
  Future<PackageValidationResult> validate(int packageId, String date) =>
      _packageDao.validate(packageId, date);

  // ── Reports ───────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getSalesReport({
    String? startDate,
    String? endDate,
  }) =>
      _packageDao.getPackageSalesReport(startDate: startDate, endDate: endDate);

  Future<List<Map<String, dynamic>>> getUsageReport({int? packageId}) =>
      _packageDao.getPackageUsageReport(packageId: packageId);

  Future<Map<String, dynamic>> getDiscountSummary({
    String? startDate,
    String? endDate,
  }) =>
      _packageDao.getPackageDiscountSummary(startDate: startDate, endDate: endDate);

  Future<Map<String, List<Package>>> getExpiryReport(String today) =>
      _packageDao.getExpiryReport(today);
}
