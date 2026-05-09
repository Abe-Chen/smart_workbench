package com.chenzhiguo.smart_workbench

import android.content.Context
import org.json.JSONObject

object VoiceWakeStore {
    private const val PREFS = "voice_wakeup"
    private const val KEY_PENDING_WAKE = "pending_wake"

    fun savePendingWake(context: Context, event: Map<String, Any?>) {
        val json = JSONObject()
        event.forEach { (key, value) -> json.put(key, value) }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_PENDING_WAKE, json.toString())
            .apply()
    }

    fun consumePendingWake(context: Context): Map<String, Any?>? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_PENDING_WAKE, null) ?: return null
        prefs.edit().remove(KEY_PENDING_WAKE).apply()
        return runCatching {
            val json = JSONObject(raw)
            val result = mutableMapOf<String, Any?>()
            json.keys().forEach { key -> result[key] = json.opt(key) }
            result
        }.getOrNull()
    }
}
