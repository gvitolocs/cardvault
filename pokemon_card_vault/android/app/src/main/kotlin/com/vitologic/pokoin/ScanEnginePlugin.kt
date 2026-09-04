package com.vitologic.pokoin

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.SystemClock
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import org.tensorflow.lite.Interpreter
import org.tensorflow.lite.gpu.CompatibilityList
import org.tensorflow.lite.gpu.GpuDelegate
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/** On-device Fast: exclusive GPU owner (YOLO TFLite or identify CNN) + 128-d cosine. */
class ScanEnginePlugin(private val appContext: Context) : MethodChannel.MethodCallHandler {
    private val yoloLock = Any()
    private val miloLock = Any()
    private val catalogLock = Any()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val detectExecutor = Executors.newSingleThreadExecutor { r ->
        Thread({
            AndroidScanPipeline.boostCurrentThread()
            r.run()
        }, "pokoin.scan.detect")
    }
    private val identifyExecutor = Executors.newSingleThreadExecutor { r ->
        Thread({
            AndroidScanPipeline.boostCurrentThread()
            r.run()
        }, "pokoin.scan.identify")
    }
    private val miloGpuExecutor = Executors.newSingleThreadExecutor { r ->
        Thread({
            AndroidScanPipeline.boostCurrentThread()
            r.run()
        }, "pokoin.scan.milo-gpu")
    }
    private val gemvPool = Executors.newFixedThreadPool(AndroidScanPipeline.gemvThreads()) { r ->
        Thread(r, "pokoin.scan.gemv").apply { isDaemon = true }
    }
    @Volatile private var interpreter: Interpreter? = null
    @Volatile private var gpuDelegate: GpuDelegate? = null
    @Volatile private var cnnInterpreter: Interpreter? = null
    @Volatile private var cnnGpuDelegate: GpuDelegate? = null
    private var ortEnv: OrtEnvironment? = null
    private var miloSession: OrtSession? = null
    private var miloSessionOpts: OrtSession.SessionOptions? = null
    private var cnnNhwc = false
    private var embeddings: FloatArray = FloatArray(0)
    private var scoreBuf: FloatArray = FloatArray(0)
    private var cards: Array<Card> = emptyArray()
    private var junkCard: BooleanArray = BooleanArray(0)
    private val dim = 128
    @Volatile private var ready = false
    @Volatile private var identifyRunning = false
    private val miloEarlyExit = 0.60f
    private var miloBackend = "ort"
    @Volatile private var yoloBackend = "pending"
    @Volatile private var gpuOwner = AndroidScanPipeline.GpuOwner.YOLO
    private var warmupMs = 0
    private var miloPredictMs = 0
    private var lastPreprocessMs = 0
    private var lastPredictMs = 0
    private var lastSearchMs = 0
    private var lastGemvMs = 0
    private var lastTopkMs = 0
    private var lastEmbeds = 0
    private var catalogGallery = "western"
    private val catalogNames = setOf("western", "japanese", "chinese")
    private var accelFile: File? = null
    private var yoloModelFile: File? = null
    private var miloModelFile: File? = null
    private var cnnTfliteFile: File? = null
    private var cnnOnnxFile: File? = null
    private var miloCtxFile: File? = null
    private var yoloInBuf: ByteBuffer? = null
    private var yoloOutBuf: ByteBuffer? = null
    private var yoloNhwc: FloatArray? = null
    private var yoloPixels: IntArray? = null
    private var miloNchw: FloatArray? = null
    private var miloPixels: IntArray? = null
    private var miloDirect: ByteBuffer? = null
    private var cnnOutBuf: ByteBuffer? = null
    private var detectArgb: IntArray? = null
    private var detectBitmap: Bitmap? = null
    private var identifyArgb: IntArray? = null
    private var identifyBitmap: Bitmap? = null
    private var yoloLetterbox: Bitmap? = null
    private val yoloLetterPaint = Paint(Paint.FILTER_BITMAP_FLAG)

    data class Card(
        val id: String,
        val name: String,
        val collectorNumber: String?,
        val set: String?,
    )

