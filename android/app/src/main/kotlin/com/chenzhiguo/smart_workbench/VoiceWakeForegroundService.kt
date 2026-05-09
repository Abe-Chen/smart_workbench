package com.chenzhiguo.smart_workbench

import android.app.Notification
import android.app.PendingIntent
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper

class VoiceWakeForegroundService : Service(), XunfeiAikitWakeEngine.Callback {
    private val handler = Handler(Looper.getMainLooper())
    private var engine: XunfeiAikitWakeEngine? = null
    private var lastConfig: XunfeiAikitWakeEngine.Config? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopWake()
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_START -> {
                val config = configFromIntent(intent)
                if (config == null) {
                    lastError = "xunfei_credentials_missing"
                    stopSelf()
                    return START_NOT_STICKY
                }
                lastConfig = config
                startForegroundService()
                startWake(config)
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        stopWake()
        super.onDestroy()
    }

    override fun onWake(wakeWord: String) {
        cooldownUntilMillis = System.currentTimeMillis() + RESTART_DELAY_MS
        VoiceWakeBridge.emitWake(this, wakeWord)
        launchAppForWake()
        stopWake()
        handler.postDelayed({
            lastConfig?.let { startWake(it) }
        }, RESTART_DELAY_MS)
    }

    override fun onEngineError(code: String, message: String) {
        lastError = code
        VoiceWakeBridge.emitError(code, message)
        stopWake()
    }

    private fun startWake(config: XunfeiAikitWakeEngine.Config) {
        if (isRunning) {
            return
        }
        if (isInWakeCooldown()) {
            VoiceWakeBridge.emitStatus(VoiceWakeRuntime.status(this, running = false))
            return
        }
        val readiness = VoiceWakeRuntime.prepare(this, config.wakeWord)
        if (!readiness.sdkPresent) {
            lastError = "aikit_sdk_missing"
            VoiceWakeBridge.emitStatus(VoiceWakeRuntime.status(this, running = false))
            stopSelf()
            return
        }
        if (!readiness.resourceReady) {
            lastError = "aikit_resource_missing"
            VoiceWakeBridge.emitStatus(VoiceWakeRuntime.status(this, running = false))
            stopSelf()
            return
        }

        val wakeEngine = XunfeiAikitWakeEngine(applicationContext, config, this)
        engine = wakeEngine
        val result = wakeEngine.start()
        isRunning = result.success
        lastError = result.errorCode
        if (result.success) {
            cooldownUntilMillis = 0L
        }
        VoiceWakeBridge.emitStatus(VoiceWakeRuntime.status(this, running = isRunning))
        if (!result.success) {
            stopWake()
            stopSelf()
        }
    }

    private fun stopWake() {
        handler.removeCallbacksAndMessages(null)
        engine?.stop()
        engine = null
        isRunning = false
        VoiceWakeBridge.emitStatus(VoiceWakeRuntime.status(this, running = false))
    }

    private fun configFromIntent(intent: Intent): XunfeiAikitWakeEngine.Config? {
        val appId = intent.getStringExtra(EXTRA_APP_ID).orEmpty()
        val apiKey = intent.getStringExtra(EXTRA_API_KEY).orEmpty()
        val apiSecret = intent.getStringExtra(EXTRA_API_SECRET).orEmpty()
        val wakeWord = intent.getStringExtra(EXTRA_WAKE_WORD)
            ?.takeIf { it.isNotBlank() }
            ?: VoiceWakeRuntime.DEFAULT_WAKE_WORD
        if (appId.isBlank() || apiKey.isBlank() || apiSecret.isBlank()) {
            return null
        }
        return XunfeiAikitWakeEngine.Config(
            appId = appId,
            apiKey = apiKey,
            apiSecret = apiSecret,
            wakeWord = wakeWord,
        )
    }

    private fun startForegroundService() {
        createNotificationChannel()
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = launchIntent?.let {
            PendingIntent.getActivity(
                this,
                0,
                it,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("小治正在等待唤醒")
            .setContentText("说“小治小治”即可开始语音对话")
            .setContentIntent(pendingIntent)
            .setOngoing(true)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            @Suppress("DEPRECATION")
            builder.setPriority(Notification.PRIORITY_LOW)
        }
        val notification = builder.build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "小治语音唤醒",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "用于在后台监听“小治小治”唤醒词"
        }
        manager.createNotificationChannel(channel)
    }

    private fun launchAppForWake() {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName) ?: return
        launchIntent.addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP,
        )
        launchIntent.putExtra("voice_wakeup", true)
        runCatching { startActivity(launchIntent) }
    }

    companion object {
        const val ACTION_START = "com.chenzhiguo.smart_workbench.voice_wake.START"
        const val ACTION_STOP = "com.chenzhiguo.smart_workbench.voice_wake.STOP"
        const val EXTRA_APP_ID = "app_id"
        const val EXTRA_API_KEY = "api_key"
        const val EXTRA_API_SECRET = "api_secret"
        const val EXTRA_WAKE_WORD = "wake_word"

        private const val CHANNEL_ID = "voice_wakeup"
        private const val NOTIFICATION_ID = 9201
        private const val RESTART_DELAY_MS = 30_000L

        @Volatile
        var isRunning: Boolean = false
            private set

        @Volatile
        var lastError: String? = null
            private set

        @Volatile
        private var cooldownUntilMillis: Long = 0L

        fun isInWakeCooldown(): Boolean {
            return System.currentTimeMillis() < cooldownUntilMillis
        }
    }
}
