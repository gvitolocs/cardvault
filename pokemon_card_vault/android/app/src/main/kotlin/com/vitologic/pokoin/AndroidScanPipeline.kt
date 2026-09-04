package com.vitologic.pokoin

import android.app.ActivityManager
import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Build
import android.os.Process
import kotlin.math.max
import kotlin.math.min

/**
 * Android Fast pipeline V2. Canonical: notes/ANDROID_PIPELINE_V2.md
 *
 * One OpenCL client per process. Default: YOLO GpuDelegate, identify CNN XNNPACK.
 * V2.2 identify is MobileNetV2 128-d (`milo_cnn.tflite`). gpuOwner=milo puts
 * that CNN on GpuDelegate and YOLO on XNNPACK. MobileViT QNN GPU is not used.
 */
object AndroidScanPipeline {
    const val YOLO_SIZE = 640
    const val MILO_SIZE = 448
    const val MILO_DIM = 128
    const val MILO_INTER_OP = 1
    const val YOLO_GPU_KEEP_MS = 150

    enum class SocClass {
        PRE_HTP,
        HTP,
        UNKNOWN,
    }

    enum class GpuOwner {
        YOLO,
        MILO,
    }

    fun cpuCount(): Int = max(1, Runtime.getRuntime().availableProcessors())

    /**
     * ORT intra-op / GEMV workers. Desktop 12 threads were slower than 4.
     * On an 8-core 865 leave 2 cores for Camera2 + Adreno OpenCL; use 6.
     */
    fun miloCpuThreads(): Int {
        val n = cpuCount()
        return max(4, min(6, n - 2))
    }

    fun gemvThreads(): Int = miloCpuThreads()

    fun yoloCpuThreads(): Int = miloCpuThreads()

    fun socKeys(): String {
        return listOf(
            Build.SOC_MODEL,
            Build.BOARD,
            Build.HARDWARE,
            Build.DEVICE,
        ).joinToString(" ").lowercase()
    }

    /**
     * HTP (QNN backend_type=htp) exists from Snapdragon 888 / SM8350
     * (Hexagon v68 fused). 865 is Hexagon v66 + HTA, not HTP.
     */
    fun socClass(): SocClass {
        val keys = socKeys()
        val htpSoc = listOf(
            "sm8350", "sm8450", "sm8475", "sm8550", "sm8635", "sm8650",
            "sm8750", "sm8850", "sm7325", "sm7450", "sm7675",
        )
        if (htpSoc.any { keys.contains(it) }) return SocClass.HTP
        val preHtp = listOf(
            "sm8250", "sm8150", "sm7250", "sm7225", "sm7125", "sm7150",
            "sm6350", "sm6125", "sm6150", "kona", "msmnile", "lito", "atoll",
        )
        if (preHtp.any { keys.contains(it) }) return SocClass.PRE_HTP
        return SocClass.UNKNOWN
    }

    fun hasHexagonHtp(): Boolean = socClass() == SocClass.HTP

    fun parseGpuOwner(raw: String?): GpuOwner {
        return if (raw.equals("milo", ignoreCase = true)) GpuOwner.MILO else GpuOwner.YOLO
    }

    fun yoloOwnsGpu(owner: GpuOwner): Boolean = owner == GpuOwner.YOLO

    fun miloMayUseGpu(owner: GpuOwner): Boolean = owner == GpuOwner.MILO

    fun keepYoloGpu(gpuMs: Int): Boolean = gpuMs in 1 until YOLO_GPU_KEEP_MS

