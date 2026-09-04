package com.vitologic.pokoin

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.Process
import android.os.SystemClock
import android.util.Log
import java.io.File

/**
 * Separate process `:qnn_prep`. No Flutter, no camera, no catalog.
 * Compiles Milo QNN GPU OpenCL here, writes `milo_qnn_gpu_ctx.onnx`,
 * then relaunches the scan UI which only **loads** that binary.
 */
class MiloQnnPrepService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startAsForeground()
        val dir = MiloQnnGpu.scanDir(this, intent?.getStringExtra(MiloQnnGpu.DIR_EXTRA))
        Thread({ compileAndRelaunch(dir) }, "pokoin.scan.qnn-prep").start()
        return START_REDELIVER_INTENT
    }

    private fun startAsForeground() {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            nm.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Milo GPU compile",
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setContentTitle("Pokoin Scan")
            .setContentText("Compiling Milo GPU (Adreno). App reopens when ready.")
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(
                NOTIFY_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFY_ID, notification)
        }
    }

    private fun compileAndRelaunch(dir: File) {
        dir.mkdirs()
        val pending = MiloQnnGpu.pendingFile(dir)
        val attempts = runCatching { pending.readText().trim().toInt() }.getOrDefault(0)
        if (attempts >= 2) {
            Log.w(MiloQnnGpu.TAG, "milo qnn-gpu prep gave up after $attempts attempts")
            MiloQnnGpu.persistSkip(dir, "hung")
            finish(dir, "hung")
            return
        }
        pending.writeText("${attempts + 1}\n")
        Log.i(
            MiloQnnGpu.TAG,
            "milo qnn-gpu prep pid=${Process.myPid()} attempt=${attempts + 1} dir=${dir.absolutePath}",
        )
        SystemClock.sleep(2000)
        System.gc()

        copyAssetIfMissing(dir, "milo_fp16.onnx", "flutter_assets/assets/models/milo_fp16.onnx")
        copyAssetIfMissing(dir, "milo.onnx", "flutter_assets/assets/models/milo.onnx")

        if (MiloQnnGpu.ctxReady(dir)) {
            Log.i(MiloQnnGpu.TAG, "milo qnn-gpu prep ctx already ready")
            finish(dir, "ok")
            return
        }

        val ctx = MiloQnnGpu.ctxFile(dir)
        var ok = false
        for (model in MiloQnnGpu.modelCandidates(dir)) {
            if (MiloQnnGpu.compileContext(dir, model, ctx)) {
                ok = true
                break
            }
        }
        finish(dir, if (ok) "ok" else "fail")
    }

    private fun finish(dir: File, status: String) {
        MiloQnnGpu.statusFile(dir).writeText("$status\n")
        runCatching { MiloQnnGpu.pendingFile(dir).delete() }
        Log.i(
            MiloQnnGpu.TAG,
            "milo qnn-gpu prep done status=$status ctx=${MiloQnnGpu.ctxFile(dir).length()}",
        )
        val launch = Intent(this, LaunchActivity::class.java)
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        startActivity(launch)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun copyAssetIfMissing(dir: File, name: String, asset: String) {
        val dest = File(dir, name)
        if (dest.isFile && dest.length() > 1024) return
        try {
            assets.open(asset).use { input ->
                dest.outputStream().use { input.copyTo(it) }
            }
            Log.i(MiloQnnGpu.TAG, "milo qnn-gpu prep copied $name bytes=${dest.length()}")
        } catch (error: Throwable) {
            Log.w(MiloQnnGpu.TAG, "milo qnn-gpu prep missing $name $error")
        }
    }

    companion object {
        private const val CHANNEL_ID = "pokoin.qnn_prep"
        private const val NOTIFY_ID = 57

        fun start(context: Context, scanDir: String) {
            val intent = Intent(context, MiloQnnPrepService::class.java)
            intent.putExtra(MiloQnnGpu.DIR_EXTRA, scanDir)
            if (Build.VERSION.SDK_INT >= 26) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            Log.i(MiloQnnGpu.TAG, "milo qnn-gpu prep start dir=$scanDir")
        }
    }
}
