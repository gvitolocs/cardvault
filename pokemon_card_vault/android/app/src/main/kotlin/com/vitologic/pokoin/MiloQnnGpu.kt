package com.vitologic.pokoin

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtLoggingLevel
import ai.onnxruntime.OrtSession
import android.content.Context
import android.os.SystemClock
import android.util.Log
import java.io.File

/**
 * QNN GPU for Milo: compile OpenCL **out of the Flutter process**, then the
 * scan process only **loads** `milo_qnn_gpu_ctx.onnx`.
 *
 * On-device JIT next to the camera OOMs Adreno (`cl::Program (-6)`, finalize
 * 6022). Qualcomm's GPU backend is supposed to dump a context binary so the
 * next session skips `clBuildProgram`. AOC/qnn-context-binary-generator is
 * partner-only; this phone dumps it in `:qnn_prep` instead.
 */
object MiloQnnGpu {
    const val TAG = "pokoin.scan"
    const val CTX_NAME = "milo_qnn_gpu_ctx.onnx"
    const val PENDING_NAME = "milo_qnn_gpu.pending"
    const val SKIP_NAME = "milo_qnn_gpu.skip"
    const val STATUS_NAME = "milo_qnn_gpu.prep"
    const val DIR_EXTRA = "scan_dir"
    private const val MIN_CTX_BYTES = 1024L

    fun scanDir(context: Context, extra: String?): File {
        if (!extra.isNullOrBlank()) return File(extra)
        return File(context.filesDir, "fast_scan")
    }

    fun ctxFile(dir: File) = File(dir, CTX_NAME)
    fun pendingFile(dir: File) = File(dir, PENDING_NAME)
    fun skipFile(dir: File) = File(dir, SKIP_NAME)
    fun statusFile(dir: File) = File(dir, STATUS_NAME)

    fun ctxReady(dir: File): Boolean {
        val ctx = ctxFile(dir)
        return ctx.isFile && ctx.length() > MIN_CTX_BYTES
    }

    fun shouldDeferUi(context: Context): Boolean {
        val dir = scanDir(context, null)
        return pendingFile(dir).exists() && !ctxReady(dir)
    }

    fun providerOptions(): Map<String, String> {
        return mapOf(
            "backend_type" to "gpu",
            "qnn_context_priority" to "high",
        )
    }

    fun applyOpts(opts: OrtSession.SessionOptions, ctxOut: File?, dump: Boolean) {
        opts.setSessionLogLevel(OrtLoggingLevel.ORT_LOGGING_LEVEL_INFO)
        opts.setOptimizationLevel(OrtSession.SessionOptions.OptLevel.BASIC_OPT)
        opts.addConfigEntry("session.disable_cpu_ep_fallback", "1")
        if (dump && ctxOut != null) {
            opts.addConfigEntry("ep.context_enable", "1")
            opts.addConfigEntry("ep.context_embed_mode", "1")
            opts.addConfigEntry("ep.context_file_path", ctxOut.absolutePath)
        }
        opts.addQnn(providerOptions())
    }

    fun loadNative() {
        runCatching { System.loadLibrary("QnnSystem") }
        runCatching { System.loadLibrary("QnnGpu") }
    }

    fun modelCandidates(dir: File): List<File> {
        val skip = readSkip(dir)
        if (skip.contains("hung")) return emptyList()
        return listOf("milo_fp16.onnx", "milo.onnx")
            .map { File(dir, it) }
            .filter { file ->
                file.isFile && file.length() > MIN_CTX_BYTES && !skip.contains(file.name)
            }
    }

    fun readSkip(dir: File): Set<String> {
        val file = skipFile(dir)
        if (!file.exists()) return emptySet()
        return runCatching {
            file.readLines().map { it.trim() }.filter { it.isNotEmpty() }.toSet()
        }.getOrDefault(emptySet())
    }

    fun persistSkip(dir: File, reason: String) {
        val file = skipFile(dir)
        runCatching {
            val lines = readSkip(dir).toMutableSet()
            lines += reason
            file.writeText(lines.joinToString("\n") + "\n")
        }
        Log.w(TAG, "milo qnn-gpu skip persist reason=$reason")
    }

