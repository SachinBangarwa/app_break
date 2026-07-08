package com.example.testproject

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import android.app.PendingIntent

class MyNotificationListenerService : NotificationListenerService() {

    companion object {
        // Map to keep track of live notification PendingIntents in memory
        val pendingIntentsMap = HashMap<Long, PendingIntent>()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return

        val packageName = sbn.packageName

        // 1. Print all incoming notification details (A to Z)
        val sb = StringBuilder()
        sb.append("\n=== INCOMING NOTIFICATION DETAILED LOG ===\n")
        sb.append("Package Name: $packageName\n")
        sb.append("Post Time: ${sbn.postTime}\n")
        sb.append("Key: ${sbn.key}\n")
        sb.append("Id: ${sbn.id}\n")
        sb.append("Tag: ${sbn.tag ?: "null"}\n")
        
        val notification = sbn.notification
        if (notification != null) {
            sb.append("Channel ID: ${notification.channelId}\n")
            sb.append("Flags: ${notification.flags}\n")
            sb.append("Has ContentIntent: ${notification.contentIntent != null}\n")
            sb.append("Has DeleteIntent: ${notification.deleteIntent != null}\n")
            
            val notificationExtras = notification.extras
            if (notificationExtras != null) {
                sb.append("--- Extras Keys & Values ---\n")
                for (key in notificationExtras.keySet()) {
                    try {
                        val value = notificationExtras.get(key)
                        sb.append("  $key: $value\n")
                    } catch (e: Exception) {
                        sb.append("  $key: [Error reading value: ${e.message}]\n")
                    }
                }
            }
        }
        sb.append("==========================================")
        Log.d("NotificationDetailed", sb.toString())

        // Check if saver is enabled in SharedPreferences
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val isEnabled = prefs.getBoolean("flutter.is_notification_saver_enabled", true)
        if (!isEnabled) {
            Log.d("NotificationSaver", "Saver is disabled. Ignoring notification for $packageName")
            return
        }

        // Ignore system packages or our own package to prevent loop/clutter
        if (packageName == "android" || packageName == "com.example.testproject" || packageName == "com.android.systemui") {
            return
        }

        // Ignore Group Summary notifications (e.g. Gmail/WhatsApp headers showing notification count) from saving,
        // but dismiss them from the status bar so they don't linger.
        val isGroupSummary = (sbn.notification.flags and android.app.Notification.FLAG_GROUP_SUMMARY) != 0
        if (isGroupSummary) {
            try {
                cancelNotification(sbn.key)
                Log.d("NotificationSaver", "Dismissed group summary notification for: $packageName")
            } catch (e: Exception) {
                Log.e("NotificationSaver", "Error dismissing group summary: ${e.message}")
            }
            return
        }

        val extras = sbn.notification.extras
        val title = extras.getString("android.title") ?: ""
        val text = extras.getCharSequence("android.text")?.toString() ?: ""
        val timestamp = sbn.postTime

        // Only save if there is content (title or body is not empty)
        if (title.isNotEmpty() || text.isNotEmpty()) {
            try {
                // Open SQLite database directly in Kotlin
                val dbFile = getDatabasePath("testproject_v2.db")
                val db = SQLiteDatabase.openDatabase(dbFile.absolutePath, null, SQLiteDatabase.OPEN_READWRITE)

                val values = ContentValues().apply {
                    put("packageName", packageName)
                    put("title", title)
                    put("body", text)
                    put("timestamp", timestamp)
                }

                // Query the latest saved notification for this package to check for duplicates
                val cursor = db.query(
                    "notifications",
                    arrayOf("id", "title", "body", "timestamp"),
                    "packageName = ?",
                    arrayOf(packageName),
                    null, null, "timestamp DESC", "1"
                )

                var duplicateId: Long? = null
                if (cursor != null) {
                    if (cursor.moveToFirst()) {
                        val lastId = cursor.getLong(cursor.getColumnIndexOrThrow("id"))
                        val lastTitle = cursor.getString(cursor.getColumnIndexOrThrow("title"))
                        val lastBody = cursor.getString(cursor.getColumnIndexOrThrow("body"))
                        val lastTimestamp = cursor.getLong(cursor.getColumnIndexOrThrow("timestamp"))

                        // If title and body match, and it's within 5 minutes (300,000 ms), treat as duplicate
                        if (lastTitle == title && lastBody == text && (timestamp - lastTimestamp) < 300000) {
                            duplicateId = lastId
                        }
                    }
                    cursor.close()
                }

                if (duplicateId != null) {
                    // Update existing notification's timestamp instead of inserting a duplicate
                    val updateValues = ContentValues().apply {
                        put("timestamp", timestamp)
                    }
                    db.update("notifications", updateValues, "id = ?", arrayOf(duplicateId.toString()))
                    db.close()
                    Log.d("NotificationSaver", "Updated timestamp for duplicate notification ID: $duplicateId")

                    // Update PendingIntent in memory to the latest one
                    if (sbn.notification.contentIntent != null) {
                        pendingIntentsMap[duplicateId] = sbn.notification.contentIntent
                    }
                } else {
                    // Print what we are about to save
                    Log.d("NotificationDetailed", "--- DATABASE SAVE ATTEMPT ---\nPackage: $packageName\nTitle: $title\nBody: $text\nTimestamp: $timestamp\n-----------------------------")

                    // Insert into notifications table
                    val rowId = db.insert("notifications", null, values)
                    db.close()
                    Log.d("NotificationSaver", "Saved notification ID: $rowId for package: $packageName")

                    // If insert is successful, map rowId to its PendingIntent in memory
                    if (rowId != -1L && sbn.notification.contentIntent != null) {
                        pendingIntentsMap[rowId] = sbn.notification.contentIntent
                    }
                }

                // Send broadcast to update UI in real-time
                val uiIntent = Intent("com.example.testproject.NOTIFICATION_SAVED")
                uiIntent.setPackage(getPackageName())
                sendBroadcast(uiIntent)
            } catch (e: Exception) {
                Log.e("NotificationSaver", "Error saving notification: ${e.message}")
            }
        }

        // Cancel/Dismiss the notification from the system status bar
        try {
            cancelNotification(sbn.key)
            Log.d("NotificationSaver", "Dismissed notification for: $packageName")
        } catch (e: Exception) {
            Log.e("NotificationSaver", "Error dismissing notification: ${e.message}")
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        // No action needed
    }
}
