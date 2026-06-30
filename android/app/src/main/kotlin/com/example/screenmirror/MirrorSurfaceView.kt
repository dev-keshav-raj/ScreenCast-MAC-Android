package com.example.screenmirror

import android.content.Context
import android.graphics.Color
import android.graphics.Paint
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import io.flutter.plugin.platform.PlatformView

class MirrorSurfaceView(context: Context) : PlatformView, SurfaceHolder.Callback {

    private val surfaceView = SurfaceView(context)
    private var isSurfaceCreated = false
    private val paint = Paint().apply {
        color = Color.WHITE
        textSize = 48f
        isAntiAlias = true
    }

    init {
        surfaceView.holder.addCallback(this)
        UsbReceiver.activeSurfaceView = this
    }

    override fun getView(): View {
        return surfaceView
    }

    override fun dispose() {
        if (UsbReceiver.activeSurfaceView == this) {
            UsbReceiver.activeSurfaceView = null
        }
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        isSurfaceCreated = true
        UsbReceiver.activeSurface = holder.surface
        drawDefaultScreen()
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {}

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        isSurfaceCreated = false
        UsbReceiver.activeSurface = null
    }

    fun drawDefaultScreen() {
        if (!isSurfaceCreated) return
        val canvas = surfaceView.holder.lockCanvas() ?: return
        canvas.drawColor(Color.parseColor("#0F0F12"))
        paint.color = Color.parseColor("#00ADB5")
        canvas.drawText("Waiting for mirror stream...", 100f, 300f, paint)
        surfaceView.holder.unlockCanvasAndPost(canvas)
    }

    fun drawDummyFrame(frameNumber: Int, latencyMs: Long) {
        if (!isSurfaceCreated) return
        val canvas = surfaceView.holder.lockCanvas() ?: return
        
        val r = (frameNumber * 3) % 256
        val g = (frameNumber * 7) % 256
        val b = (frameNumber * 11) % 256
        canvas.drawColor(Color.rgb(r, g, b))
        
        paint.color = Color.BLACK
        canvas.drawRect(50f, 50f, 800f, 350f, paint)
        
        paint.color = Color.parseColor("#00ADB5")
        canvas.drawText("MacMirror Receiver (Active)", 80f, 120f, paint)
        
        paint.color = Color.WHITE
        canvas.drawText("Frame: $frameNumber", 80f, 180f, paint)
        canvas.drawText("Latency: $latencyMs ms", 80f, 240f, paint)
        canvas.drawText("FPS Target: 60 FPS", 80f, 300f, paint)
        
        surfaceView.holder.unlockCanvasAndPost(canvas)
    }
}
