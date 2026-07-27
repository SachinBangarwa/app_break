package com.example.testproject

/**
 * CustomAppModel:
 * Yeh model class Dart side ke CustomAppModel.dart ko mirror karti hai.
 * Har ek app jiska limit ya usage hum track kar rahe hain, uska data is object me store hoga.
 */
data class CustomAppModel(
    // App ka package name (Unique ID) jaise: "com.whatsapp"
    val packageName: String,

    // App ka visible display name (Label) jaise: "WhatsApp"
    val displayName: String,

    // App ka icon blob (binary image data) jo SQLite database me saved hai
    val icon: ByteArray? = null,

    // Kya ye system app hai? (1 = System App, 0 = Installed/User App)
    val isSystemApp: Int,

    // Kya user ne is app ko favorited list me add kiya hai? (1 = Yes, 0 = No)
    val isFavorite: Int,

    // App open hone se pehle user ke liye screen pause delay (Mindful Delay in seconds)
    val countdown: Int,

    // App last time kis timestamp par open ki gayi thi
    val lastOpened: Long,

    // Aaj ke din ka user-set daily limit (Milliseconds me)
    var todayLimit: Long = 0,

    // Aaj ke din ka user ka accumulated usage time (Milliseconds me)
    var todayUsage: Long = 0,

    // Extra allowed extended limit time (2 minutes extend window button click par - Milliseconds me)
    var extraLimit: Long = 0,

    // Temporary active session limit (In-memory, jaise 5 min or 10 min - Milliseconds me)
    var sessionLimit: Long = 0,

    // Current temporary active session usage (In-memory - Milliseconds me)
    var sessionUsage: Long = 0
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false

        other as CustomAppModel

        if (packageName != other.packageName) return false
        if (displayName != other.displayName) return false
        if (icon != null) {
            if (other.icon == null) return false
            if (!icon.contentEquals(other.icon)) return false
        } else if (other.icon != null) return false
        if (isSystemApp != other.isSystemApp) return false
        if (isFavorite != other.isFavorite) return false
        if (countdown != other.countdown) return false
        if (lastOpened != other.lastOpened) return false
        if (todayLimit != other.todayLimit) return false
        if (todayUsage != other.todayUsage) return false
        if (extraLimit != other.extraLimit) return false
        if (sessionLimit != other.sessionLimit) return false
        if (sessionUsage != other.sessionUsage) return false

        return true
    }

    override fun hashCode(): Int {
        var result = packageName.hashCode()
        result = 31 * result + displayName.hashCode()
        result = 31 * result + (icon?.contentHashCode() ?: 0)
        result = 31 * result + isSystemApp
        result = 31 * result + isFavorite
        result = 31 * result + countdown
        result = 31 * result + lastOpened.hashCode()
        result = 31 * result + todayLimit.hashCode()
        result = 31 * result + todayUsage.hashCode()
        result = 31 * result + extraLimit.hashCode()
        result = 31 * result + sessionLimit.hashCode()
        result = 31 * result + sessionUsage.hashCode()
        return result
    }
}
