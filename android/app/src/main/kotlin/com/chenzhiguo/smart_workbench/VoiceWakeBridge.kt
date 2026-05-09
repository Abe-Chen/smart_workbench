package com.chenzhiguo.smart_workbench

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

object VoiceWakeBridge {
    private const val METHOD_CHANNEL = "smart_workbench/voice_wakeup"
    private const val EVENT_CHANNEL = "smart_workbench/voice_wakeup_events"

    @Volatile
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    fun attach(context: Context, flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL,
        ).setMethodCallHandler { call, result ->
            handleMethodCall(context.applicationContext, call, result)
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL,
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                val sink = events ?: return
                eventSink = sink
                VoiceWakeStore.consumePendingWake(context.applicationContext)?.let { event ->
                    sink.success(event)
                }
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    fun emitWake(context: Context, wakeWord: String) {
        val event = mapOf(
            "type" to "wake",
            "wakeWord" to wakeWord,
            "timestamp" to System.currentTimeMillis(),
        )
        val sink = eventSink
        if (sink == null) {
            VoiceWakeStore.savePendingWake(context.applicationContext, event)
        } else {
            postEvent(event) {
                VoiceWakeStore.savePendingWake(context.applicationContext, event)
            }
        }
    }

    fun emitStatus(status: Map<String, Any?>) {
        postEvent(mapOf("type" to "status", "status" to status))
    }

    fun emitError(code: String, message: String) {
        postEvent(
            mapOf(
                "type" to "error",
                "code" to code,
                "message" to message,
                "timestamp" to System.currentTimeMillis(),
            ),
        )
    }

    private fun postEvent(event: Map<String, Any?>, onMissingSink: (() -> Unit)? = null) {
        val dispatch = Runnable {
            val sink = eventSink
            if (sink == null) {
                onMissingSink?.invoke()
            } else {
                sink.success(event)
            }
        }
        if (Looper.myLooper() == Looper.getMainLooper()) {
            dispatch.run()
        } else {
            mainHandler.post(dispatch)
        }
    }

    private fun handleMethodCall(
        context: Context,
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            "getStatus" -> result.success(VoiceWakeRuntime.status(context))
            "start" -> result.success(start(context, call))
            "stop" -> result.success(stop(context))
            else -> result.notImplemented()
        }
    }

    private fun start(context: Context, call: MethodCall): Map<String, Any?> {
        val appId = call.argument<String>("appId").orEmpty()
        val apiKey = call.argument<String>("apiKey").orEmpty()
        val apiSecret = call.argument<String>("apiSecret").orEmpty()
        val wakeWord = call.argument<String>("wakeWord")?.takeIf { it.isNotBlank() } ?: "小治小治"

        if (!VoiceWakeRuntime.isSupported) {
            return VoiceWakeRuntime.status(context, lastError = "unsupported_platform")
        }
        if (!hasRecordAudioPermission(context)) {
            return VoiceWakeRuntime.status(context, lastError = "record_audio_permission_missing")
        }
        if (appId.isBlank() || apiKey.isBlank() || apiSecret.isBlank()) {
            return VoiceWakeRuntime.status(context, lastError = "xunfei_credentials_missing")
        }
        if (VoiceWakeForegroundService.isInWakeCooldown()) {
            return VoiceWakeRuntime.status(context, running = false)
        }

        val readiness = VoiceWakeRuntime.prepare(context, wakeWord)
        if (!readiness.sdkPresent) {
            return VoiceWakeRuntime.status(context, lastError = "aikit_sdk_missing")
        }
        if (!readiness.resourceReady) {
            return VoiceWakeRuntime.status(context, lastError = "aikit_resource_missing")
        }

        val intent = Intent(context, VoiceWakeForegroundService::class.java).apply {
            action = VoiceWakeForegroundService.ACTION_START
            putExtra(VoiceWakeForegroundService.EXTRA_APP_ID, appId)
            putExtra(VoiceWakeForegroundService.EXTRA_API_KEY, apiKey)
            putExtra(VoiceWakeForegroundService.EXTRA_API_SECRET, apiSecret)
            putExtra(VoiceWakeForegroundService.EXTRA_WAKE_WORD, wakeWord)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
        return VoiceWakeRuntime.status(context, running = true)
    }

    private fun stop(context: Context): Map<String, Any?> {
        context.startService(Intent(context, VoiceWakeForegroundService::class.java).apply {
            action = VoiceWakeForegroundService.ACTION_STOP
        })
        return VoiceWakeRuntime.status(context, running = false)
    }

    private fun hasRecordAudioPermission(context: Context): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.M ||
            context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
    }
}
