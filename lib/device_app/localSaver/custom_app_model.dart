import 'dart:typed_data';

class CustomAppModel {
  final String packageName;
  final String displayName;
  final Uint8List? icon;
  final int isSystemApp;
  final int isFavorite;
  final int countdown;
  final int lastOpened;
  final int todayLimit;
  final int todayUsage;
  final int extraLimit;
  final int sessionLimit;
  final int sessionUsage;

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
    required this.extraLimit,
    this.sessionLimit = 0,
    this.sessionUsage = 0,
  });

  factory CustomAppModel.fromMap(Map<String, dynamic> map) {
    dynamic iconData = map['icon'];
    Uint8List? iconBytes;
    if (iconData != null) {
      if (iconData is Uint8List) {
        iconBytes = iconData;
      } else if (iconData is List) {
        iconBytes = Uint8List.fromList(List<int>.from(iconData));
      }
    }

    return CustomAppModel(
      packageName: map['packageName'] as String? ?? '',
      displayName: map['displayName'] as String? ?? '',
      icon: iconBytes,
      isSystemApp: map['isSystemApp'] as int? ?? 0,
      isFavorite: map['isFavorite'] as int? ?? 0,
      countdown: map['countdown'] as int? ?? 0,
      lastOpened: map['lastOpened'] as int? ?? 0,
      todayLimit: map['todayLimit'] as int? ?? 0,
      todayUsage: map['todayUsage'] as int? ?? 0,
      extraLimit: map['extraLimit'] as int? ?? 0,
      sessionLimit: map['sessionLimit'] as int? ?? 0,
      sessionUsage: map['sessionUsage'] as int? ?? 0,
    );
  }

  @override
  String toString() {
    return 'CustomAppModel(packageName: $packageName, displayName: $displayName, hasIcon: ${icon != null}, isSystemApp: $isSystemApp, isFavorite: $isFavorite, countdown: $countdown, lastOpened: $lastOpened, todayLimit: $todayLimit, todayUsage: $todayUsage, extraLimit: $extraLimit, sessionLimit: $sessionLimit, sessionUsage: $sessionUsage)';
  }
}
