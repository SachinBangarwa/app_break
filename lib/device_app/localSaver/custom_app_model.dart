import 'dart:typed_data';

class CustomAppModel {
  final String packageName;
  final String displayName;
  final Uint8List? icon;
  final bool isSystemApp;
  final bool isFavorite;
  final int countdown;
  final int lastOpened;
  final int todayLimit;
  final int todayUsage;

  CustomAppModel({
    required this.packageName,
    required this.displayName,
    this.icon,
    required this.isSystemApp,
    required this.isFavorite,
    required this.countdown,
    required this.lastOpened,
    required this.todayLimit,
    required this.todayUsage,
  });

  factory CustomAppModel.fromMap(Map<String, dynamic> map) {
    return CustomAppModel(
      packageName: map['packageName'] as String? ?? '',
      displayName: map['displayName'] as String? ?? '',
      icon: map['icon'] as Uint8List?,
      isSystemApp: map['isSystemApp'] == 1,
      isFavorite: map['isFavorite'] == 1,
      countdown: map['countdown'] as int? ?? 0,
      lastOpened: map['lastOpened'] as int? ?? 0,
      todayLimit: map['todayLimit'] as int? ?? 0,
      todayUsage: map['todayUsage'] as int? ?? 0,
    );
  }
}