    data class Box(val x1: Float, val y1: Float, val x2: Float, val y2: Float, val conf: Float)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickBackCamera" -> {
                result.success(AndroidScanPipeline.pickDefaultBackCamera(appContext))
            }
            "bundleStamp" -> {
                val info = appContext.packageManager.getPackageInfo(appContext.packageName, 0)
                val code = if (android.os.Build.VERSION.SDK_INT >= 28) {
                    info.longVersionCode
                } else {
                    @Suppress("DEPRECATION")
                    info.versionCode.toLong()
                }
                result.success(code.toString())
            }
            "init" -> {
                val dir = call.argument<String>("dir") ?: ""
                val gallery = call.argument<String>("gallery") ?: "western"
                Thread({
                    try {
                        bootstrap(dir, gallery)
                        val n = cards.size
                        mainHandler.post {
                            result.success(
                                mapOf(
                                    "ok" to true,
                                    "miloN" to n,
                                    "yolo" to (interpreter != null),
                                    "milo" to (miloSession != null || cnnInterpreter != null),
                                    "miloBackend" to miloBackend,
                                    "yoloBackend" to yoloBackend,
                                    "gpuOwner" to gpuOwner.name.lowercase(),
                                    "warmupMs" to warmupMs,
                                    "predictMs" to miloPredictMs,
                                    "gallery" to catalogGallery,
                                ),
                            )
                        }
                    } catch (error: Exception) {
                        mainHandler.post { result.error("init_failed", error.message, null) }
                    }
                }, "pokoin.scan.init").start()
            }
            "setCatalog" -> {
                val dir = call.argument<String>("dir") ?: ""
                val gallery = call.argument<String>("gallery") ?: "western"
                runNative(identifyExecutor, result, "catalog_failed") {
                    synchronized(catalogLock) { loadCatalog(dir, gallery) }
                    mapOf(
                        "ok" to true,
                        "miloN" to cards.size,
                        "gallery" to catalogGallery,
                    )
                }
            }
            "setGpuOwner" -> {
                val next = AndroidScanPipeline.parseGpuOwner(call.argument<String>("owner"))
                val restart = next != gpuOwner
                gpuOwner = next
                val dir = accelFile?.parentFile
                    ?: File(appContext.filesDir, "fast_scan")
                if (next == AndroidScanPipeline.GpuOwner.MILO) {
                    MiloQnnGpu.clearSkip(dir)
                }
                saveAccel()
                val hasCnn = File(dir, "milo_cnn.tflite").isFile ||
                    File(dir, "milo_cnn.onnx").isFile
                val needPrep = next == AndroidScanPipeline.GpuOwner.MILO &&
                    !hasCnn &&
                    !MiloQnnGpu.ctxReady(dir)
                android.util.Log.i(
                    "pokoin.scan",
                    "gpu owner=$gpuOwner restart=$restart needPrep=$needPrep cnn=$hasCnn ctx=${MiloQnnGpu.ctxFile(dir).length()}",
                )
                result.success(
                    mapOf(
                        "ok" to true,
                        "gpuOwner" to gpuOwner.name.lowercase(),
                        "yoloBackend" to yoloBackend,
                        "miloBackend" to miloBackend,
                        "restart" to restart,
                        "prep" to needPrep,
                    ),
                )
                if (needPrep) {
                    MiloQnnPrepService.start(appContext, dir.absolutePath)
                    mainHandler.postDelayed({
                        android.util.Log.i("pokoin.scan", "kill ui for qnn_prep")
                        Process.killProcess(Process.myPid())
                    }, 600)
                } else if (restart) {
                    mainHandler.postDelayed({ restartProcess() }, 250)
                }
            }
            "setYoloAccel" -> {
                val gpu = call.argument<Boolean>("gpu") ?: true
                runNative(detectExecutor, result, "yolo_accel_failed") {
                    setYoloAccel(gpu)
                    mapOf(
                        "ok" to true,
                        "yoloBackend" to yoloBackend,
                        "miloBackend" to miloBackend,
                    )
                }
            }
            "scan" -> {
                val bytes = call.argument<ByteArray>("bytes")
                val topK = call.argument<Int>("topK") ?: 5
                val multi = (call.argument<String>("mode") ?: "fast").equals("multi", ignoreCase = true)
                if (bytes == null || bytes.isEmpty()) {
                    result.error("bad_args", "missing image bytes", null)
                    return
                }
                runNative(identifyExecutor, result, "scan_failed") {
                    val bitmap = decodeJpeg(bytes)
                    try {
                        scanBitmap(bitmap, max(1, min(topK, 10)), multi, true)
                    } finally {
                        bitmap.recycle()
                    }
                }
            }
            "scanFrame" -> {
                val format = (call.argument<String>("format") ?: "").lowercase()
                val width = call.argument<Int>("width") ?: 0
                val height = call.argument<Int>("height") ?: 0
                val topK = call.argument<Int>("topK") ?: 5
                val multi = (call.argument<String>("mode") ?: "fast").equals("multi", ignoreCase = true)
                val identify = call.argument<Boolean>("identify") ?: true
                runNative(detectExecutor, result, "scan_failed") {
                    val bitmap = decodeFrame(call, format, width, height)
                    try {
                        scanBitmap(bitmap, max(1, min(topK, 10)), multi, identify)
                    } finally {
                        recycleFrame(bitmap)
                    }
                }
            }
            "identifyFrame" -> {
                val format = (call.argument<String>("format") ?: "").lowercase()
                val width = call.argument<Int>("width") ?: 0
                val height = call.argument<Int>("height") ?: 0
                val topK = call.argument<Int>("topK") ?: 5
                val multi = (call.argument<String>("mode") ?: "fast").equals("multi", ignoreCase = true)
                val boxes = boxesFromArgs(call.argument("boxes"))
                runNative(identifyExecutor, result, "scan_failed") {
                    val bitmap = decodeFrame(call, format, width, height)
                    try {
                        identifyBitmap(bitmap, boxes, max(1, min(topK, 10)), multi)
                    } finally {
                        recycleFrame(bitmap)
                    }
                }
            }
            "openUrl" -> {
                val url = call.argument<String>("url") ?: ""
                val parsed = runCatching { Uri.parse(url) }.getOrNull()
                val scheme = parsed?.scheme?.lowercase()
                if (parsed == null || (scheme != "http" && scheme != "https")) {
                    result.success(mapOf("ok" to false, "handler" to ""))
                    return
                }
                try {
                    val intent = Intent(Intent.ACTION_VIEW, parsed)
                    intent.addCategory(Intent.CATEGORY_BROWSABLE)
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    appContext.startActivity(intent)
                    result.success(mapOf("ok" to true, "handler" to "https"))
                } catch (_: Exception) {
                    result.success(mapOf("ok" to false, "handler" to ""))
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun runNative(
        executor: java.util.concurrent.Executor,
        result: MethodChannel.Result,
        errorCode: String,
        block: () -> Any?,
    ) {
        executor.execute {
            try {
                val payload = block()
                mainHandler.post { result.success(payload) }
            } catch (error: Exception) {
                mainHandler.post { result.error(errorCode, error.message, null) }
            }
        }
    }

    private fun bootstrap(dir: String, gallery: String) {
        if (ready) return
        val started = SystemClock.elapsedRealtime()
        val root = File(dir)
        val yoloFile = File(root, "card_detector.tflite")
        yoloModelFile = yoloFile
        val miloFile = File(root, "milo.onnx")
        miloModelFile = miloFile
        cnnTfliteFile = File(root, "milo_cnn.tflite")
        cnnOnnxFile = File(root, "milo_cnn.onnx")
        miloCtxFile = MiloQnnGpu.ctxFile(root)
        accelFile = File(root, "accel.json")
        gpuOwner = loadAccel()?.owner ?: AndroidScanPipeline.GpuOwner.YOLO
        android.util.Log.i("pokoin.scan", AndroidScanPipeline.hardwareLine(appContext, gpuOwner))
        val env = OrtEnvironment.getEnvironment()
        ortEnv = env
        // Exclusive GPU: YOLO GpuDelegate XOR Milo QNN. EGL is thread-local
        // so YOLO always binds on the detect thread.
        detectExecutor.execute {
            try {
                pickYolo(yoloFile)
                saveAccel()
                android.util.Log.i("pokoin.scan", "yolo ready backend=$yoloBackend gpuOwner=$gpuOwner")
            } catch (error: Throwable) {
                android.util.Log.w("pokoin.scan", "yolo pick failed $error")
            }
        }
        val miloF = identifyExecutor.submit { pickMilo() }
        miloF.get()
        saveAccel()
        if (AndroidScanPipeline.miloMayUseGpu(gpuOwner) &&
            cnnTfliteFile?.isFile != true &&
            cnnOnnxFile?.isFile != true
        ) {
            miloGpuExecutor.execute {
                try {
                    tryMiloQnnGpu()
                } catch (error: Throwable) {
                    android.util.Log.w("pokoin.scan", "milo qnn-gpu worker failed $error")
                }
            }
        }
        val afterMilo = SystemClock.elapsedRealtime()
        synchronized(catalogLock) { loadCatalog(dir, gallery) }
        val afterCatalog = SystemClock.elapsedRealtime()
        warmupMs = 0
        android.util.Log.i(
            "pokoin.scan",
            "init backend=$miloBackend yolo=$yoloBackend gpuOwner=$gpuOwner warmupMs=$warmupMs predictMs=$miloPredictMs " +
                "miloN=${cards.size} gallery=$catalogGallery miloMs=${afterMilo - started} " +
                "catalogMs=${afterCatalog - afterMilo} yolo=background",
        )
        ready = true
    }

    private data class AccelState(
        val owner: AndroidScanPipeline.GpuOwner,
        val yolo: String,
        val milo: String,
    )

    private fun loadAccel(): AccelState? {
        val file = accelFile ?: return null
        if (!file.exists()) return null
        return try {
            val obj = JSONObject(file.readText())
            AccelState(
                owner = AndroidScanPipeline.parseGpuOwner(obj.optString("gpuOwner")),
                yolo = obj.optString("yolo"),
                milo = obj.optString("milo"),
            )
        } catch (_: Exception) {
            null
        }
    }

    private fun saveAccel() {
        val file = accelFile ?: return
        runCatching {
            file.writeText(
                JSONObject()
                    .put("gpuOwner", gpuOwner.name.lowercase())
                    .put("yolo", yoloBackend)
                    .put("milo", miloBackend)
                    .toString(),
            )
        }
    }

    private fun restartProcess() {
        android.util.Log.i("pokoin.scan", "restart process gpuOwner=$gpuOwner")
        val intent = appContext.packageManager.getLaunchIntentForPackage(appContext.packageName)
        if (intent != null) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
            appContext.startActivity(intent)
        }
        Process.killProcess(Process.myPid())
    }

    private fun closeYoloLocked() {
        runCatching { interpreter?.close() }
        runCatching { gpuDelegate?.close() }
        interpreter = null
        gpuDelegate = null
    }

    private fun bindCpuYolo(yoloFile: File) {
        val cpuOpts = Interpreter.Options().apply {
            setNumThreads(AndroidScanPipeline.yoloCpuThreads())
            setUseXNNPACK(true)
        }
        interpreter = Interpreter(yoloFile, cpuOpts)
        yoloBackend = "xnnpack"
    }

    private fun setYoloAccel(useGpu: Boolean) {
        val file = yoloModelFile ?: throw IllegalStateException("YOLO model missing")
        synchronized(yoloLock) {
            closeYoloLocked()
            if (useGpu && AndroidScanPipeline.yoloOwnsGpu(gpuOwner)) {
                val gpu = tryGpuYolo(file)
                if (gpu != null) {
                    interpreter = gpu.first
                    gpuDelegate = gpu.second
                    yoloBackend = "gpu"
                    runYoloDummyLocked()
                } else {
                    bindCpuYolo(file)
                }
            } else {
                bindCpuYolo(file)
            }
            saveAccel()
            android.util.Log.i("pokoin.scan", "yolo switch backend=$yoloBackend milo=$miloBackend")
        }
    }

    private fun tryGpuYolo(yoloFile: File): Pair<Interpreter, GpuDelegate>? {
        val created = SystemClock.elapsedRealtime()
        val compat = CompatibilityList()
        if (!compat.isDelegateSupportedOnThisDevice) {
            runCatching { compat.close() }
            return null
        }
        val gpuOptions = compat.bestOptionsForThisDevice
        runCatching {
            gpuOptions.setPrecisionLossAllowed(true)
            gpuOptions.setInferencePreference(
                GpuDelegate.Options.INFERENCE_PREFERENCE_FAST_SINGLE_ANSWER,
            )
        }
        val delegate = GpuDelegate(gpuOptions)
        runCatching { compat.close() }
        return try {
            val gpuOpts = Interpreter.Options().apply { addDelegate(delegate) }
            val interp = Interpreter(yoloFile, gpuOpts)
            android.util.Log.i(
                "pokoin.scan",
                "yolo gpu createMs=${SystemClock.elapsedRealtime() - created}",
            )
            interp to delegate
        } catch (error: Exception) {
            android.util.Log.w("pokoin.scan", "yolo gpu failed $error")
            runCatching { delegate.close() }
            null
        }
    }

    private fun runYoloDummyLocked() {
        val interp = interpreter ?: return
        val dummy = Bitmap.createBitmap(
            AndroidScanPipeline.YOLO_SIZE,
            AndroidScanPipeline.YOLO_SIZE,
            Bitmap.Config.ARGB_8888,
        )
        try {
            detectYolo(dummy, interp)
        } catch (error: Exception) {
            android.util.Log.w("pokoin.scan", "yolo dummy failed $error")
        } finally {
            dummy.recycle()
        }
    }

    private fun pickYolo(yoloFile: File) {
        val prev = loadAccel()?.yolo
        val wantGpu = AndroidScanPipeline.yoloOwnsGpu(gpuOwner)
        synchronized(yoloLock) {
            closeYoloLocked()
            if (wantGpu) {
                val gpu = tryGpuYolo(yoloFile)
                if (gpu != null) {
                    interpreter = gpu.first
                    gpuDelegate = gpu.second
                    yoloBackend = "gpu"
                    val skipDummy = prev == "gpu"
                    if (skipDummy) {
                        android.util.Log.i("pokoin.scan", "yolo gpu reuse skipDummy=1")
                    } else {
                        runYoloDummyLocked()
                    }
                    return
                }
            }
            bindCpuYolo(yoloFile)
            android.util.Log.i("pokoin.scan", "yolo cpu backend=$yoloBackend")
        }
    }

    private fun pickMilo() {
        val cnnTflite = cnnTfliteFile
        if (cnnTflite != null && cnnTflite.isFile) {
            pickCnnTflite(cnnTflite)
            return
        }
        val cnnOnnx = cnnOnnxFile
        if (cnnOnnx != null && cnnOnnx.isFile) {
            pickOrtMilo(cnnOnnx, "cnn-ort")
            return
        }
        val miloFile = miloModelFile ?: throw IllegalStateException("Milo model missing")
        pickOrtMilo(miloFile, "ort")
    }

    private fun pickCnnTflite(cnnFile: File) {
        synchronized(miloLock) {
            closeCnnLocked()
            closeMiloLocked()
            val wantGpu = AndroidScanPipeline.miloMayUseGpu(gpuOwner)
            if (wantGpu) {
                val gpu = tryGpuCnn(cnnFile)
                if (gpu != null) {
                    cnnInterpreter = gpu.first
                    cnnGpuDelegate = gpu.second
                    miloBackend = "cnn-gpu"
                    miloPredictMs = timeCnnDummy()
                    lastEmbeds = 0
                    android.util.Log.i(
                        "pokoin.scan",
                        "milo pick backend=$miloBackend predictMs=$miloPredictMs gpuOwner=$gpuOwner",
                    )
                    return
                }
            }
            val cpuOpts = Interpreter.Options().apply {
                setNumThreads(AndroidScanPipeline.miloCpuThreads())
                setUseXNNPACK(true)
            }
            val interp = Interpreter(cnnFile, cpuOpts)
            cnnInterpreter = interp
            miloBackend = "cnn-xnnpack"
            inspectCnnLayout(interp)
            miloPredictMs = timeCnnDummy()
            lastEmbeds = 0
            android.util.Log.i(
                "pokoin.scan",
                "milo pick backend=$miloBackend predictMs=$miloPredictMs gpuOwner=$gpuOwner",
            )
        }
    }

    private fun tryGpuCnn(cnnFile: File): Pair<Interpreter, GpuDelegate>? {
        val created = SystemClock.elapsedRealtime()
        val compat = CompatibilityList()
        if (!compat.isDelegateSupportedOnThisDevice) {
            runCatching { compat.close() }
            return null
        }
        val gpuOptions = compat.bestOptionsForThisDevice
        runCatching {
            gpuOptions.setPrecisionLossAllowed(true)
            gpuOptions.setInferencePreference(
                GpuDelegate.Options.INFERENCE_PREFERENCE_FAST_SINGLE_ANSWER,
            )
        }
        val delegate = GpuDelegate(gpuOptions)
        runCatching { compat.close() }
        return try {
            val gpuOpts = Interpreter.Options().apply { addDelegate(delegate) }
            val interp = Interpreter(cnnFile, gpuOpts)
            inspectCnnLayout(interp)
            android.util.Log.i(
                "pokoin.scan",
                "cnn gpu createMs=${SystemClock.elapsedRealtime() - created}",
            )
            interp to delegate
        } catch (error: Exception) {
            android.util.Log.w("pokoin.scan", "cnn gpu failed $error")
            runCatching { delegate.close() }
            null
        }
    }

    private fun inspectCnnLayout(interp: Interpreter) {
        val shape = interp.getInputTensor(0).shape()
        cnnNhwc = shape.size == 4 && shape[3] == 3
        android.util.Log.i(
            "pokoin.scan",
            "cnn input=${shape.contentToString()} nhwc=$cnnNhwc out=${interp.getOutputTensor(0).shape().contentToString()}",
        )
    }

    private fun timeCnnDummy(): Int {
        val dummy = Bitmap.createBitmap(miloSize, miloSize, Bitmap.Config.ARGB_8888)
        try {
            lastPredictMs = 0
            embedCnn(dummy)
            return lastPredictMs
        } finally {
            dummy.recycle()
        }
    }

    private fun pickOrtMilo(modelFile: File, name: String) {
        val env = ortEnv ?: throw IllegalStateException("ORT env missing")
        val cpuThreads = AndroidScanPipeline.miloCpuThreads()
        if (AndroidScanPipeline.hasHexagonHtp()) {
            android.util.Log.i(
                "pokoin.scan",
                "milo htp available; V2 identify uses CNN/ORT CPU on Pre-HTP (see ANDROID_PIPELINE_V2.md)",
            )
        }
        synchronized(miloLock) {
            closeCnnLocked()
            closeMiloLocked()
            val opts = OrtSession.SessionOptions()
            var session: OrtSession? = null
            try {
                opts.setIntraOpNumThreads(cpuThreads)
                opts.setInterOpNumThreads(AndroidScanPipeline.MILO_INTER_OP)
                session = env.createSession(modelFile.absolutePath, opts)
                val ready = session
                miloSession = ready
                miloSessionOpts = opts
                miloBackend = name
                val dummy = Bitmap.createBitmap(miloSize, miloSize, Bitmap.Config.ARGB_8888)
                try {
                    lastPredictMs = 0
                    embedMiloWith(ready, dummy)
                    miloPredictMs = lastPredictMs
                } finally {
                    dummy.recycle()
                }
                lastEmbeds = 0
                android.util.Log.i(
                    "pokoin.scan",
                    "milo pick backend=$miloBackend predictMs=$miloPredictMs cpuThreads=$cpuThreads gpuOwner=$gpuOwner",
                )
            } catch (error: Throwable) {
                android.util.Log.w("pokoin.scan", "milo $name failed $error")
                miloSession = null
                runCatching { session?.close() }
                runCatching { opts.close() }
                throw IllegalStateException("Milo $name failed", error)
            }
        }
    }

    private fun closeCnnLocked() {
        runCatching { cnnInterpreter?.close() }
        runCatching { cnnGpuDelegate?.close() }
        cnnInterpreter = null
        cnnGpuDelegate = null
    }

    private fun closeMiloLocked() {
        runCatching { miloSession?.close() }
        runCatching { miloSessionOpts?.close() }
        miloSession = null
        miloSessionOpts = null
    }

    private fun tryMiloQnnGpu() {
        if (cnnInterpreter != null) return
        if (!AndroidScanPipeline.miloMayUseGpu(gpuOwner)) return
        val dir = miloCtxFile?.parentFile ?: return
        if (MiloQnnGpu.pendingFile(dir).exists()) {
            android.util.Log.w("pokoin.scan", "milo qnn-gpu prep running — staying ORT CPU")
            return
        }
        if (yoloBackend == "gpu" || gpuDelegate != null) {
            android.util.Log.w("pokoin.scan", "milo qnn-gpu aborted — YOLO owns Adreno")
            return
        }
        if (!MiloQnnGpu.ctxReady(dir)) {
            android.util.Log.w(
                "pokoin.scan",
                "milo qnn-gpu no ctx — staying ORT CPU (toggle MILO to compile in :qnn_prep)",
            )
            return
        }
        val env = ortEnv ?: return
        val ctxFile = MiloQnnGpu.ctxFile(dir)
        android.util.Log.i(
            "pokoin.scan",
            "milo qnn-gpu load ctx bytes=${ctxFile.length()} yolo=$yoloBackend",
        )
        val opened = try {
            MiloQnnGpu.openSession(env, ctxFile, dumpCtx = null)
        } catch (error: Throwable) {
            val stop = MiloQnnGpu.stopReason(error)
            android.util.Log.w("pokoin.scan", "milo qnn-gpu load failed $stop $error")
            MiloQnnGpu.persistSkip(dir, "ctx:$stop")
            runCatching { ctxFile.delete() }
            return
        }
        val (session, opts) = opened
        val dummy = Bitmap.createBitmap(miloSize, miloSize, Bitmap.Config.ARGB_8888)
        try {
            val ms = synchronized(miloLock) {
                if (yoloBackend == "gpu" || gpuDelegate != null) {
                    android.util.Log.w("pokoin.scan", "milo qnn-gpu discard — YOLO took Adreno")
                    runCatching { session.close() }
                    runCatching { opts.close() }
                    return
                }
                lastPredictMs = 0
                embedMiloWith(session, dummy)
                val predict = lastPredictMs
                closeMiloLocked()
                miloSession = session
                miloSessionOpts = opts
                miloBackend = "qnn-gpu"
                miloPredictMs = predict
                lastEmbeds = 0
                predict
            }
            saveAccel()
            android.util.Log.i(
                "pokoin.scan",
                "milo pick backend=$miloBackend predictMs=$ms model=${ctxFile.name}",
            )
        } catch (error: Throwable) {
            val stop = MiloQnnGpu.stopReason(error)
            android.util.Log.w("pokoin.scan", "milo qnn-gpu dummy failed $stop $error")
            MiloQnnGpu.persistSkip(dir, "ctx:$stop")
            runCatching { session.close() }
            runCatching { opts.close() }
            runCatching { ctxFile.delete() }
        } finally {
            dummy.recycle()
        }
    }

    private fun loadCatalog(dir: String, gallery: String) {
        require(gallery in catalogNames) { "unknown gallery $gallery" }
        val started = SystemClock.elapsedRealtime()
        val root = File(dir, gallery)
        val embFile = File(root, "embeddings.bin")
        val metaFile = File(root, "metadata.jsonl")
        val embBytes = embFile.readBytes()
        val buf = ByteBuffer.wrap(embBytes).order(ByteOrder.LITTLE_ENDIAN).asFloatBuffer()
        val nFloats = buf.remaining()
        require(nFloats % dim == 0) { "embeddings.bin length $nFloats not divisible by $dim" }
        val copy = FloatArray(nFloats)
        buf.get(copy)
        val n = nFloats / dim
        val recs = ArrayList<Card>(n)
        metaFile.bufferedReader().useLines { lines ->
            lines.forEach { line ->
                if (line.isBlank()) return@forEach
                val obj = JSONObject(line)
                recs.add(
                    Card(
                        id = obj.optString("id"),
                        name = obj.optString("name"),
                        collectorNumber = obj.optString("n").ifEmpty { null },
                        set = obj.optString("set").ifEmpty { null },
                    ),
                )
            }
        }
        require(recs.size == n) { "metadata ${recs.size} vs embeddings $n" }
        embeddings = copy
        scoreBuf = FloatArray(n)
        cards = recs.toTypedArray()
        junkCard = BooleanArray(recs.size) { isJunkCard(recs[it]) }
        catalogGallery = gallery
        android.util.Log.i(
            "pokoin.scan",
            "catalog gallery=$gallery miloN=$n loadMs=${SystemClock.elapsedRealtime() - started} " +
                "bytes=${embFile.length()}",
        )
    }

    private fun scanBitmap(bitmap: Bitmap, topK: Int, multi: Boolean, identify: Boolean): Map<String, Any?> {
        val started = System.currentTimeMillis()
        val interp = interpreter
        if (interp == null) {
            return scanPayload(
                bitmap.width, bitmap.height,
                emptyList(), emptyList(), emptyList(), emptyList(),
                0, 0, 0, (System.currentTimeMillis() - started).toInt(), multi,
            )
        }
        val imgW = bitmap.width
        val imgH = bitmap.height
        val yoloStarted = System.currentTimeMillis()
        val yolo = synchronized(yoloLock) { detectYolo(bitmap, interp) }
        val yoloMs = (System.currentTimeMillis() - yoloStarted).toInt()
        val yoloHasCard = yolo.any { isPlausibleCard(it, bitmap.width, bitmap.height, multi) }
        val rects = if (identifyRunning || (!identify && yoloHasCard)) {
            emptyList()
        } else {
            detectPokeRects(bitmap)
        }
        val boxes = mergePokeBoxes(yolo, rects, bitmap.width, bitmap.height, multi)
        if (!identify) {
            return scanPayload(
                imgW, imgH, yolo, rects, boxes, emptyList(),
                yoloMs, 0, 0, (System.currentTimeMillis() - started).toInt(), multi,
            )
        }
        return identifyBitmap(bitmap, boxes, topK, multi, yolo, rects, yoloMs, started)
    }

    private fun identifyBitmap(
        bitmap: Bitmap,
        boxes: List<Box>,
        topK: Int,
        multi: Boolean,
        yolo: List<Box> = boxes,
        rects: List<Box> = emptyList(),
        yoloMs: Int = 0,
        started: Long = System.currentTimeMillis(),
    ): Map<String, Any?> {
        identifyRunning = true
        lastEmbeds = 0
        lastPreprocessMs = 0
        lastPredictMs = 0
        lastSearchMs = 0
        lastGemvMs = 0
        lastTopkMs = 0
        try {
        val selected = if (multi) boxes.take(maxMultiCards) else boxes.take(1)
        val hits = ArrayList<Map<String, Any?>>()
        var miloMsTotal = 0L
        var preprocessMsTotal = 0
        var predictMsTotal = 0
        var searchMsTotal = 0
        var gemvMsTotal = 0
        var topkMsTotal = 0
        selected.forEachIndexed { boxIndex, box ->
            if (!isPlausibleCard(box, bitmap.width, bitmap.height, multi)) return@forEachIndexed
            val cropBox = if (!multi && isPokeSize(box.x2 - box.x1, box.y2 - box.y1)) {
                snapToPokeSize(box, bitmap.width, bitmap.height)
            } else {
                box
            }
            val crop = cropBitmap(bitmap, cropBox)
            try {
                val t0 = System.currentTimeMillis()
                val neighbors = identifyMilo(crop, if (multi) 1 else topK, allAngles = !multi)
                miloMsTotal += System.currentTimeMillis() - t0
                preprocessMsTotal += lastPreprocessMs
                predictMsTotal += lastPredictMs
                searchMsTotal += lastSearchMs
                gemvMsTotal += lastGemvMs
                topkMsTotal += lastTopkMs
                neighbors.forEachIndexed { rank, neighbor ->
                    hits.add(
                        mapOf(
                            "rank" to if (multi) boxIndex + 1 else rank + 1,
                            "boxIndex" to boxIndex,
                            "score" to neighbor.second.toDouble(),
                            "id" to neighbor.first.id,
                            "name" to neighbor.first.name,
                            "collectorNumber" to neighbor.first.collectorNumber,
                            "set" to neighbor.first.set,
                            "yoloConf" to box.conf.toDouble(),
                            "quad" to listOf(
                                box.x1, box.y1, box.x2, box.y1,
                                box.x2, box.y2, box.x1, box.y2,
                            ),
                        ),
                    )
                }
            } finally {
                if (crop !== bitmap) crop.recycle()
            }
        }
        return scanPayload(
            bitmap.width,
            bitmap.height,
            yolo,
            rects,
            selected,
            hits,
            yoloMs,
            0,
            miloMsTotal.toInt(),
            (System.currentTimeMillis() - started).toInt(),
            multi,
            preprocessMsTotal,
            predictMsTotal,
            searchMsTotal,
            gemvMsTotal,
            topkMsTotal,
            lastEmbeds,
        )
        } finally {
            identifyRunning = false
        }
    }

    private fun scanPayload(
        imgW: Int,
        imgH: Int,
        yolo: List<Box>,
        rects: List<Box>,
        boxes: List<Box>,
        hits: List<Map<String, Any?>>,
        yoloMs: Int,
        visionMs: Int,
        miloMs: Int,
        totalMs: Int,
        multi: Boolean,
        preprocessMs: Int = 0,
        predictMs: Int = 0,
        searchMs: Int = 0,
        gemvMs: Int = 0,
        topkMs: Int = 0,
        embeds: Int = 0,
    ): Map<String, Any?> {
        val top = hits.firstOrNull()
        val box = boxes.firstOrNull()
        val boxW = if (box != null) (box.x2 - box.x1).toInt() else 0
        val boxH = if (box != null) (box.y2 - box.y1).toInt() else 0
        android.util.Log.i(
            "pokoin.scan",
            "img=${imgW}x$imgH yoloRaw=${yolo.size} yolo=${boxes.size} box=${boxW}x$boxH conf=${box?.conf} " +
                "yoloMs=$yoloMs visionMs=$visionMs miloMs=$miloMs preprocessMs=$preprocessMs " +
                "predictMs=$predictMs searchMs=$searchMs gemvMs=$gemvMs topkMs=$topkMs " +
                "embeds=$embeds totalMs=$totalMs backend=$miloBackend yoloBackend=$yoloBackend " +
                "top=${top?.get("name")} score=${top?.get("score")}",
        )
        return mapOf(
            "ok" to (top != null || boxes.isNotEmpty()),
            "mode" to if (multi) "multi" else "fast",
            "imgW" to imgW,
            "imgH" to imgH,
            "yoloRaw" to yolo.size,
            "visionBoxes" to rects.size,
            "yoloBoxes" to boxes.size,
            "yoloMs" to yoloMs,
            "visionMs" to visionMs,
            "miloMs" to miloMs,
            "preprocessMs" to preprocessMs,
            "predictMs" to predictMs,
            "searchMs" to searchMs,
            "gemvMs" to gemvMs,
            "topkMs" to topkMs,
            "embeds" to embeds,
            "totalMs" to totalMs,
            "miloN" to cards.size,
            "miloBackend" to miloBackend,
            "hits" to hits,
            "boxes" to boxes.map {
                mapOf(
                    "x1" to it.x1.toDouble(),
                    "y1" to it.y1.toDouble(),
                    "x2" to it.x2.toDouble(),
                    "y2" to it.y2.toDouble(),
                    "conf" to it.conf.toDouble(),
                    "quad" to listOf(it.x1, it.y1, it.x2, it.y1, it.x2, it.y2, it.x1, it.y2),
                    "rotated" to false,
                )
            },
            "name" to top?.get("name"),
            "id" to top?.get("id"),
            "score" to top?.get("score"),
        )
    }

    private val yoloSize = 640
    private val yoloConf = 0.25f
    private val yoloIou = 0.45f
    private val yoloMinArea = 0.005f
    private val maxMultiCards = 60
    // iPhone 3:4 preview used 0.25. Android Camera2 is 16:9; a hand-held
    // card is often 8–18% of that buffer, so 0.25 drops a real YOLO box.
    private val liveMinCardArea = 0.08f
    private val multiMinCardArea = 0.006f

    private fun detectYolo(src: Bitmap, interpreter: Interpreter): List<Box> {
        val (square, scale, padX, padY) = letterboxYolo(src)
        val input = bitmapToNhwc01(square)
        val inBuf = yoloInBuf?.takeIf { it.capacity() >= input.size * 4 }
            ?: ByteBuffer.allocateDirect(input.size * 4).order(ByteOrder.nativeOrder()).also { yoloInBuf = it }
        inBuf.clear()
        inBuf.asFloatBuffer().put(input)
        inBuf.rewind()
        val outTensor = interpreter.getOutputTensor(0)
        val outBuf = yoloOutBuf?.takeIf { it.capacity() >= outTensor.numBytes() }
            ?: ByteBuffer.allocateDirect(outTensor.numBytes()).order(ByteOrder.nativeOrder()).also { yoloOutBuf = it }
        outBuf.clear()
        interpreter.run(inBuf, outBuf)
        outBuf.rewind()
        val floats = FloatArray(outTensor.numElements())
        outBuf.asFloatBuffer().get(floats)
        val dims = outTensor.shape()
        val channels = if (dims.size >= 3) dims[dims.size - 2] else 5
        val anchors = if (dims.size >= 3) dims[dims.size - 1] else 8400
        if (floats.size < channels * anchors) return emptyList()
        return decodeYolo(floats, channels, anchors, src.width, src.height, scale, padX, padY)
    }

    private data class Letterbox(val square: Bitmap, val scale: Float, val padX: Int, val padY: Int)

    private fun letterboxYolo(src: Bitmap): Letterbox {
        val size = yoloSize
        if (src.width == size && src.height == size) {
            return Letterbox(src, 1f, 0, 0)
        }
        val scale = min(size.toFloat() / src.width, size.toFloat() / src.height)
        val nw = max(1, (src.width * scale).toInt())
        val nh = max(1, (src.height * scale).toInt())
        val padX = (size - nw) / 2
        val padY = (size - nh) / 2
        val square = yoloLetterbox?.takeIf { it.width == size && it.height == size && !it.isRecycled }
            ?: Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888).also {
                yoloLetterbox?.recycle()
                yoloLetterbox = it
            }
        square.eraseColor(0xFF727272.toInt())
        val matrix = Matrix().apply {
            setScale(scale, scale)
            postTranslate(padX.toFloat(), padY.toFloat())
        }
        Canvas(square).drawBitmap(src, matrix, yoloLetterPaint)
        return Letterbox(square, scale, padX, padY)
    }

    private fun decodeYolo(
        out: FloatArray,
        channels: Int,
        anchors: Int,
        origW: Int,
        origH: Int,
        scale: Float,
        padX: Int,
        padY: Int,
    ): List<Box> {
        val minArea = yoloMinArea * origW * origH
        val raw = ArrayList<Box>(64)
        val inv = if (scale > 1e-6f) 1f / scale else 1f
        for (j in 0 until anchors) {
            val conf = out[4 * anchors + j]
            if (conf < yoloConf) continue
            val cx = out[0 * anchors + j]
            val cy = out[1 * anchors + j]
            val bw = out[2 * anchors + j]
            val bh = out[3 * anchors + j]
            val x1 = max(0f, min(origW.toFloat(), (cx - bw / 2 - padX) * inv))
            val y1 = max(0f, min(origH.toFloat(), (cy - bh / 2 - padY) * inv))
            val x2 = max(0f, min(origW.toFloat(), (cx + bw / 2 - padX) * inv))
            val y2 = max(0f, min(origH.toFloat(), (cy + bh / 2 - padY) * inv))
            if ((x2 - x1) * (y2 - y1) < minArea) continue
            if (x2 - x1 < 24f || y2 - y1 < 24f) continue
            val aspect = (x2 - x1) / (y2 - y1)
            if (aspect < 0.25f || aspect > 4f) continue
            raw.add(Box(x1, y1, x2, y2, conf))
        }
        raw.sortByDescending { it.conf }
        val kept = ArrayList<Box>()
        for (b in raw) {
            if (kept.all { iou(b, it) <= yoloIou }) kept.add(b)
        }
        return kept
    }

    private fun iou(a: Box, b: Box): Float {
        val ix1 = max(a.x1, b.x1)
        val iy1 = max(a.y1, b.y1)
        val ix2 = min(a.x2, b.x2)
        val iy2 = min(a.y2, b.y2)
        val inter = max(0f, ix2 - ix1) * max(0f, iy2 - iy1)
        if (inter <= 0f) return 0f
        val aa = boxArea(a)
        val ba = boxArea(b)
        val denom = aa + ba - inter
        return if (denom <= 0f) 0f else inter / denom
    }

    private fun boxArea(b: Box): Float = max(0f, b.x2 - b.x1) * max(0f, b.y2 - b.y1)

    /** Artwork / title panel sitting inside a larger card. */
    private fun contained(inner: Box, outer: Box): Boolean {
        val innerA = boxArea(inner)
        val outerA = boxArea(outer)
        if (innerA < 8f || outerA <= innerA * 1.15f) return false
        val ix1 = max(inner.x1, outer.x1)
        val iy1 = max(inner.y1, outer.y1)
        val ix2 = min(inner.x2, outer.x2)
        val iy2 = min(inner.y2, outer.y2)
        val inter = max(0f, ix2 - ix1) * max(0f, iy2 - iy1)
        return inter / innerA >= 0.72f
    }

    private val pokeAspectMin = 0.58f
    private val pokeAspectMax = 0.88f

    private fun isPokeSize(width: Float, height: Float): Boolean {
        if (width < 24f || height < 24f) return false
        val aspect = width / height
        val portrait = aspect in pokeAspectMin..pokeAspectMax
        val landscape = aspect in (1f / pokeAspectMax)..(1f / pokeAspectMin)
        return portrait || landscape
    }

    private fun centerPokeBox(width: Int, height: Int): Box {
        val frame = width.toFloat() / max(height, 1)
        val target = 63f / 88f
        val bw: Float
        val bh: Float
        if (frame >= target) {
            bh = height.toFloat() * 0.92f
            bw = bh * target
        } else {
            bw = width.toFloat() * 0.92f
            bh = bw / target
        }
        val x1 = (width - bw) / 2f
        val y1 = (height - bh) / 2f
        return Box(x1, y1, x1 + bw, y1 + bh, 0.2f)
    }

    private fun snapToPokeSize(box: Box, width: Int, height: Int): Box {
        val maxW = width.toFloat()
        val maxH = height.toFloat()
        if (maxW < 8f || maxH < 8f) return box
        val w = max(1f, min(box.x2 - box.x1, maxW))
        val h = max(1f, min(box.y2 - box.y1, maxH))
        val landscape = w >= h
        val target = if (landscape) 88f / 63f else 63f / 88f
        var bw: Float
        var bh: Float
        if (w / h >= target) {
            bh = h
            bw = bh * target
        } else {
            bw = w
            bh = bw / target
        }
        if (bw > maxW) {
            bw = maxW
            bh = bw / target
        }
        if (bh > maxH) {
            bh = maxH
            bw = bh * target
        }
        var x1 = (box.x1 + box.x2) / 2f - bw / 2f
        var y1 = (box.y1 + box.y2) / 2f - bh / 2f
        x1 = max(0f, min(x1, maxW - bw))
        y1 = max(0f, min(y1, maxH - bh))
        return Box(x1, y1, x1 + bw, y1 + bh, box.conf)
    }

    private fun mergePokeBoxes(
        yolo: List<Box>,
        rects: List<Box>,
        width: Int,
        height: Int,
        multi: Boolean,
    ): List<Box> {
        val all = (rects + yolo)
            .filter { isPlausibleCard(it, width, height, multi) }
        val candidates = if (!multi) {
            all.sortedByDescending { boxArea(it) }
        } else {
            val cells = all.filter { host ->
                all.count { other ->
                    other !== host &&
                        contained(other, host) &&
                        boxArea(other) >= 0.12f * boxArea(host)
                } < 2
            }
            (if (cells.isNotEmpty()) cells else all).sortedBy { boxArea(it) }
        }
        val kept = ArrayList<Box>()
        for (b in candidates) {
            if (kept.any {
                    iou(b, it) > yoloIou ||
                        contained(b, it) ||
                        (multi && contained(it, b))
                }
            ) {
                continue
            }
            kept.add(b)
            if (!multi) break
            if (kept.size >= maxMultiCards) break
        }
        return kept
    }

    private fun isPlausibleCard(box: Box, width: Int, height: Int, multi: Boolean = false): Boolean {
        if (!isPokeSize(box.x2 - box.x1, box.y2 - box.y1)) return false
        val frame = (width * height).coerceAtLeast(1).toFloat()
        val area = boxArea(box)
        val minArea = if (multi) multiMinCardArea else liveMinCardArea
        if (area < minArea * frame) return false
        if (area > 0.72f * frame) return false
        val m = 18f
        if (box.x1 <= m && box.y1 <= m &&
            box.x2 >= width - m && box.y2 >= height - m
        ) {
            return false
        }
        return true
    }

    private fun isTiltedAabb(b: Box): Boolean {
        val w = b.x2 - b.x1
        val h = b.y2 - b.y1
        if (w < 24f || h < 24f) return false
        val a = w / h
        return a in 0.45f..2.22f
    }

    private fun completeness(b: Box, width: Int, height: Int): Float {
        val m = 4f
        var s = 1f
        if (b.x1 <= m) s *= 0.45f
        if (b.y1 <= m) s *= 0.45f
        if (b.x2 >= width - m) s *= 0.45f
        if (b.y2 >= height - m) s *= 0.45f
        return s
    }

    /** Edge blobs whose AABB is a 63:88 (or sideways) card rectangle. */
    private fun detectPokeRects(src: Bitmap): List<Box> {
        val longSide = max(src.width, src.height)
        val target = 360
        val scale = longSide.toFloat() / target
        val dw = max(16, (src.width / scale).toInt())
        val dh = max(16, (src.height / scale).toInt())
        val small = if (src.width == dw && src.height == dh) src else Bitmap.createScaledBitmap(src, dw, dh, true)
        val n = dw * dh
        val pixels = IntArray(n)
        small.getPixels(pixels, 0, dw, 0, 0, dw, dh)
        if (small !== src) small.recycle()
        val gray = IntArray(n)
        for (i in 0 until n) {
            val p = pixels[i]
            gray[i] = (30 * ((p shr 16) and 0xff) + 59 * ((p shr 8) and 0xff) + 11 * (p and 0xff)) / 100
        }
        val mag = IntArray(n)
        var sum = 0L
        for (y in 1 until dh - 1) {
            for (x in 1 until dw - 1) {
                val i = y * dw + x
                val gx = -gray[i - dw - 1] + gray[i - dw + 1] - 2 * gray[i - 1] + 2 * gray[i + 1] - gray[i + dw - 1] + gray[i + dw + 1]
                val gy = -gray[i - dw - 1] - 2 * gray[i - dw] - gray[i - dw + 1] + gray[i + dw - 1] + 2 * gray[i + dw] + gray[i + dw + 1]
                val m = kotlin.math.abs(gx) + kotlin.math.abs(gy)
                mag[i] = m
                sum += m
            }
        }
        val mean = (sum / max(1, (dw - 2) * (dh - 2))).toInt()
        val thresh = max(48, mean + mean / 2)
        val parent = IntArray(n) { it }
        fun find(a: Int): Int {
            var x = a
            while (parent[x] != x) {
                parent[x] = parent[parent[x]]
                x = parent[x]
            }
            return x
        }
        fun union(a: Int, b: Int) {
            val ra = find(a)
            val rb = find(b)
            if (ra != rb) parent[rb] = ra
        }
        for (y in 1 until dh - 1) {
            for (x in 1 until dw - 1) {
                val i = y * dw + x
                if (mag[i] < thresh) continue
                if (mag[i - 1] >= thresh) union(i, i - 1)
                if (mag[i - dw] >= thresh) union(i, i - dw)
            }
        }
        data class Acc(var minX: Int, var minY: Int, var maxX: Int, var maxY: Int, var count: Int)
        val acc = HashMap<Int, Acc>()
        for (y in 1 until dh - 1) {
            for (x in 1 until dw - 1) {
                val i = y * dw + x
                if (mag[i] < thresh) continue
                val r = find(i)
                val cur = acc[r]
                if (cur == null) acc[r] = Acc(x, y, x, y, 1)
                else {
                    if (x < cur.minX) cur.minX = x
                    if (y < cur.minY) cur.minY = y
                    if (x > cur.maxX) cur.maxX = x
                    if (y > cur.maxY) cur.maxY = y
                    cur.count++
                }
            }
        }
        val sx = src.width.toFloat() / dw
        val sy = src.height.toFloat() / dh
        val minCount = (0.01f * n).toInt()
        val out = ArrayList<Box>()
        for (c in acc.values) {
            if (c.count < minCount) continue
            val x1 = c.minX * sx
            val y1 = c.minY * sy
            val x2 = (c.maxX + 1) * sx
            val y2 = (c.maxY + 1) * sy
            if (!isPokeSize(x2 - x1, y2 - y1)) continue
            out.add(Box(x1, y1, x2, y2, 0.35f))
        }
        return out
    }

    private val miloSize = 448
    private val miloMean = floatArrayOf(0.485f, 0.456f, 0.406f)
    private val miloStd = floatArrayOf(0.229f, 0.224f, 0.225f)

    private fun identifyMilo(crop: Bitmap, topK: Int, allAngles: Boolean = false): List<Pair<Card, Float>> {
        val oriented = miloBitmaps(crop, allAngles)
        var best = emptyList<Pair<Card, Float>>()
        var bestScore = -1f
        var preprocessMsTotal = 0
        var predictMsTotal = 0
        var searchMsTotal = 0
        var gemvMsTotal = 0
        var topkMsTotal = 0
        try {
            for (bmp in oriented) {
                val neighbors = search(embedMilo(bmp), topK)
                preprocessMsTotal += lastPreprocessMs
                predictMsTotal += lastPredictMs
                searchMsTotal += lastSearchMs
                gemvMsTotal += lastGemvMs
                topkMsTotal += lastTopkMs
                val score = neighbors.firstOrNull()?.second ?: -1f
                if (score > bestScore) {
                    bestScore = score
                    best = neighbors
                }
                if (score >= miloEarlyExit) break
            }
        } finally {
            lastPreprocessMs = preprocessMsTotal
            lastPredictMs = predictMsTotal
            lastSearchMs = searchMsTotal
            lastGemvMs = gemvMsTotal
            lastTopkMs = topkMsTotal
            for (bmp in oriented) {
                if (bmp !== crop && !bmp.isRecycled) bmp.recycle()
            }
        }
        return best
    }

    private fun miloBitmaps(crop: Bitmap, allAngles: Boolean = false): List<Bitmap> {
        val r90 = rotateBitmap(crop, 90f)
        if (allAngles) {
            return listOf(crop, r90, rotateBitmap(crop, 180f), rotateBitmap(crop, 270f))
        }
        val aspect = crop.width.toFloat() / max(crop.height, 1)
        if (aspect in 0.85f..1.18f) {
            val r180 = rotateBitmap(crop, 180f)
            val r270 = rotateBitmap(crop, 270f)
            return listOf(crop, r90, r180, r270)
        }
        if (crop.width > crop.height) {
            val r270 = rotateBitmap(crop, 270f)
            return listOf(r90, r270)
        }
        val r180 = rotateBitmap(crop, 180f)
        return listOf(crop, r180)
    }

    private fun rotateBitmap(src: Bitmap, degrees: Float): Bitmap {
        val m = Matrix().apply { postRotate(degrees) }
        return Bitmap.createBitmap(src, 0, 0, src.width, src.height, m, true)
    }

    private fun embedMilo(bmp: Bitmap): FloatArray {
        synchronized(miloLock) {
            if (cnnInterpreter != null) return embedCnn(bmp)
            val session = miloSession ?: throw IllegalStateException("Scan engine is not initialized")
            return embedMiloWith(session, bmp)
        }
    }

    private fun embedCnn(bmp: Bitmap): FloatArray {
        val interp = cnnInterpreter ?: throw IllegalStateException("CNN identify is not initialized")
        val preStarted = System.nanoTime()
        val scaled = if (bmp.width == miloSize && bmp.height == miloSize) {
            bmp
        } else {
            Bitmap.createScaledBitmap(bmp, miloSize, miloSize, true)
        }
        try {
            val floats = if (cnnNhwc) bitmapToNhwcImageNet(scaled) else bitmapToNchwImageNet(scaled)
            val inBuf = miloDirect?.takeIf { it.capacity() >= floats.size * 4 }
                ?: ByteBuffer.allocateDirect(floats.size * 4).order(ByteOrder.nativeOrder()).also { miloDirect = it }
            inBuf.clear()
            inBuf.asFloatBuffer().put(floats)
            inBuf.rewind()
            lastPreprocessMs = ((System.nanoTime() - preStarted) / 1_000_000).toInt()
            val outTensor = interp.getOutputTensor(0)
            val outBuf = cnnOutBuf?.takeIf { it.capacity() >= outTensor.numBytes() }
                ?: ByteBuffer.allocateDirect(outTensor.numBytes()).order(ByteOrder.nativeOrder()).also { cnnOutBuf = it }
            outBuf.clear()
            val predStarted = System.nanoTime()
            interp.run(inBuf, outBuf)
            lastPredictMs = ((System.nanoTime() - predStarted) / 1_000_000).toInt()
            lastEmbeds += 1
            outBuf.rewind()
            val raw = FloatArray(dim)
            outBuf.asFloatBuffer().get(raw)
            return l2(raw)
        } finally {
            if (scaled !== bmp) scaled.recycle()
        }
    }

    private fun embedMiloWith(session: OrtSession, bmp: Bitmap): FloatArray {
        val env = ortEnv ?: throw IllegalStateException("Scan engine is not initialized")
        val preStarted = System.nanoTime()
        val scaled = if (bmp.width == miloSize && bmp.height == miloSize) {
            bmp
        } else {
            Bitmap.createScaledBitmap(bmp, miloSize, miloSize, true)
        }
        try {
            val nchw = bitmapToNchwImageNet(scaled)
            val direct = miloDirect?.takeIf { it.capacity() >= nchw.size * 4 }
                ?: ByteBuffer.allocateDirect(nchw.size * 4).order(ByteOrder.nativeOrder()).also { miloDirect = it }
            direct.clear()
            val fb = direct.asFloatBuffer()
            fb.put(nchw)
            fb.rewind()
            lastPreprocessMs = ((System.nanoTime() - preStarted) / 1_000_000).toInt()
            val inputName = session.inputNames.first()
            val predStarted = System.nanoTime()
            OnnxTensor.createTensor(env, fb, longArrayOf(1, 3, miloSize.toLong(), miloSize.toLong())).use { tensor ->
                session.run(mapOf(inputName to tensor)).use { outputs ->
                    lastPredictMs = ((System.nanoTime() - predStarted) / 1_000_000).toInt()
                    lastEmbeds += 1
                    val tensorOut = outputs[0] as OnnxTensor
                    val raw = FloatArray(dim)
                    tensorOut.floatBuffer.get(raw)
                    return l2(raw)
                }
            }
        } finally {
            if (scaled !== bmp) scaled.recycle()
        }
    }

    private fun search(query: FloatArray, topK: Int): List<Pair<Card, Float>> {
        synchronized(catalogLock) {
            val n = cards.size
            val scores = if (scoreBuf.size == n) scoreBuf else FloatArray(n).also { scoreBuf = it }
            val gemvStarted = System.nanoTime()
            gemv(query, scores, n)
            lastGemvMs = ((System.nanoTime() - gemvStarted) / 1_000_000).toInt()
            val topkStarted = System.nanoTime()
            val hits = topK(scores, topK)
            lastTopkMs = ((System.nanoTime() - topkStarted) / 1_000_000).toInt()
            lastSearchMs = lastGemvMs + lastTopkMs
            return hits
        }
    }

    private fun gemv(query: FloatArray, scores: FloatArray, n: Int) {
        val v = embeddings
        val d = dim
        val threads = min(AndroidScanPipeline.gemvThreads(), max(1, Runtime.getRuntime().availableProcessors()))
        if (n < 2048 || threads <= 1) {
            gemvRange(query, scores, v, d, 0, n)
            return
        }
        val chunk = (n + threads - 1) / threads
        val latch = CountDownLatch(threads)
        for (t in 0 until threads) {
            val start = t * chunk
            val end = min(n, start + chunk)
            if (start >= end) {
                latch.countDown()
                continue
            }
            gemvPool.execute {
                try {
                    gemvRange(query, scores, v, d, start, end)
                } finally {
                    latch.countDown()
                }
            }
        }
        if (!latch.await(2, TimeUnit.SECONDS)) {
            android.util.Log.w("pokoin.scan", "gemv timeout threads=$threads n=$n")
        }
    }

    private fun gemvRange(
        query: FloatArray,
        scores: FloatArray,
        v: FloatArray,
        d: Int,
        start: Int,
        end: Int,
    ) {
        for (i in start until end) {
            var s = 0f
            val base = i * d
            var j = 0
            while (j < d) {
                s += v[base + j] * query[j]
                j++
            }
            scores[i] = s
        }
    }

    private fun topK(scores: FloatArray, k: Int): List<Pair<Card, Float>> {
        val take = min(k, scores.size)
        if (take <= 0) return emptyList()
        val idx = IntArray(take) { -1 }
        val vals = FloatArray(take) { -2f }
        for (i in scores.indices) {
            if (i < junkCard.size && junkCard[i]) continue
            val s = scores[i]
            if (s <= vals[take - 1]) continue
            var pos = take - 1
            while (pos > 0 && s > vals[pos - 1]) {
                vals[pos] = vals[pos - 1]
                idx[pos] = idx[pos - 1]
                pos--
            }
            vals[pos] = s
            idx[pos] = i
        }
        val out = ArrayList<Pair<Card, Float>>(take)
        for (p in 0 until take) {
            if (idx[p] >= 0) out.add(cards[idx[p]] to vals[p])
        }
        return out
    }

    private fun isJunkCard(card: Card): Boolean {
        val n = card.name.lowercase()
        val needles = listOf(
            "blank filler", "filler card", "manhole tip",
            "booster box", "jumbo booster", "shoulder bag",
            "display frame", "storage box", "long card box",
            "deck box", "theme deck", "playmat", "pendant",
            "checklane blister", "stacking tin", "liberty bottle",
            "merchandise", "ultra pro", "sleeves", "divider",
            " empty box", "elite trainer", "promo booster",
            "figure set", "card holder", "translucent die",
        )
        if (needles.any { n.contains(it) }) return true
        return n.endsWith(" pin") || n.contains(" pin ")
    }

    private fun l2(v: FloatArray): FloatArray {
        var s = 0f
        for (x in v) s += x * x
        val n = max(sqrt(s), 1e-8f)
        return FloatArray(v.size) { v[it] / n }
    }

    private fun cropBitmap(src: Bitmap, box: Box): Bitmap {
        val ix1 = max(0, min(src.width - 1, box.x1.toInt()))
        val iy1 = max(0, min(src.height - 1, box.y1.toInt()))
        val ix2 = max(ix1 + 1, min(src.width, box.x2.toInt()))
        val iy2 = max(iy1 + 1, min(src.height, box.y2.toInt()))
        return Bitmap.createBitmap(src, ix1, iy1, ix2 - ix1, iy2 - iy1)
    }

    private fun bitmapToNhwc01(bmp: Bitmap): FloatArray {
        val w = bmp.width
        val h = bmp.height
        val pixels = yoloPixels?.takeIf { it.size == w * h } ?: IntArray(w * h).also { yoloPixels = it }
        bmp.getPixels(pixels, 0, w, 0, 0, w, h)
        val out = yoloNhwc?.takeIf { it.size == w * h * 3 } ?: FloatArray(w * h * 3).also { yoloNhwc = it }
        var dst = 0
        for (p in pixels) {
            out[dst++] = ((p shr 16) and 0xff) / 255f
            out[dst++] = ((p shr 8) and 0xff) / 255f
            out[dst++] = (p and 0xff) / 255f
        }
        return out
    }

    private fun bitmapToNhwcImageNet(bmp: Bitmap): FloatArray {
        val w = bmp.width
        val h = bmp.height
        val pixels = miloPixels?.takeIf { it.size == w * h } ?: IntArray(w * h).also { miloPixels = it }
        bmp.getPixels(pixels, 0, w, 0, 0, w, h)
        val out = miloNchw?.takeIf { it.size == w * h * 3 } ?: FloatArray(w * h * 3).also { miloNchw = it }
        var dst = 0
        for (p in pixels) {
            out[dst++] = (((p shr 16) and 0xff) / 255f - miloMean[0]) / miloStd[0]
            out[dst++] = (((p shr 8) and 0xff) / 255f - miloMean[1]) / miloStd[1]
            out[dst++] = ((p and 0xff) / 255f - miloMean[2]) / miloStd[2]
        }
        return out
    }

    private fun bitmapToNchwImageNet(bmp: Bitmap): FloatArray {
        val w = bmp.width
        val h = bmp.height
        val hw = w * h
        val pixels = miloPixels?.takeIf { it.size == hw } ?: IntArray(hw).also { miloPixels = it }
        bmp.getPixels(pixels, 0, w, 0, 0, w, h)
        val planar = miloNchw?.takeIf { it.size == 3 * hw } ?: FloatArray(3 * hw).also { miloNchw = it }
        for (i in pixels.indices) {
            val p = pixels[i]
            planar[0 * hw + i] = (((p shr 16) and 0xff) / 255f - miloMean[0]) / miloStd[0]
            planar[1 * hw + i] = (((p shr 8) and 0xff) / 255f - miloMean[1]) / miloStd[1]
            planar[2 * hw + i] = ((p and 0xff) / 255f - miloMean[2]) / miloStd[2]
        }
        return planar
    }

    private fun decodeJpeg(bytes: ByteArray): Bitmap {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        var sample = 1
        val maxSide = max(bounds.outWidth, bounds.outHeight)
        while (maxSide / sample > 1920) sample *= 2
        val opts = BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, opts)
            ?: throw IllegalArgumentException("Could not decode the photo")
    }

    private fun boxesFromArgs(raw: Any?): List<Box> {
        val list = raw as? List<*> ?: return emptyList()
        return list.mapNotNull { item ->
            val m = item as? Map<*, *> ?: return@mapNotNull null
            val x1 = (m["x1"] as? Number)?.toFloat() ?: return@mapNotNull null
            val y1 = (m["y1"] as? Number)?.toFloat() ?: return@mapNotNull null
            val x2 = (m["x2"] as? Number)?.toFloat() ?: return@mapNotNull null
            val y2 = (m["y2"] as? Number)?.toFloat() ?: return@mapNotNull null
            val conf = (m["conf"] as? Number)?.toFloat() ?: 0f
            Box(x1, y1, x2, y2, conf)
        }
    }

    private fun decodeFrame(call: MethodCall, format: String, width: Int, height: Int): Bitmap {
        require(width > 1 && height > 1) { "bad frame size $width x $height" }
        return when (format) {
            "bgra" -> {
                val bgra = call.argument<ByteArray>("bgra") ?: throw IllegalArgumentException("missing bgra")
                val stride = call.argument<Int>("bgraStride") ?: (width * 4)
                bgraToBitmap(bgra, width, height, stride)
            }
            "yuv420" -> {
                val y = call.argument<ByteArray>("y") ?: throw IllegalArgumentException("missing y")
                val u = call.argument<ByteArray>("u") ?: throw IllegalArgumentException("missing u")
                val v = call.argument<ByteArray>("v") ?: throw IllegalArgumentException("missing v")
                val yStride = call.argument<Int>("yStride") ?: width
                val uStride = call.argument<Int>("uStride") ?: width
                val vStride = call.argument<Int>("vStride") ?: width
                val uvPixel = max(1, call.argument<Int>("uvPixelStride") ?: 1)
                val rot = AndroidScanPipeline.yuvDisplayRotation(
                    call.argument<Int>("sensorOrientation") ?: 90,
                )
                yuv420ToBitmap(y, u, v, width, height, yStride, uStride, vStride, uvPixel, rot)
            }
            else -> throw IllegalArgumentException("unsupported frame format $format")
        }
    }

    private fun bgraToBitmap(bgra: ByteArray, width: Int, height: Int, stride: Int): Bitmap {
        val argb = IntArray(width * height)
        var o = 0
        for (row in 0 until height) {
            var i = row * stride
            for (col in 0 until width) {
                val b = bgra[i].toInt() and 0xff
                val g = bgra[i + 1].toInt() and 0xff
                val r = bgra[i + 2].toInt() and 0xff
                argb[o++] = (0xff shl 24) or (r shl 16) or (g shl 8) or b
                i += 4
            }
        }
        return Bitmap.createBitmap(argb, width, height, Bitmap.Config.ARGB_8888)
    }

    private fun recycleFrame(bitmap: Bitmap) {
        if (bitmap === detectBitmap || bitmap === identifyBitmap) return
        if (!bitmap.isRecycled) bitmap.recycle()
    }

    private fun yuvScratch(width: Int, height: Int): Pair<IntArray, Bitmap> {
        val detect = Thread.currentThread().name.contains("detect")
        val n = width * height
        if (detect) {
            val argb = detectArgb?.takeIf { it.size == n } ?: IntArray(n).also { detectArgb = it }
            val bmp = detectBitmap?.takeIf { it.width == width && it.height == height && !it.isRecycled }
                ?: Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).also {
                    detectBitmap?.recycle()
                    detectBitmap = it
                }
            return argb to bmp
        }
        val argb = identifyArgb?.takeIf { it.size == n } ?: IntArray(n).also { identifyArgb = it }
        val bmp = identifyBitmap?.takeIf { it.width == width && it.height == height && !it.isRecycled }
            ?: Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).also {
                identifyBitmap?.recycle()
                identifyBitmap = it
            }
        return argb to bmp
    }

    private fun yuv420ToBitmap(
        y: ByteArray,
        u: ByteArray,
        v: ByteArray,
        width: Int,
        height: Int,
        yStride: Int,
        uStride: Int,
        vStride: Int,
        uvPixel: Int,
        rotation: Int = 0,
    ): Bitmap {
        val rot = ((rotation % 360) + 360) % 360
        val outW = if (rot == 90 || rot == 270) height else width
        val outH = if (rot == 90 || rot == 270) width else height
        val (argb, bmp) = yuvScratch(outW, outH)
        for (row in 0 until height) {
            val yRow = row * yStride
            val uvRow = (row / 2) * uStride
            val vvRow = (row / 2) * vStride
            for (col in 0 until width) {
                val Y = (y[yRow + col].toInt() and 0xff)
                val U = (u[uvRow + (col / 2) * uvPixel].toInt() and 0xff) - 128
                val V = (v[vvRow + (col / 2) * uvPixel].toInt() and 0xff) - 128
                val y1192 = 1192 * max(0, Y - 16)
                var r = y1192 + 1634 * V
                var g = y1192 - 833 * V - 400 * U
                var b = y1192 + 2066 * U
                r = min(262143, max(0, r)) shr 10
                g = min(262143, max(0, g)) shr 10
                b = min(262143, max(0, b)) shr 10
                val pixel = (0xff shl 24) or (r shl 16) or (g shl 8) or b
                val dest = when (rot) {
                    90 -> col * outW + (height - 1 - row)
                    180 -> (height - 1 - row) * outW + (width - 1 - col)
                    270 -> (width - 1 - col) * outW + row
                    else -> row * outW + col
                }
                argb[dest] = pixel
            }
        }
        bmp.setPixels(argb, 0, outW, 0, 0, outW, outH)
        return bmp
    }
}