    fun boostCurrentThread() {
        runCatching {
            Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_DISPLAY)
        }
    }

    /** Camera2 YUV is sensor-landscape. Rotate this many degrees CW to match CameraPreview. */
    fun yuvDisplayRotation(sensorOrientation: Int): Int {
        val deg = ((sensorOrientation % 360) + 360) % 360
        return when (deg) {
            90, 180, 270 -> deg
            else -> 0
        }
    }

    fun policyLine(owner: GpuOwner = GpuOwner.YOLO): String {
        return "gpuOwner=${owner.name.lowercase()} " +
            "yoloGpu=${yoloOwnsGpu(owner)} miloGpu=${miloMayUseGpu(owner)} " +
            "socClass=${socClass()} htp=${hasHexagonHtp()}"
    }

    fun hardwareLine(
        context: Context? = null,
        owner: GpuOwner = GpuOwner.YOLO,
    ): String {
        val rt = Runtime.getRuntime()
        val cores = cpuCount()
        val maxMb = rt.maxMemory() / (1024 * 1024)
        val mem = if (context != null) {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            " memClass=${am?.memoryClass} largeMem=${am?.largeMemoryClass}"
        } else {
            ""
        }
        val soc = if (Build.VERSION.SDK_INT >= 31) Build.SOC_MODEL else ""
        return "soc=$soc board=${Build.BOARD} device=${Build.DEVICE} " +
            "sdk=${Build.VERSION.SDK_INT} ${policyLine(owner)} " +
            "cores=$cores maxMb=$maxMb miloIntra=${miloCpuThreads()} " +
            "gemv=${gemvThreads()}$mem"
    }

    /**
     * 1x wide back camera. Samsung logical camera `0` includes the telephoto
     * (S20 FE: physical 52 / 7.12 mm) and the HAL will switch to it — that is
     * the "zoom camera". Prefer a wide group that does not list a tele id.
     */
    fun pickDefaultBackCamera(context: Context): Map<String, Any> {
        data class Cam(val id: String, val focal: Float, val physicalIds: List<String>)

        val mgr = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val idList = mgr.cameraIdList.toList()
        android.util.Log.i("pokoin.scan", "camera ids=${idList.joinToString(",")}")
        val back = ArrayList<Cam>()
        for (id in idList) {
            val chars = runCatching { mgr.getCameraCharacteristics(id) }.getOrNull() ?: continue
            val facing = chars.get(CameraCharacteristics.LENS_FACING) ?: continue
            if (facing != CameraCharacteristics.LENS_FACING_BACK) continue
            val focal = chars.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)
                ?.firstOrNull() ?: 0f
            val physicalIds = if (Build.VERSION.SDK_INT >= 28) {
                chars.physicalCameraIds.toList()
            } else {
                emptyList()
            }
            back += Cam(id, focal, physicalIds)
        }
        val summary = back.joinToString(" ") { "${it.id}:${it.focal}" }
        if (back.isEmpty()) {
            return mapOf("id" to "0", "reason" to "none", "cameras" to summary)
        }
        val minF = back.minOf { it.focal }
        val maxF = back.maxOf { it.focal }
        val spread = if (minF > 0f) maxF / minF else 1f
        fun result(cam: Cam, reason: String) = mapOf(
            "id" to cam.id,
            "focal" to cam.focal,
            "reason" to reason,
            "cameras" to summary,
            "physical" to cam.physicalIds.joinToString(","),
        )
        if (spread < 1.35f) {
            val cam = back.firstOrNull { it.id == "0" } ?: back.first()
            return result(cam, "single_fov")
        }
        fun isUw(focal: Float) = focal > 0f && focal <= 2.8f
        fun isTele(focal: Float) = focal >= 6.5f
        val teleIds = back.filter { isTele(it.focal) }.map { it.id }.toSet()
        val normal = back.filter { !isTele(it.focal) && !isUw(it.focal) }
        val noTeleSwitch = normal.filter { cam -> cam.physicalIds.none { it in teleIds } }
        // Camera 0 on Samsung is the all-lens logical (includes 3x). Skip it when a
        // narrower wide group exists so the HAL cannot jump to telephoto.
        val withoutAllLens = if (teleIds.isNotEmpty()) {
            noTeleSwitch.filter { it.id != "0" }
        } else {
            noTeleSwitch
        }
        val noTeleKnown = withoutAllLens.filter { it.physicalIds.isNotEmpty() }
        val picked = noTeleKnown.minByOrNull { it.id.toIntOrNull() ?: Int.MAX_VALUE }
            ?: withoutAllLens.minByOrNull { it.id.toIntOrNull() ?: Int.MAX_VALUE }
            ?: noTeleSwitch.minByOrNull { it.id.toIntOrNull() ?: Int.MAX_VALUE }
            ?: normal.firstOrNull { it.id == "0" }
            ?: back.firstOrNull { it.id == "0" }
            ?: normal.minByOrNull { it.id.toIntOrNull() ?: Int.MAX_VALUE }
            ?: back.first()
        val payload = result(picked, "wide_no_tele")
        android.util.Log.i(
            "pokoin.scan",
            "camera pick id=${picked.id} focal=${picked.focal} physical=${picked.physicalIds} " +
                "tele=$teleIds cameras=$summary",
        )
        return payload
    }
}