    fun clearSkip(dir: File) {
        runCatching { skipFile(dir).delete() }
        runCatching { pendingFile(dir).delete() }
    }

    fun stopReason(error: Throwable): String {
        val msg = ((error.message ?: "") + " " + error.toString()).lowercase()
        return when {
            msg.contains("1002") || msg.contains("createqnninputoutputtensors") -> "1002"
            msg.contains("6022") || msg.contains("finalize") -> "finalize"
            msg.contains("gsl mem") || msg.contains("out of memory") ||
                msg.contains("cl_out_of_host_memory") || msg.contains("oom") -> "oom"
            else -> "fail"
        }
    }

    /**
     * JIT-compile [model] to [ctxOut] in **this** process. Caller must be
     * `:qnn_prep`, not the Flutter UI process.
     */
    fun compileContext(dir: File, model: File, ctxOut: File): Boolean {
        loadNative()
        if (ctxOut.exists()) runCatching { ctxOut.delete() }
        val env = OrtEnvironment.getEnvironment()
        val opts = OrtSession.SessionOptions()
        var session: OrtSession? = null
        return try {
            applyOpts(opts, ctxOut, dump = true)
            val started = SystemClock.elapsedRealtime()
            Log.i(
                TAG,
                "milo qnn-gpu compile start model=${model.name} bytes=${model.length()} " +
                    "ctx=${ctxOut.absolutePath}",
            )
            session = env.createSession(model.absolutePath, opts)
            dummyRun(env, session)
            val ms = SystemClock.elapsedRealtime() - started
            val ok = ctxOut.length() > MIN_CTX_BYTES
            Log.i(
                TAG,
                "milo qnn-gpu compile done ok=$ok createMs=$ms ctxBytes=${ctxOut.length()}",
            )
            if (!ok) persistSkip(dir, "${model.name}:nodump")
            ok
        } catch (error: Throwable) {
            val dumped = ctxOut.length() > MIN_CTX_BYTES
            if (dumped) {
                Log.w(TAG, "milo qnn-gpu compile dumped ctx then dummy failed $error")
                return true
            }
            val stop = stopReason(error)
            Log.w(TAG, "milo qnn-gpu compile failed model=${model.name} $stop $error")
            persistSkip(dir, "${model.name}:$stop")
            persistSkip(dir, model.name)
            if (ctxOut.exists()) runCatching { ctxOut.delete() }
            false
        } finally {
            runCatching { session?.close() }
            runCatching { opts.close() }
        }
    }

    fun openSession(env: OrtEnvironment, path: File, dumpCtx: File?): Pair<OrtSession, OrtSession.SessionOptions> {
        loadNative()
        val opts = OrtSession.SessionOptions()
        try {
            applyOpts(opts, dumpCtx, dump = dumpCtx != null)
            val started = SystemClock.elapsedRealtime()
            val session = env.createSession(path.absolutePath, opts)
            Log.i(
                TAG,
                "milo qnn-gpu session path=${path.name} dump=${dumpCtx != null} " +
                    "createMs=${SystemClock.elapsedRealtime() - started}",
            )
            return session to opts
        } catch (error: Throwable) {
            runCatching { opts.close() }
            throw error
        }
    }

    fun dummyRun(env: OrtEnvironment, session: OrtSession): Int {
        val size = AndroidScanPipeline.MILO_SIZE
        val n = 1 * 3 * size * size
        val direct = java.nio.ByteBuffer
            .allocateDirect(n * 4)
            .order(java.nio.ByteOrder.nativeOrder())
        val buf = direct.asFloatBuffer()
        val inputName = session.inputNames.first()
        val started = SystemClock.elapsedRealtime()
        OnnxTensor.createTensor(
            env,
            buf,
            longArrayOf(1, 3, size.toLong(), size.toLong()),
        ).use { tensor ->
            session.run(mapOf(inputName to tensor)).use { }
        }
        return (SystemClock.elapsedRealtime() - started).toInt()
    }
}
