package dev.resong.resong

import android.content.ContentValues
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// AudioServiceActivity liga o FlutterEngine do audio_service ao motor do app
class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "resong/downloads")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveToMusicMediaStore" -> {
                        val tempPath = call.argument<String>("tempPath")
                        val fileName = call.argument<String>("fileName")
                        val mimeType = call.argument<String>("mimeType") ?: "audio/mp4"
                        if (tempPath.isNullOrEmpty() || fileName.isNullOrEmpty()) {
                            result.error("INVALID_ARGS", "tempPath e fileName são obrigatórios", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val saved = saveToMusicMediaStore(File(tempPath), fileName, mimeType)
                            result.success(saved)
                        } catch (e: Exception) {
                            result.error("MEDIA_STORE_ERROR", e.message, null)
                        }
                    }

                    "exists" -> {
                        val uriOrPath = call.argument<String>("uriOrPath") ?: ""
                        result.success(checkExists(uriOrPath))
                    }

                    "delete" -> {
                        val uriOrPath = call.argument<String>("uriOrPath") ?: ""
                        result.success(deleteEntry(uriOrPath))
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun saveToMusicMediaStore(srcFile: File, fileName: String, mimeType: String): Map<String, Any> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = applicationContext.contentResolver
            val relPath = "${Environment.DIRECTORY_MUSIC}/resong"
            val values = ContentValues().apply {
                put(MediaStore.Audio.Media.DISPLAY_NAME, fileName)
                put(MediaStore.Audio.Media.MIME_TYPE, mimeType)
                put(MediaStore.Audio.Media.RELATIVE_PATH, relPath)
                put(MediaStore.Audio.Media.IS_MUSIC, 1)
                put(MediaStore.Audio.Media.IS_PENDING, 1)
            }
            val collection = MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            val uri = resolver.insert(collection, values)
                ?: throw IllegalStateException("Falha ao registrar arquivo no MediaStore")
            try {
                resolver.openOutputStream(uri)?.use { out ->
                    srcFile.inputStream().use { input -> input.copyTo(out) }
                } ?: throw IllegalStateException("Falha ao abrir OutputStream do MediaStore")
                values.clear()
                values.put(MediaStore.Audio.Media.IS_PENDING, 0)
                resolver.update(uri, values, null, null)
            } catch (e: Exception) {
                resolver.delete(uri, null, null)
                throw e
            }
            return mapOf(
                "uriOrPath" to uri.toString(),
                "displayPath" to "$relPath/$fileName",
                "size" to srcFile.length(),
            )
        }

        val musicDir = File(
            applicationContext.getExternalFilesDir(Environment.DIRECTORY_MUSIC) ?: filesDir,
            "resong",
        )
        if (!musicDir.exists()) musicDir.mkdirs()
        var dest = File(musicDir, fileName)
        if (dest.exists()) {
            val dot = fileName.lastIndexOf('.')
            val stem = if (dot > 0) fileName.substring(0, dot) else fileName
            val ext = if (dot > 0) fileName.substring(dot) else ""
            var n = 2
            while (dest.exists()) {
                dest = File(musicDir, "$stem ($n)$ext")
                n++
            }
        }
        srcFile.copyTo(dest, overwrite = false)
        return mapOf(
            "uriOrPath" to dest.absolutePath,
            "displayPath" to dest.absolutePath,
            "size" to dest.length(),
        )
    }

    private fun checkExists(uriOrPath: String): Boolean {
        if (uriOrPath.isEmpty()) return false
        if (uriOrPath.startsWith("content://")) {
            return try {
                applicationContext.contentResolver
                    .openAssetFileDescriptor(Uri.parse(uriOrPath), "r")
                    ?.use { true } ?: false
            } catch (_: Exception) {
                false
            }
        }
        return File(uriOrPath).exists()
    }

    private fun deleteEntry(uriOrPath: String): Boolean {
        if (uriOrPath.isEmpty()) return false
        if (uriOrPath.startsWith("content://")) {
            return try {
                applicationContext.contentResolver.delete(Uri.parse(uriOrPath), null, null) > 0
            } catch (_: Exception) {
                false
            }
        }
        return File(uriOrPath).delete()
    }
}
