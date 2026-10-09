package de.arbeitszeitrechner

import org.json.JSONObject
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Prüft, dass shared/test-vectors.json zur Kotlin-Implementierung passt.
 * Nach einer gewollten Änderung der Rechenlogik neu erzeugen mit:
 *   UPDATE_TEST_VECTORS=1 ./gradlew testDebugUnitTest --tests '*SharedVectorsTest*'
 */
class SharedVectorsTest {

    @Test
    fun sharedVectorsMatchKotlinImplementation() {
        val file = File("../shared/test-vectors.json")
        val generated = SharedVectors.generate()
        if (System.getenv("UPDATE_TEST_VECTORS") == "1") {
            file.writeText(generated.toString(1) + "\n")
            return
        }
        assertTrue(
            "shared/test-vectors.json ist veraltet – mit UPDATE_TEST_VECTORS=1 neu erzeugen",
            JSONObject(file.readText()).similar(generated),
        )
    }
}
