package com.example.testproject

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.util.Log

/**
 * AppDbHelper:
 * Yeh class Dart side ke localSaver/db_helper.dart ki exact native copy (duplicate) hai.
 * Yeh completely standalone tarike se database create karne, tables verify karne aur dynamic columns
 * alter (upgrade) karne ka saara logic natively execute karti hai.
 */
class AppDbHelper(private val context: Context) : SQLiteOpenHelper(context, DATABASE_NAME, null, DATABASE_VERSION) {

    companion object {
        private const val DATABASE_NAME = "testproject_v2.db"
        private const val DATABASE_VERSION = 1
    }

    /**
     * Database create hone par call hota hai.
     * Dart ke _createDB function ki tarah, installed_apps table ko saare initial columns ke sath create karta hai.
     */
    override fun onCreate(db: SQLiteDatabase?) {
        try {
            db?.execSQL(
                "CREATE TABLE installed_apps (" +
                "id INTEGER PRIMARY KEY AUTOINCREMENT, " +
                "packageName TEXT UNIQUE, " +
                "displayName TEXT, " +
                "icon BLOB, " +
                "isSystemApp INTEGER, " +
                "isFavorite INTEGER DEFAULT 0, " +
                "countdown INTEGER DEFAULT 0, " +
                "lastOpened INTEGER DEFAULT 0, " +
                "todayLimit INTEGER DEFAULT 0, " +
                "todayUsage INTEGER DEFAULT 0, " +
                "extraLimit INTEGER DEFAULT 0" +
                ")"
            )
        } catch (e: Exception) {
        }
    }

    /**
     * Database open hone par call hota hai.
     * Dart ke _onOpen function ka duplicate logic:
     * 1. notifications table agar nahi hai, toh create karta hai.
     * 2. table_info check karke dynamic columns verify karta hai aur alter column commands run karta hai.
     */
    override fun onOpen(db: SQLiteDatabase?) {
        super.onOpen(db)
        try {
            // 1. Notifications table check / create
            db?.execSQL(
                "CREATE TABLE IF NOT EXISTS notifications (" +
                "id INTEGER PRIMARY KEY AUTOINCREMENT, " +
                "packageName TEXT, " +
                "title TEXT, " +
                "body TEXT, " +
                "timestamp INTEGER" +
                ")"
            )

            // 2. Column schema check & upgrades (PRAGMA table_info checking)
            val columns = ArrayList<String>()
            val cursor = db?.rawQuery("PRAGMA table_info(installed_apps)", null)
            if (cursor != null && cursor.moveToFirst()) {
                do {
                    columns.add(cursor.getString(1)) // Column name index is 1
                } while (cursor.moveToNext())
                cursor.close()
            }

            val newCols = mapOf(
                "countdown" to "INTEGER DEFAULT 0",
                "lastOpened" to "INTEGER DEFAULT 0",
                "todayLimit" to "INTEGER DEFAULT 0",
                "todayUsage" to "INTEGER DEFAULT 0",
                "extraLimit" to "INTEGER DEFAULT 0"
            )

            // Agar koi column missing hai toh use ALTER TABLE command se add karega
            for ((colName, colType) in newCols) {
                if (!columns.contains(colName)) {
                    db?.execSQL("ALTER TABLE installed_apps ADD COLUMN $colName $colType")
                }
            }
        } catch (e: Exception) {
        }
    }

    override fun onUpgrade(db: SQLiteDatabase?, oldVersion: Int, newVersion: Int) {
        // No-Op
    }

    override fun getWritableDatabase(): SQLiteDatabase {
        val dbFile = context.getDatabasePath(DATABASE_NAME)
        return SQLiteDatabase.openDatabase(dbFile.absolutePath, null, SQLiteDatabase.OPEN_READWRITE)
    }

    override fun getReadableDatabase(): SQLiteDatabase {
        val dbFile = context.getDatabasePath(DATABASE_NAME)
        return SQLiteDatabase.openDatabase(dbFile.absolutePath, null, SQLiteDatabase.OPEN_READONLY)
    }

    /**
     * getActiveAppsFromDb:
     * SQLite se un apps ko fetch karta hai jinke limits, favorites ya delays configured hain.
     */
    fun getActiveAppsFromDb(): List<CustomAppModel> {
        val list = ArrayList<CustomAppModel>()
        try {
            val db = readableDatabase
            val cursor = db.rawQuery(
                "SELECT packageName, displayName, icon, isSystemApp, isFavorite, countdown, lastOpened, todayLimit, todayUsage, extraLimit " +
                "FROM installed_apps WHERE isFavorite = 1 OR countdown > 0 OR todayLimit > 0",
                null
            )
            if (cursor.moveToFirst()) {
                do {
                    list.add(CustomAppModel(
                        packageName = cursor.getString(0) ?: "",
                        displayName = cursor.getString(1) ?: "",
                        icon = cursor.getBlob(2),
                        isSystemApp = cursor.getInt(3),
                        isFavorite = cursor.getInt(4),
                        countdown = cursor.getInt(5),
                        lastOpened = cursor.getLong(6),
                        todayLimit = cursor.getLong(7),
                        todayUsage = cursor.getLong(8),
                        extraLimit = cursor.getLong(9)
                    ))
                } while (cursor.moveToNext())
            }
            cursor.close()
        } catch (e: Exception) {
        }
        return list
    }

    fun updateAppUsage(packageName: String, usageMs: Long) {
        try {
            val db = writableDatabase
            db.execSQL("UPDATE installed_apps SET todayUsage = ? WHERE packageName = ?", arrayOf(usageMs, packageName))
        } catch (e: Exception) {
        }
    }

    fun updateAppExtraLimit(packageName: String, extraLimitMs: Long) {
        try {
            val db = writableDatabase
            db.execSQL("UPDATE installed_apps SET extraLimit = ? WHERE packageName = ?", arrayOf(extraLimitMs, packageName))
        } catch (e: Exception) {
        }
    }
}
