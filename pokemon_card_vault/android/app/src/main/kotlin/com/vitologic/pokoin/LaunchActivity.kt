package com.vitologic.pokoin

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.widget.Toast

/**
 * LAUNCHER trampoline. While `:qnn_prep` is compiling, do not start Flutter
 * (that was the 400 MB + camera that made QNN JIT OOM).
 */
class LaunchActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (MiloQnnGpu.shouldDeferUi(this)) {
            Toast.makeText(
                this,
                "Compiling Milo GPU… keep the notification up.",
                Toast.LENGTH_LONG,
            ).show()
            finish()
            return
        }
        startActivity(Intent(this, MainActivity::class.java))
        finish()
    }
}
