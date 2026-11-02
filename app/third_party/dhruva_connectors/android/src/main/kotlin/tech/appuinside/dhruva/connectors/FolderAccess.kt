package tech.appuinside.dhruva.connectors

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import java.io.File
import java.io.FileOutputStream

/** A refusal the plugin turns into a PlatformException (code + user-safe message). */
internal class FolderError(val code: String, message: String) : Exception(message)

/**
 * Storage Access Framework access to ONE folder the user picked
 * (ACTION_OPEN_DOCUMENT_TREE, read-only persistable grant). No raw file paths,
 * no MANAGE_EXTERNAL_STORAGE: every read goes through ContentResolver on a
 * document inside the granted tree.
 *
 * Safety:
 *  - listing starts at the tree root and only follows child documents the
 *    provider returns for directories under it (depth, directory and file
 *    counts are capped);
 *  - fetching re-verifies that the requested document id is the root or a
 *    child of it (`isChildDocument`) and contains no `..` segment, so an id
 *    crafted outside the tree is refused;
 *  - the copy destination must resolve inside this app's cache directory;
 *  - reads stop at maxBytes (the file is deleted if it is longer).
 *
 * Symlinks: SAF exposes documents, not file-system links, so this code has no
 * symlink handling of its own. What a provider does with a link is the
 * provider's choice; the confinement above (child-of-root check at fetch, no
 * `..`, depth and count caps at list) is what keeps reads inside the tree.
 */
internal object FolderAccess {
    private const val MAX_DEPTH = 12
    private const val MAX_DIRS = 5000
    private val EXTENSIONS = setOf("txt", "md", "markdown", "pdf")

    fun treeUri(id: String): Uri = Uri.parse(id)

    fun displayName(ctx: Context, tree: Uri): String = try {
        val doc = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        ctx.contentResolver.query(doc, arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)
            ?.use { if (it.moveToFirst()) it.getString(0) else null } ?: "Folder"
    } catch (_: Exception) {
        "Folder"
    }

    fun takeReadGrant(ctx: Context, tree: Uri) {
        ctx.contentResolver.takePersistableUriPermission(tree, Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }

    fun release(ctx: Context, tree: Uri) {
        try {
            ctx.contentResolver.releasePersistableUriPermission(tree, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (_: Exception) {
        }
    }

    fun reachable(ctx: Context, tree: Uri): Boolean {
        val granted = ctx.contentResolver.persistedUriPermissions.any { it.uri == tree && it.isReadPermission }
        if (!granted) return false
        return try {
            val root = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
            ctx.contentResolver.query(root, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID), null, null, null)
                ?.use { it.moveToFirst() } ?: false
        } catch (_: Exception) {
            false
        }
    }

    fun list(ctx: Context, tree: Uri, maxFiles: Int): List<Map<String, Any?>> {
        val rootId = DocumentsContract.getTreeDocumentId(tree)
        val out = ArrayList<Map<String, Any?>>()
        val stack = ArrayDeque<Pair<String, Int>>()
        stack.addLast(rootId to 0)
        var dirs = 0
        while (stack.isNotEmpty() && out.size < maxFiles && dirs < MAX_DIRS) {
            val (dirId, depth) = stack.removeLast()
            dirs++
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, dirId)
            ctx.contentResolver.query(
                children,
                arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_MIME_TYPE,
                    DocumentsContract.Document.COLUMN_SIZE,
                    DocumentsContract.Document.COLUMN_LAST_MODIFIED,
                ),
                null, null, null,
            )?.use { c ->
                while (c.moveToNext() && out.size < maxFiles) {
                    val id = c.getString(0) ?: continue
                    val name = c.getString(1) ?: continue
                    val mime = c.getString(2)
                    if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                        if (depth < MAX_DEPTH) stack.addLast(id to depth + 1)
                        continue
                    }
                    if (name.substringAfterLast('.', "").lowercase() !in EXTENSIONS) continue
                    if (c.isNull(3)) continue
                    out.add(
                        mapOf(
                            "id" to id,
                            "name" to name,
                            "size" to c.getLong(3),
                            "modified" to if (c.isNull(4)) 0L else c.getLong(4),
                        ),
                    )
                }
                // A null cursor is a provider that cannot answer right now (a
                // cloud folder that is offline), not an empty folder: fail the
                // listing so the caller never reads it as "everything was
                // deleted".
            } ?: throw FolderError("unreadable", "The folder could not be read right now.")
        }
        return out
    }

    /**
     * The document URI for [entryId], only if it is the granted root or a
     * child of it (same confinement as [fetch]); otherwise a [FolderError].
     */
    fun confinedDocumentUri(ctx: Context, tree: Uri, entryId: String): Uri {
        val rootId = DocumentsContract.getTreeDocumentId(tree)
        if (entryId.isEmpty() || entryId.split('/', '\\').any { it == ".." }) {
            throw FolderError("outside_grant", "That file is not inside the chosen folder.")
        }
        val docUri = DocumentsContract.buildDocumentUriUsingTree(tree, entryId)
        val rootUri = DocumentsContract.buildDocumentUriUsingTree(tree, rootId)
        val inside = entryId == rootId || try {
            DocumentsContract.isChildDocument(ctx.contentResolver, rootUri, docUri)
        } catch (_: Exception) {
            false
        }
        if (!inside) throw FolderError("outside_grant", "That file is not inside the chosen folder.")
        return docUri
    }

    /** Opens a file of the granted folder in the phone's own viewer (read-only). */
    fun open(ctx: Context, activity: android.app.Activity?, tree: Uri, entryId: String) {
        val docUri = confinedDocumentUri(ctx, tree, entryId)
        val mime = ctx.contentResolver.getType(docUri) ?: "*/*"
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(docUri, mime)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        try {
            if (activity != null) activity.startActivity(intent)
            else ctx.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (_: android.content.ActivityNotFoundException) {
            throw FolderError("no_viewer", "No app on this phone can open that file.")
        }
    }

    fun fetch(ctx: Context, tree: Uri, entryId: String, dest: String, maxBytes: Long) {
        val docUri = confinedDocumentUri(ctx, tree, entryId)

        val target = File(dest).canonicalFile
        val cache = ctx.cacheDir.canonicalFile
        if (!target.path.startsWith(cache.path + File.separator)) {
            throw FolderError("bad_dest", "Cannot copy outside the app cache.")
        }
        target.parentFile?.mkdirs()

        val input = ctx.contentResolver.openInputStream(docUri)
            ?: throw FolderError("unreadable", "Could not open the file.")
        var written = 0L
        try {
            input.use { ins ->
                FileOutputStream(target).use { outs ->
                    val buf = ByteArray(64 * 1024)
                    while (true) {
                        val n = ins.read(buf)
                        if (n < 0) break
                        written += n
                        if (written > maxBytes) throw FolderError("too_large", "File is larger than the limit.")
                        outs.write(buf, 0, n)
                    }
                }
            }
        } catch (e: Exception) {
            target.delete()
            if (e is FolderError) throw e
            throw FolderError("unreadable", "Could not read the file.")
        }
    }
}
