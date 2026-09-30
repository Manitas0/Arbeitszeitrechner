package de.arbeitszeitrechner.data

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import java.io.File
import java.io.IOException

/** Lesen und Schreiben von Dateien, die der Nutzer ausgewählt hat, sowie Teilen von Dateien. */
object DataTransfer {

    fun writeText(context: Context, uri: Uri, text: String) {
        val resolver = context.contentResolver
        // "wt" kürzt die Datei vorher; nicht jeder Anbieter unterstützt das.
        val stream = runCatching { resolver.openOutputStream(uri, "wt") }.getOrNull()
            ?: resolver.openOutputStream(uri, "w")
            ?: throw IOException("Datei kann nicht geschrieben werden")
        stream.use { it.write(text.toByteArray(Charsets.UTF_8)) }
    }

    fun readText(context: Context, uri: Uri): String =
        context.contentResolver.openInputStream(uri)?.use { it.readBytes().toString(Charsets.UTF_8) }
            ?: throw IOException("Datei kann nicht gelesen werden")

    /** Öffnet das Teilen-Menü mit einer Datei (z. B. Mail an den Arbeitgeber). */
    fun shareFile(context: Context, fileName: String, mimeType: String, content: String, title: String) {
        val dir = File(context.cacheDir, "exports").apply { mkdirs() }
        val file = File(dir, fileName)
        file.writeText(content, Charsets.UTF_8)
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = mimeType
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_SUBJECT, title)
            clipData = ClipData.newRawUri(fileName, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(intent, title))
    }
}
