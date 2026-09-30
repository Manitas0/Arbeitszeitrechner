package de.arbeitszeitrechner.widget

import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import de.arbeitszeitrechner.MainActivity
import de.arbeitszeitrechner.calc.ClockAction
import de.arbeitszeitrechner.calc.formatTime
import de.arbeitszeitrechner.calc.nextClockAction
import de.arbeitszeitrechner.data.TimeClock

/** Kachel in den Schnelleinstellungen: Kommen/Gehen direkt aus der Benachrichtigungsleiste. */
class ClockTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        refreshTile()
    }

    override fun onClick() {
        super.onClick()
        if (TimeClock.toggle(this) == null) {
            // Heute ist schon fertig gestempelt (oder Urlaub usw.): App öffnen.
            openApp()
        } else {
            refreshTile()
        }
    }

    private fun refreshTile() {
        val tile = qsTile ?: return
        val entry = TimeClock.today(this)
        when (nextClockAction(entry)) {
            ClockAction.CLOCK_IN -> {
                tile.label = "Kommen"
                tile.state = Tile.STATE_INACTIVE
                setSubtitle(tile, "Einstempeln")
            }
            ClockAction.CLOCK_OUT -> {
                tile.label = "Gehen"
                tile.state = Tile.STATE_ACTIVE
                setSubtitle(tile, entry.start?.let { "seit ${formatTime(it)}" })
            }
            null -> {
                tile.label = "Arbeitszeit"
                tile.state = Tile.STATE_INACTIVE
                setSubtitle(tile, if (entry.type.isAbsence) entry.type.label else "Feierabend")
            }
        }
        tile.updateTile()
    }

    private fun setSubtitle(tile: Tile, text: String?) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) tile.subtitle = text
    }

    private fun openApp() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startActivityAndCollapse(WorkWidgets.openAppIntent(this))
        } else {
            openAppLegacy()
        }
    }

    @Suppress("DEPRECATION")
    private fun openAppLegacy() {
        startActivityAndCollapse(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}
