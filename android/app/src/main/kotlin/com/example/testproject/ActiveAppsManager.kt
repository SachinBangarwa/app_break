package com.example.testproject

import java.util.concurrent.ConcurrentHashMap

/**
 * ActiveAppsManager:
 * Yeh manager class Dart side ke ActiveAppsManager.dart ko mirror karti hai.
 * Isme saare active app models, dynamic session limits aur reminder settings in-memory (RAM) me maintain hoti hain.
 */
object ActiveAppsManager {
    // RAM cache jo sabhi active apps ke models (limits, usage) ko hold karti hai
    val activeAppsList = ArrayList<CustomAppModel>()

    // Session Limit Map (App packageName -> Limit in milliseconds)
    val sessionLimitMap = ConcurrentHashMap<String, Long>()

    // Session Start Time Map (App packageName -> Session Start Timestamp in milliseconds)
    val sessionStartTimeMap = ConcurrentHashMap<String, Long>()

    // Reminder Setting Option (Default is -1 meaning 'No reminder', values > 0 are preset minutes)
    var reminderOptionSetting: Int = -1

    /**
     * App list me se kisi app ka usage ya limits ko update karne ke liye helper function.
     * Dart side ke ActiveAppsManager.updateApp function ka counterpart.
     */
    fun updateApp(packageName: String, todayUsage: Long, extraLimit: Long? = null) {
        val app = activeAppsList.find { it.packageName == packageName }
        if (app != null) {
            app.todayUsage = todayUsage
            if (extraLimit != null) {
                app.extraLimit = extraLimit
            }
        }
    }
}
