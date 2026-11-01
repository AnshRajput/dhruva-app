package tech.appuinside.dhruva

import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/** Quick Settings tile "Ask Dhruva": collapses the shade and opens a new chat. */
class DhruvaTileService : TileService() {
    override fun onStartListening() {
        qsTile?.apply {
            state = Tile.STATE_INACTIVE // a launcher, not a toggle
            updateTile()
        }
    }

    override fun onClick() {
        if (Build.VERSION.SDK_INT >= 34) {
            startActivityAndCollapse(ShortcutIntents.pending(this, "new_chat", 0))
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(ShortcutIntents.intent(this, "new_chat"))
        }
    }
}
