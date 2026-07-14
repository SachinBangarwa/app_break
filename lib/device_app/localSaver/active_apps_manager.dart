import 'package:get/get.dart';
import 'custom_app_model.dart';

class ActiveAppsManager {
  // इन-मेमोरी रिएक्टिव लिस्ट (GetX RxList) जिसे ऐप में कहीं भी एक्सेस किया जा सकता है
  static final RxList<CustomAppModel> activeAppsList = <CustomAppModel>[].obs;

  // ऐप के पैरामीटर्स बदलने पर लिस्ट को मेमोरी में ही अपडेट/ऐड/डिलीट करने का फ़ंक्शन
  static void updateApp({
    required String packageName,
    required String displayName,
    required bool isSystemApp,
    bool? isFavorite,
    int? countdown,
    int? todayLimit,
    int? todayUsage,
    int? lastOpened,
  }) {
    int index = activeAppsList.indexWhere((app) => app.packageName == packageName);

    if (index != -1) {
      // यदि ऐप पहले से लिस्ट में मौजूद है
      var existing = activeAppsList[index];
      var updated = CustomAppModel(
        packageName: packageName,
        displayName: displayName,
        isSystemApp: isSystemApp,
        isFavorite: isFavorite ?? existing.isFavorite,
        countdown: countdown ?? existing.countdown,
        todayLimit: todayLimit ?? existing.todayLimit,
        todayUsage: todayUsage ?? existing.todayUsage,
        lastOpened: lastOpened ?? existing.lastOpened,
      );

      // यदि अपडेट के बाद कोई भी पैरामीटर सक्रिय नहीं बचता, तो इसे लिस्ट से हटा देंगे
      if (!updated.isFavorite && updated.countdown == 0 && updated.todayLimit == 0) {
        activeAppsList.removeAt(index);
      } else {
        activeAppsList[index] = updated;
      }
    } else {
      // यदि ऐप लिस्ट में नहीं है, तो चेक करेंगे कि क्या कोई पैरामीटर सक्रिय है
      bool shouldAdd = (isFavorite == true) || 
                       (countdown != null && countdown > 0) || 
                       (todayLimit != null && todayLimit > 0);

      if (shouldAdd) {
        activeAppsList.add(
          CustomAppModel(
            packageName: packageName,
            displayName: displayName,
            isSystemApp: isSystemApp,
            isFavorite: isFavorite ?? false,
            countdown: countdown ?? 0,
            todayLimit: todayLimit ?? 0,
            todayUsage: todayUsage ?? 0,
            lastOpened: lastOpened ?? 0,
          ),
        );
      }
    }
  }
}
