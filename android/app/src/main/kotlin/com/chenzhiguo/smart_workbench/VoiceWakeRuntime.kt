package com.chenzhiguo.smart_workbench

import android.content.Context
import java.io.File

data class VoiceWakeReadiness(
    val sdkPresent: Boolean,
    val resourceReady: Boolean,
)

object VoiceWakeRuntime {
    const val ABILITY_ID = "e867a88f2"
    const val DEFAULT_WAKE_WORD = "小治小治"
    private val resourceAssetPaths = listOf("aikit_resources", "aikit/resource")

    val isSupported: Boolean = true

    fun prepare(context: Context, wakeWord: String = DEFAULT_WAKE_WORD): VoiceWakeReadiness {
        val workDir = workDir(context)
        workDir.mkdirs()
        resourceAssetPaths.forEach { assetPath ->
            copyAssetFolder(context, assetPath, workDir)
        }
        writeWakeWordFile(context, wakeWord)
        return VoiceWakeReadiness(
            sdkPresent = isAikitSdkPresent(),
            resourceReady = hasResourceFiles(resourceDir(context)),
        )
    }

    fun status(
        context: Context,
        running: Boolean = VoiceWakeForegroundService.isRunning,
        lastError: String? = VoiceWakeForegroundService.lastError,
    ): Map<String, Any?> {
        val readiness = prepare(context)
        return mapOf(
            "supported" to isSupported,
            "running" to running,
            "sdkPresent" to readiness.sdkPresent,
            "resourceReady" to readiness.resourceReady,
            "abilityId" to ABILITY_ID,
            "wakeWord" to DEFAULT_WAKE_WORD,
            "coolingDown" to VoiceWakeForegroundService.isInWakeCooldown(),
            "lastError" to lastError,
        )
    }

    fun workDir(context: Context): File {
        return File(context.filesDir, "iflytek_aikit")
    }

    fun resourceDir(context: Context): File {
        return File(workDir(context), "ivw")
    }

    fun wakeWordFile(context: Context): File {
        return File(workDir(context), "ivw/keyword.txt")
    }

    fun isAikitSdkPresent(): Boolean {
        return classCandidates("AiHelper").any { runCatching { Class.forName(it) }.isSuccess }
    }

    fun classCandidates(simpleName: String): List<String> {
        return listOf(
            "com.iflytek.aikit.core.$simpleName",
            "com.iflytek.aikit.$simpleName",
        )
    }

    private fun writeWakeWordFile(context: Context, wakeWord: String) {
        val file = wakeWordFile(context)
        file.parentFile?.mkdirs()
        val desired = "$wakeWord;nCM:300;\n"
        if (!file.exists() || file.readText() != desired) {
            file.writeText(desired)
        }
    }

    private fun hasResourceFiles(resourceDir: File): Boolean {
        if (!resourceDir.exists()) {
            return false
        }
        return resourceDir.walkTopDown().any { it.isFile && it.length() > 0L }
    }

    private fun copyAssetFolder(context: Context, assetPath: String, targetDir: File) {
        val children = runCatching { context.assets.list(assetPath)?.toList().orEmpty() }
            .getOrDefault(emptyList())
        if (children.isEmpty()) {
            return
        }
        targetDir.mkdirs()
        children.forEach { child ->
            val childAssetPath = "$assetPath/$child"
            val nested = runCatching { context.assets.list(childAssetPath)?.toList().orEmpty() }
                .getOrDefault(emptyList())
            val target = File(targetDir, child)
            if (nested.isNotEmpty()) {
                copyAssetFolder(context, childAssetPath, target)
            } else {
                context.assets.open(childAssetPath).use { input ->
                    val expectedBytes = input.available().toLong()
                    if (!target.exists() || target.length() != expectedBytes) {
                        target.outputStream().use { output -> input.copyTo(output) }
                    }
                }
            }
        }
    }
}
