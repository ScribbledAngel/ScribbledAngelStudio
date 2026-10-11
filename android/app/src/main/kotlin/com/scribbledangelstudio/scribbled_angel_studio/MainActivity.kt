package com.scribbledangelstudio.scribbled_angel_studio

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/// Extracts a video's audio track for a given time range into a standalone
/// .m4a file, by copying compressed samples directly (MediaExtractor into
/// MediaMuxer) rather than decoding/re-encoding. No FFmpeg involved - this
/// is standard, documented Android media API usage. Used by the
/// rotoscoping video-reference import flow, since no FFmpeg-free Flutter
/// package currently does this.
class MainActivity : FlutterActivity() {
    private val channelName = "com.scribbledangelstudio.scribbled_angel_studio/audio_extractor"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            if (call.method == "extractAudio") {
                val sourcePath = call.argument<String>("sourcePath")
                val outputPath = call.argument<String>("outputPath")
                val startMs = call.argument<Int>("startMs")
                val endMs = call.argument<Int>("endMs")
                if (sourcePath == null || outputPath == null || startMs == null || endMs == null) {
                    result.error("BAD_ARGS", "sourcePath, outputPath, startMs and endMs are all required", null)
                    return@setMethodCallHandler
                }
                try {
                    val extracted = extractAudio(sourcePath, outputPath, startMs.toLong(), endMs.toLong())
                    result.success(extracted)
                } catch (e: Exception) {
                    // Most commonly: no audio track, or an audio codec that
                    // MediaMuxer's MP4 container doesn't support remuxing.
                    // Treat as "no audio available" rather than a hard
                    // failure of the whole video import.
                    result.success(false)
                }
            } else if (call.method == "extractWaveformPeaks") {
                val sourcePath = call.argument<String>("sourcePath")
                val startMs = call.argument<Int>("startMs")
                val endMs = call.argument<Int>("endMs")
                val sampleCount = call.argument<Int>("sampleCount")
                if (sourcePath == null || startMs == null || endMs == null || sampleCount == null) {
                    result.error("BAD_ARGS", "sourcePath, startMs, endMs and sampleCount are all required", null)
                    return@setMethodCallHandler
                }
                try {
                    val peaks = extractWaveformPeaks(sourcePath, startMs.toLong(), endMs.toLong(), sampleCount)
                    result.success(peaks)
                } catch (e: Exception) {
                    // No audio track, or a codec we can't decode - report an
                    // empty waveform rather than failing the whole screen.
                    result.success(null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    /** Returns true if an audio track was found and copied into [outputPath]. */
    private fun extractAudio(sourcePath: String, outputPath: String, startMs: Long, endMs: Long): Boolean {
        val extractor = MediaExtractor()
        extractor.setDataSource(sourcePath)

        var audioTrackIndex = -1
        var audioFormat: MediaFormat? = null
        for (i in 0 until extractor.trackCount) {
            val format = extractor.getTrackFormat(i)
            val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
            if (mime.startsWith("audio/")) {
                audioTrackIndex = i
                audioFormat = format
                break
            }
        }

        if (audioTrackIndex == -1 || audioFormat == null) {
            extractor.release()
            return false
        }

        extractor.selectTrack(audioTrackIndex)
        val startUs = startMs * 1000
        val endUs = endMs * 1000
        extractor.seekTo(startUs, MediaExtractor.SEEK_TO_CLOSEST_SYNC)

        val muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        val muxerTrackIndex = muxer.addTrack(audioFormat)
        muxer.start()

        val buffer = ByteBuffer.allocate(1 shl 20) // 1MB - generous for a single audio sample
        val bufferInfo = MediaCodec.BufferInfo()
        var wroteAnySamples = false
        var lastWrittenTimeUs = -1L

        while (true) {
            val sampleTimeUs = extractor.sampleTime
            if (sampleTimeUs < 0 || sampleTimeUs > endUs) break

            buffer.clear()
            val sampleSize = extractor.readSampleData(buffer, 0)
            if (sampleSize < 0) break

            // A "closest sync" seek can land slightly before startUs, and
            // MediaMuxer requires non-decreasing timestamps per track.
            var presentationTimeUs = sampleTimeUs - startUs
            if (presentationTimeUs < 0) presentationTimeUs = 0
            if (presentationTimeUs <= lastWrittenTimeUs) presentationTimeUs = lastWrittenTimeUs + 1

            bufferInfo.offset = 0
            bufferInfo.size = sampleSize
            bufferInfo.presentationTimeUs = presentationTimeUs
            bufferInfo.flags = extractor.sampleFlags

            muxer.writeSampleData(muxerTrackIndex, buffer, bufferInfo)
            lastWrittenTimeUs = presentationTimeUs
            wroteAnySamples = true
            extractor.advance()
        }

        muxer.stop()
        muxer.release()
        extractor.release()

        return wroteAnySamples
    }

    /**
     * Decodes the audio track between [startMs] and [endMs] and returns
     * [sampleCount] peak amplitudes (0.0-1.0, loudest moment in range = 1.0)
     * for drawing a waveform. Returns null if there's no audio track.
     */
    private fun extractWaveformPeaks(sourcePath: String, startMs: Long, endMs: Long, sampleCount: Int): List<Double>? {
        val extractor = MediaExtractor()
        extractor.setDataSource(sourcePath)

        var audioTrackIndex = -1
        var audioFormat: MediaFormat? = null
        for (i in 0 until extractor.trackCount) {
            val format = extractor.getTrackFormat(i)
            val mime = format.getString(MediaFormat.KEY_MIME) ?: continue
            if (mime.startsWith("audio/")) {
                audioTrackIndex = i
                audioFormat = format
                break
            }
        }
        if (audioTrackIndex == -1 || audioFormat == null) {
            extractor.release()
            return null
        }

        val mime = audioFormat.getString(MediaFormat.KEY_MIME)!!
        extractor.selectTrack(audioTrackIndex)
        val startUs = startMs * 1000
        val endUs = endMs * 1000
        extractor.seekTo(startUs, MediaExtractor.SEEK_TO_CLOSEST_SYNC)

        val decoder = MediaCodec.createDecoderByType(mime)
        decoder.configure(audioFormat, null, null, 0)
        decoder.start()

        val peaks = DoubleArray(sampleCount)
        val rangeUs = max(1L, endUs - startUs)
        var sawInputEos = false
        var sawOutputEos = false

        while (!sawOutputEos) {
            if (!sawInputEos) {
                val inputBufferId = decoder.dequeueInputBuffer(10_000)
                if (inputBufferId >= 0) {
                    val inputBuffer = decoder.getInputBuffer(inputBufferId)!!
                    val sampleTimeUs = extractor.sampleTime
                    if (sampleTimeUs < 0 || sampleTimeUs > endUs) {
                        decoder.queueInputBuffer(inputBufferId, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        sawInputEos = true
                    } else {
                        val sampleSize = extractor.readSampleData(inputBuffer, 0)
                        if (sampleSize < 0) {
                            decoder.queueInputBuffer(inputBufferId, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            sawInputEos = true
                        } else {
                            decoder.queueInputBuffer(inputBufferId, 0, sampleSize, sampleTimeUs, 0)
                            extractor.advance()
                        }
                    }
                }
            }

            val bufferInfo = MediaCodec.BufferInfo()
            val outputBufferId = decoder.dequeueOutputBuffer(bufferInfo, 10_000)
            if (outputBufferId >= 0) {
                if (bufferInfo.size > 0 && bufferInfo.presentationTimeUs >= startUs) {
                    val outputBuffer = decoder.getOutputBuffer(outputBufferId)!!
                    outputBuffer.order(ByteOrder.LITTLE_ENDIAN)
                    outputBuffer.position(bufferInfo.offset)
                    outputBuffer.limit(bufferInfo.offset + bufferInfo.size)

                    var maxAbsInBuffer = 0
                    while (outputBuffer.remaining() >= 2) {
                        val sample = outputBuffer.short.toInt()
                        maxAbsInBuffer = max(maxAbsInBuffer, abs(sample))
                    }

                    val relativeUs = bufferInfo.presentationTimeUs - startUs
                    val bucket = min(sampleCount - 1, max(0, ((relativeUs * sampleCount) / rangeUs).toInt()))
                    peaks[bucket] = max(peaks[bucket], maxAbsInBuffer / 32768.0)
                }
                decoder.releaseOutputBuffer(outputBufferId, false)
                if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) sawOutputEos = true
            }
        }

        decoder.stop()
        decoder.release()
        extractor.release()

        val loudest = peaks.maxOrNull() ?: 0.0
        if (loudest > 0.0) {
            for (i in peaks.indices) peaks[i] = peaks[i] / loudest
        }
        return peaks.toList()
    }
}
