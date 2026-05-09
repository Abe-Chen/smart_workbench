package com.chenzhiguo.smart_workbench

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import java.lang.reflect.Proxy
import java.nio.charset.Charset
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.concurrent.thread

class XunfeiAikitWakeEngine(
    private val context: Context,
    private val config: Config,
    private val callback: Callback,
) {
    data class Config(
        val appId: String,
        val apiKey: String,
        val apiSecret: String,
        val wakeWord: String,
    )

    data class StartResult(
        val success: Boolean,
        val errorCode: String? = null,
        val message: String? = null,
    )

    interface Callback {
        fun onWake(wakeWord: String)
        fun onEngineError(code: String, message: String)
    }

    private val running = AtomicBoolean(false)
    private var audioRecord: AudioRecord? = null
    private var audioThread: Thread? = null
    private var helper: Any? = null
    private var handle: Any? = null

    fun start(): StartResult {
        if (running.get()) {
            return StartResult(success = true)
        }
        val helperClass = findAikitClass("AiHelper")
            ?: return StartResult(false, "aikit_sdk_missing", "AIKit SDK not found")

        return runCatching {
            helper = helperClass.getMethod("getInst").invoke(null)
            initAikit()
            registerListener()
            loadWakeResource()
            handle = startAbility()
            if (!isHandleSuccess(handle)) {
                val code = handle?.let { invokeAny(it, "getCode") }?.toString()
                throw IllegalStateException("AIKit start failed: ${code ?: "empty handle"}")
            }
            running.set(true)
            startAudioLoop()
            StartResult(success = true)
        }.getOrElse { error ->
            stop()
            StartResult(
                success = false,
                errorCode = "aikit_start_failed",
                message = error.message ?: error.javaClass.simpleName,
            )
        }
    }

    fun stop() {
        if (!running.getAndSet(false) && audioRecord == null && helper == null) {
            return
        }
        runCatching { sendAudioFrame(ByteArray(0), "END") }
        runCatching { audioRecord?.stop() }
        audioRecord?.release()
        audioRecord = null
        audioThread?.interrupt()
        audioThread = null
        runCatching { invokeAny(helper, "end", handle) }
        handle = null
        helper = null
    }

    private fun initAikit() {
        if (sdkInitialized) {
            return
        }
        synchronized(initLock) {
            if (sdkInitialized) {
                return
            }
            initAikitLocked()
            sdkInitialized = true
        }
    }

    private fun initAikitLocked() {
        val paramsClass = findAikitClass("BaseLibrary\$Params")
            ?: findAikitClass("AiHelper\$Params")
            ?: throw IllegalStateException("AIKit Params class not found")
        val builder = paramsClass.getMethod("builder").invoke(null)
        invokeIfExists(builder, "appId", config.appId)
        invokeIfExists(builder, "apiKey", config.apiKey)
        invokeIfExists(builder, "apiSecret", config.apiSecret)
        invokeIfExists(builder, "workDir", VoiceWakeRuntime.workDir(context).absolutePath)
        invokeIfExists(builder, "resDir", VoiceWakeRuntime.resourceDir(context).absolutePath)
        invokeIfExists(builder, "ability", VoiceWakeRuntime.ABILITY_ID)
        val params = invokeAny(builder, "build")
        val initCode = returnCode(
            invokeAny(helper, "initEntry", context, params)
                ?: invokeAny(helper, "init", context, params),
        )
        if (initCode != null && initCode != 0) {
            throw IllegalStateException("AIKit init failed: $initCode")
        }
    }

    private fun loadWakeResource() {
        val request = buildKeywordRequest()
        val loadCode = returnCode(invokeAny(helper, "loadData", VoiceWakeRuntime.ABILITY_ID, request))
        if (loadCode != null && loadCode != 0) {
            throw IllegalStateException("AIKit loadData failed: $loadCode")
        }
        val specifyCode = returnCode(
            invokeAny(
                helper,
                "specifyDataSet",
                VoiceWakeRuntime.ABILITY_ID,
                "key_word",
                intArrayOf(0),
            ),
        )
        if (specifyCode != null && specifyCode != 0) {
            throw IllegalStateException("AIKit specifyDataSet failed: $specifyCode")
        }
    }

    private fun registerListener() {
        val listenerClass = findAikitClass("AiListener")
            ?: findAikitClass("AiResponseListener")
            ?: return
        val proxy = Proxy.newProxyInstance(
            listenerClass.classLoader,
            arrayOf(listenerClass),
        ) { _, method, args ->
            when (method.name) {
                "onResult" -> {
                    if (args?.any(::looksLikeWakeResult) == true) {
                        running.set(false)
                        callback.onWake(config.wakeWord)
                    }
                }
                "onError" -> {
                    val message = args?.joinToString(separator = " ") { it?.toString().orEmpty() }
                        .orEmpty()
                    callback.onEngineError("aikit_runtime_error", message)
                }
            }
            null
        }

        if (!invokeIfExists(helper, "registerListener", VoiceWakeRuntime.ABILITY_ID, proxy)) {
            invokeIfExists(helper, "registerListener", proxy)
        }
    }

    private fun startAbility(): Any? {
        val request = buildRequest()
        val started = invokeAny(helper, "start", VoiceWakeRuntime.ABILITY_ID, request, null)
            ?: invokeAny(helper, "start", VoiceWakeRuntime.ABILITY_ID, request)
        return started
    }

    @SuppressLint("MissingPermission")
    private fun startAudioLoop() {
        val minBufferSize = AudioRecord.getMinBufferSize(
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        ).coerceAtLeast(FRAME_SIZE * 4)
        val recorder = AudioRecord(
            MediaRecorder.AudioSource.MIC,
            SAMPLE_RATE,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            minBufferSize,
        )
        recorder.startRecording()
        audioRecord = recorder

        audioThread = thread(name = "xunfei-aikit-wake-audio") {
            val buffer = ByteArray(FRAME_SIZE)
            var firstFrame = true
            while (running.get() && !Thread.currentThread().isInterrupted) {
                val read = recorder.read(buffer, 0, buffer.size)
                if (read <= 0) {
                    continue
                }
                if (!running.get()) {
                    break
                }
                val payload = if (read == buffer.size) buffer else buffer.copyOf(read)
                val status = if (firstFrame) "BEGIN" else "CONTINUE"
                firstFrame = false
                runCatching { sendAudioFrame(payload, status) }
                    .onFailure {
                        callback.onEngineError(
                            "aikit_audio_write_failed",
                            it.message ?: it.javaClass.simpleName,
                        )
                        running.set(false)
                    }
            }
        }
    }

    private fun sendAudioFrame(payload: ByteArray, statusName: String) {
        val status = enumValue("AiStatus", statusName)
        val request = buildAudioRequest(payload, status)
        invokeAny(helper, "write", request, handle)
    }

    private fun buildRequest(): Any {
        val requestClass = requestClass()
        val builder = requestClass.getMethod("builder").invoke(null)
        invokeIfExists(builder, "param", "wdec_param_nCmThreshold", "0 0:800")
        invokeIfExists(builder, "param", "gramLoad", true)
        return invokeAny(builder, "build")
            ?: throw IllegalStateException("AIRequest build failed")
    }

    private fun buildKeywordRequest(): Any {
        val requestClass = requestClass()
        val builder = requestClass.getMethod("builder").invoke(null)
        val keywordPath = VoiceWakeRuntime.wakeWordFile(context).absolutePath
        if (!invokeIfExists(builder, "customText", "key_word", keywordPath, 0)) {
            throw IllegalStateException("AIRequest customText builder method not found")
        }
        return invokeAny(builder, "build")
            ?: throw IllegalStateException("AIRequest keyword build failed")
    }

    private fun buildAudioRequest(payload: ByteArray, status: Any?): Any {
        val requestClass = requestClass()
        val builder = requestClass.getMethod("builder").invoke(null)
        val audio = buildAudio(payload, status)
        if (!invokeIfExists(builder, "payload", audio)) {
            throw IllegalStateException("AIRequest payload builder method not found")
        }
        return invokeAny(builder, "build")
            ?: throw IllegalStateException("AIRequest audio build failed")
    }

    private fun buildAudio(payload: ByteArray, status: Any?): Any {
        val audioClass = findAikitClass("AiAudio")
            ?: throw IllegalStateException("AiAudio class not found")
        val audio = invokeStaticAny(audioClass, "get", "wav")
            ?: audioClass.getDeclaredConstructor().newInstance()
        val withData = invokeAny(audio, "data", payload) ?: audio
        val encoding = staticField("AiAudio", "ENCODING_DEFAULT")
            ?: enumValue("AiAudio\$Encoding", "RAW")
        val withEncoding = encoding?.let {
            invokeAny(withData, "encoding", it)
        } ?: withData
        val withStatus = status?.let { invokeAny(withEncoding, "status", it) } ?: withEncoding
        return invokeAny(withStatus, "valid") ?: withStatus
    }

    private fun looksLikeWakeResult(value: Any?): Boolean {
        if (value == null) {
            return false
        }
        if (value is Iterable<*>) {
            return value.any(::looksLikeWakeResult)
        }
        if (value is Array<*>) {
            return value.any(::looksLikeWakeResult)
        }
        val key = runCatching {
            value.javaClass.methods.firstOrNull { it.name == "getKey" && it.parameterCount == 0 }
                ?.invoke(value)
                ?.toString()
        }.getOrNull()
        if (key == "func_wake_up") {
            return true
        }
        if (key == "func_pre_wakeup") {
            return false
        }
        val text = resultText(value)
        return text.contains(config.wakeWord) ||
            text.contains("func_wake_up", ignoreCase = true)
    }

    private fun requestClass(): Class<*> {
        return findAikitClass("AiRequest")
            ?: findAikitClass("AIRequest")
            ?: throw IllegalStateException("AiRequest class not found")
    }

    private fun resultText(value: Any): String {
        val direct = value.toString()
        val methodText = listOf("getValue", "getData", "getResult", "getKey")
            .mapNotNull { name ->
                runCatching {
                    val raw = value.javaClass.methods.firstOrNull { it.name == name && it.parameterCount == 0 }
                        ?.invoke(value)
                    when (raw) {
                        is ByteArray -> raw.toString(Charset.forName("UTF-8"))
                        null -> null
                        else -> raw.toString()
                    }
                }.getOrNull()
            }
            .joinToString(separator = " ")
        return "$direct $methodText"
    }

    private fun findAikitClass(simpleName: String): Class<*>? {
        return VoiceWakeRuntime.classCandidates(simpleName)
            .firstNotNullOfOrNull { name -> runCatching { Class.forName(name) }.getOrNull() }
    }

    private fun enumValue(simpleName: String, valueName: String): Any? {
        val enumClass = findAikitClass(simpleName) ?: return null
        return enumClass.enumConstants?.firstOrNull { it.toString() == valueName }
    }

    private fun staticField(simpleName: String, fieldName: String): Any? {
        val targetClass = findAikitClass(simpleName) ?: return null
        return runCatching { targetClass.getField(fieldName).get(null) }.getOrNull()
    }

    private fun isHandleSuccess(candidate: Any?): Boolean {
        if (candidate == null) {
            return false
        }
        val success = invokeAny(candidate, "isSuccess")
        if (success is Boolean) {
            return success
        }
        val code = returnCode(invokeAny(candidate, "getCode"))
        return code == null || code == 0
    }

    private fun returnCode(candidate: Any?): Int? {
        return when (candidate) {
            is Int -> candidate
            is Number -> candidate.toInt()
            is String -> candidate.toIntOrNull()
            null -> null
            else -> null
        }
    }

    private fun invokeIfExists(target: Any?, methodName: String, vararg args: Any?): Boolean {
        return runCatching {
            invokeAny(target, methodName, *args) != null
        }.getOrDefault(false)
    }

    private fun invokeAny(target: Any?, methodName: String, vararg args: Any?): Any? {
        val actualTarget = target ?: return null
        val method = actualTarget.javaClass.methods.firstOrNull { method ->
            method.name == methodName && method.parameterCount == args.size &&
                method.parameterTypes.zip(args).all { (type, arg) -> isCompatible(type, arg) }
        } ?: return null
        return method.invoke(actualTarget, *args)
    }

    private fun invokeStaticAny(targetClass: Class<*>, methodName: String, vararg args: Any?): Any? {
        val method = targetClass.methods.firstOrNull { method ->
            method.name == methodName && method.parameterCount == args.size &&
                method.parameterTypes.zip(args).all { (type, arg) -> isCompatible(type, arg) }
        } ?: return null
        return method.invoke(null, *args)
    }

    private fun isCompatible(type: Class<*>, arg: Any?): Boolean {
        if (arg == null) {
            return !type.isPrimitive
        }
        if (type.isPrimitive) {
            return when (type.name) {
                "boolean" -> arg is Boolean
                "byte" -> arg is Byte
                "char" -> arg is Char
                "short" -> arg is Short
                "int" -> arg is Int
                "long" -> arg is Long
                "float" -> arg is Float
                "double" -> arg is Double
                else -> false
            }
        }
        return type.isAssignableFrom(arg.javaClass)
    }

    companion object {
        private const val SAMPLE_RATE = 16_000
        private const val FRAME_SIZE = 1280

        private val initLock = Any()

        @Volatile
        private var sdkInitialized = false
    }
}
