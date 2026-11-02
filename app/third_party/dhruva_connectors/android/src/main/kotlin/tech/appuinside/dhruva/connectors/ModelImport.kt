package tech.appuinside.dhruva.connectors

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.atomic.AtomicBoolean

/** Error with a code Dart maps to a message: no_space | cancelled | unreadable | failed. */
class ImportError(val code: String, message: String) : Exception(message)

/**
 * Streams a SAF document (content URI) into app storage in 1 MiB chunks.
 *
 * Why this exists: the stock Android file_selector plugin reads the picked
 * file into one Java byte[] inside onActivityResult, which dies with
 * OutOfMemoryError on any realistic GGUF (the heap growth limit is ~200 MB).
 * Here the bytes only ever pass through one fixed buffer.
 */
object ModelImport {
    private const val CHUNK = 1 shl 20
    private const val PROGRESS_EVERY_MS = 100L

    /** Display name and size (0 when the provider doesn't say). */
    fun describe(context: Context, uri: Uri): Pair<String, Long> {
        var name = uri.lastPathSegment ?: "model.gguf"
        var size = 0L
        context.contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
            null,
            null,
            null,
        )?.use { c ->
            if (c.moveToFirst()) {
                c.getColumnIndex(OpenableColumns.DISPLAY_NAME).takeIf { it >= 0 }
                    ?.let { i -> c.getString(i)?.let { name = it } }
                c.getColumnIndex(OpenableColumns.SIZE).takeIf { it >= 0 && !c.isNull(it) }
                    ?.let { size = c.getLong(it) }
            }
        }
        return name to size
    }

    /** Best effort: keeps the read grant alive until [release], however long the user dawdles. */
    fun keepGrant(context: Context, uri: Uri) {
        try {
            context.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (_: Exception) {
            // Not every provider offers persistable grants; the activity-result grant still holds.
        }
    }

    fun release(context: Context, uri: Uri) {
        try {
            context.contentResolver.releasePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (_: Exception) {
        }
    }

    /**
     * Copies [uri] to [dest] (must sit inside this app's data dir). Calls
     * [onProgress] (copied, total) at most every 100 ms. On any failure or
     * cancel the partial [dest] is deleted. Returns bytes written.
     */
    fun copy(
        context: Context,
        uri: Uri,
        dest: File,
        cancelled: AtomicBoolean,
        onProgress: (Long, Long) -> Unit,
    ): Long {
        val root = context.dataDir.canonicalPath + File.separator
        val target = dest.canonicalFile
        if (!target.path.startsWith(root)) throw ImportError("failed", "Destination is outside app storage.")
        target.parentFile?.mkdirs()

        val total = describe(context, uri).second
        var copied = 0L
        try {
            val input = context.contentResolver.openInputStream(uri)
                ?: throw ImportError("unreadable", "Could not open that file.")
            input.use { src ->
                FileOutputStream(target).use { out ->
                    val buf = ByteArray(CHUNK)
                    var lastReport = 0L
                    while (true) {
                        if (cancelled.get()) throw ImportError("cancelled", "Import cancelled.")
                        val n = src.read(buf)
                        if (n < 0) break
                        out.write(buf, 0, n)
                        copied += n
                        val now = System.currentTimeMillis()
                        if (now - lastReport >= PROGRESS_EVERY_MS) {
                            lastReport = now
                            onProgress(copied, if (total > 0) total else copied)
                        }
                    }
                    out.fd.sync()
                }
            }
            onProgress(copied, if (total > 0) total else copied)
            return copied
        } catch (e: ImportError) {
            target.delete()
            throw e
        } catch (e: SecurityException) {
            target.delete()
            throw ImportError("unreadable", "Access to that file was revoked.")
        } catch (e: IOException) {
            target.delete()
            // ENOSPC surfaces as an IOException whose message names it.
            val full = e.message?.contains("ENOSPC") == true || e.message?.contains("No space left") == true
            throw if (full) ImportError("no_space", "Not enough free space.")
            else ImportError("failed", e.message ?: "Could not copy the file.")
        }
    }
}
