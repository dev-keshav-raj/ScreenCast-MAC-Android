package com.example.screenmirror

import android.media.MediaCodec
import android.media.MediaFormat
import android.os.Handler
import android.os.Looper
import android.view.Surface
import io.flutter.plugin.common.MethodChannel
import java.io.EOFException
import java.io.InputStream
import java.net.ServerSocket
import java.net.Socket
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicBoolean

object UsbReceiver {
    private var serverSocket: ServerSocket? = null
    private var clientSocket: Socket? = null
    private var workerThread: Thread? = null
    private val isRunning = AtomicBoolean(false)
    
    var activeSurfaceView: MirrorSurfaceView? = null
    var methodChannel: MethodChannel? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    var activeSurface: Surface? = null
        set(value) {
            field = value
            if (value != null && clientSocket != null && mediaCodec == null) {
                initDecoder(value)
            } else if (value == null) {
                releaseDecoder()
            }
        }

    // Hardware MediaCodec members
    private var mediaCodec: MediaCodec? = null
    private var decoderOutputThread: Thread? = null

    fun startListening(mode: String, callback: (String) -> Unit) {
        if (isRunning.get()) {
            stopListening()
        }

        isRunning.set(true)
        workerThread = Thread {
            try {
                if (mode == "adbReverse") {
                    notifyStatus("listening")
                    logNative("Connecting to localhost:8080 (ADB Reverse Mode)...")
                    var socket: Socket? = null
                    while (isRunning.get() && socket == null) {
                        try {
                            socket = Socket("127.0.0.1", 8080)
                        } catch (e: Exception) {
                            Thread.sleep(1000)
                        }
                    }
                    if (socket != null && isRunning.get()) {
                        logNative("Connected to Mac server.")
                        handleConnection(socket)
                    }
                } else {
                    notifyStatus("listening")
                    logNative("Starting ServerSocket on port 8080 (ADB Forward Mode)...")
                    serverSocket = ServerSocket(8080)
                    while (isRunning.get()) {
                        try {
                            val socket = serverSocket?.accept() ?: break
                            logNative("Accepted client connection from ${socket.remoteSocketAddress}")
                            handleConnection(socket)
                        } catch (e: Exception) {
                            if (isRunning.get()) {
                                logNative("ServerSocket accept error: ${e.message}", "ERROR")
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                logNative("Worker thread exception: ${e.message}", "ERROR")
                notifyStatus("error", e.message)
            } finally {
                notifyStatus("disconnected")
            }
        }.apply { start() }
    }

    fun stopListening() {
        isRunning.set(false)
        
        // Shut down TCP sockets
        try {
            serverSocket?.close()
        } catch (e: Exception) {}
        serverSocket = null

        try {
            clientSocket?.close()
        } catch (e: Exception) {}
        clientSocket = null

        workerThread?.interrupt()
        workerThread = null

        // Shut down MediaCodec decoder
        releaseDecoder()

        mainHandler.post {
            activeSurfaceView?.drawDefaultScreen()
        }
        notifyStatus("disconnected")
    }

    private fun initDecoder(surface: Surface) {
        synchronized(this) {
            if (mediaCodec != null) return
            try {
                logNative("Initializing hardware H.264 MediaCodec decoder...")
                val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, 1920, 1080)
                
                // Set low-latency option if supported
                if (android.os.Build.VERSION.SDK_INT >= 30) {
                    format.setInteger(MediaFormat.KEY_LOW_LATENCY, 1)
                }
                
                val codec = MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
                codec.configure(format, surface, null, 0)
                codec.start()
                
                mediaCodec = codec
                
                // Start dedicated output thread to release buffers
                decoderOutputThread = Thread {
                    val info = MediaCodec.BufferInfo()
                    while (isRunning.get() && mediaCodec == codec) {
                        try {
                            val index = codec.dequeueOutputBuffer(info, 10000) // 10ms timeout
                            if (index >= 0) {
                                // true = render decoded frame onto the Surface immediately!
                                codec.releaseOutputBuffer(index, true)
                            } else if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                                logNative("Decoder format changed: ${codec.outputFormat}")
                            }
                        } catch (e: Exception) {
                            // Suppress exception on shutdown
                        }
                    }
                }.apply { start() }
                
                logNative("MediaCodec decoder started successfully.")
            } catch (e: Exception) {
                logNative("Failed to start MediaCodec: ${e.message}", "ERROR")
            }
        }
    }

    private fun releaseDecoder() {
        synchronized(this) {
            decoderOutputThread?.interrupt()
            decoderOutputThread = null
            
            try {
                mediaCodec?.stop()
                mediaCodec?.release()
            } catch (e: Exception) {}
            mediaCodec = null
            logNative("MediaCodec decoder released.")
        }
    }

    private fun feedDecoder(data: ByteArray, isConfig: Boolean) {
        val codec = mediaCodec ?: return
        try {
            val index = codec.dequeueInputBuffer(10000) // 10ms timeout
            if (index >= 0) {
                val buffer = codec.getInputBuffer(index) ?: return
                buffer.clear()
                buffer.put(data)
                
                val flags = if (isConfig) MediaCodec.BUFFER_FLAG_CODEC_CONFIG else 0
                codec.queueInputBuffer(index, 0, data.size, System.nanoTime() / 1000, flags)
            }
        } catch (e: Exception) {
            // Log occasionally to avoid spam
        }
    }

    private fun handleConnection(socket: Socket) {
        clientSocket = socket
        notifyStatus("streaming")
        
        // Initialize MediaCodec decoder if surface is available
        val surface = activeSurface
        if (surface != null) {
            initDecoder(surface)
        } else {
            logNative("Warning: No active Surface to bind MediaCodec output to", "WARNING")
        }

        val inputStream = socket.getInputStream()
        val headerBuffer = ByteArray(20)

        var frameCount = 0
        var totalBytes = 0L
        var accumulatedLatency = 0L
        var lastStatsTime = System.currentTimeMillis()

        try {
            while (isRunning.get()) {
                // 1. Read 20-byte header
                try {
                    readFully(inputStream, headerBuffer, 0, 20)
                } catch (e: EOFException) {
                    logNative("Socket closed by remote host.")
                    break
                }

                val frameLength = getInt(headerBuffer, 0)
                val frameNumber = getInt(headerBuffer, 4)
                val timestamp = getLong(headerBuffer, 8)
                val flags = getInt(headerBuffer, 16)

                // 2. Read body if payload is present
                val body = if (frameLength > 0) {
                    val bodyBuffer = ByteArray(frameLength)
                    readFully(inputStream, bodyBuffer, 0, frameLength)
                    bodyBuffer
                } else {
                    ByteArray(0)
                }

                totalBytes += 20 + frameLength

                // 3. Process video/config frames
                if (flags == 0x01) {
                    // Heartbeat packet
                } else if (flags == 0x02) {
                    // Raw/Dummy Frame (Legacy Phase 1 fallback)
                    val currentMillis = System.currentTimeMillis()
                    val latency = currentMillis - timestamp
                    accumulatedLatency += latency
                    frameCount++
                    
                    mainHandler.post {
                        activeSurfaceView?.drawDummyFrame(frameNumber, latency)
                    }
                } else if (flags == 0x04) {
                    // SPS / PPS Codec Configuration
                    feedDecoder(body, isConfig = true)
                } else if (flags == 0x08 || flags == 0x10) {
                    // Video H.264 I-Frame or P-Frame
                    feedDecoder(body, isConfig = false)
                    
                    val currentMillis = System.currentTimeMillis()
                    val latency = currentMillis - timestamp
                    accumulatedLatency += latency
                    frameCount++
                }

                // 4. Update UI stats once per second
                val now = System.currentTimeMillis()
                if (now - lastStatsTime >= 1000) {
                    val elapsed = now - lastStatsTime
                    val fps = (frameCount * 1000.0 / elapsed).toInt()
                    val bandwidth = totalBytes * 1000.0 / elapsed
                    val avgLatency = if (frameCount > 0) (accumulatedLatency / frameCount) else 0L

                    mainHandler.post {
                        methodChannel?.invokeMethod("onStatsUpdated", mapOf(
                            "fps" to fps,
                            "bandwidth" to bandwidth,
                            "latencyMs" to avgLatency
                        ))
                    }

                    frameCount = 0
                    totalBytes = 0
                    accumulatedLatency = 0
                    lastStatsTime = now
                }
            }
        } catch (e: Exception) {
            if (isRunning.get()) {
                logNative("Stream read error: ${e.message}", "ERROR")
            }
        } finally {
            try {
                socket.close()
            } catch (e: Exception) {}
            releaseDecoder()
            logNative("Connection handler closed.")
        }
    }

    private fun readFully(inputStream: InputStream, buffer: ByteArray, offset: Int, length: Int) {
        var bytesRead = 0
        while (bytesRead < length) {
            val count = inputStream.read(buffer, offset + bytesRead, length - bytesRead)
            if (count < 0) {
                throw EOFException("Stream closed unexpectedly")
            }
            bytesRead += count
        }
    }

    private fun getInt(buffer: ByteArray, offset: Int): Int {
        return ((buffer[offset].toInt() and 0xFF) shl 24) or
               ((buffer[offset + 1].toInt() and 0xFF) shl 16) or
               ((buffer[offset + 2].toInt() and 0xFF) shl 8) or
               (buffer[offset + 3].toInt() and 0xFF)
    }

    private fun getLong(buffer: ByteArray, offset: Int): Long {
        return ((buffer[offset].toLong() and 0xFF) shl 56) or
               ((buffer[offset + 1].toLong() and 0xFF) shl 48) or
               ((buffer[offset + 2].toLong() and 0xFF) shl 40) or
               ((buffer[offset + 3].toLong() and 0xFF) shl 32) or
               ((buffer[offset + 4].toLong() and 0xFF) shl 24) or
               ((buffer[offset + 5].toLong() and 0xFF) shl 16) or
               ((buffer[offset + 6].toLong() and 0xFF) shl 8) or
               (buffer[offset + 7].toLong() and 0xFF)
    }

    private fun logNative(message: String, level: String = "INFO") {
        mainHandler.post {
            methodChannel?.invokeMethod("onLog", mapOf("message" to message, "level" to level))
        }
    }

    private fun notifyStatus(status: String, error: String? = null) {
        mainHandler.post {
            methodChannel?.invokeMethod("onStatusChanged", mapOf("status" to status, "error" to error))
        }
    }
}
