package fm.segue.segue

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.view.KeyEvent
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * Home-screen widget: cover, title, artist and transport buttons.
 * Data comes from the app (home_widget); the buttons send media-button
 * events to audio_service, the same as headphone buttons.
 */
class SegueWidgetProvider : HomeWidgetProvider() {
  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    for (id in appWidgetIds) {
      val views = RemoteViews(context.packageName, R.layout.segue_widget)
      val title = widgetData.getString("title", null)
      val artist = widgetData.getString("artist", null)
      val playing = widgetData.getBoolean("playing", false)

      views.setTextViewText(R.id.widget_title, title ?: "Segue")
      views.setTextViewText(
          R.id.widget_artist, artist ?: context.getString(R.string.widget_empty))
      views.setImageViewResource(
          R.id.widget_play,
          if (playing) R.drawable.widget_pause else R.drawable.widget_play)

      val cover = widgetData.getString("cover", null)
      val bitmap = cover?.let {
        val opts = BitmapFactory.Options().apply { inSampleSize = 2 }
        BitmapFactory.decodeFile(it, opts)
      }
      if (bitmap != null) {
        views.setImageViewBitmap(R.id.widget_cover, bitmap)
      } else {
        views.setImageViewResource(R.id.widget_cover, R.mipmap.ic_launcher)
      }
      val hasTrack = title != null
      val controls = if (hasTrack) View.VISIBLE else View.GONE
      views.setViewVisibility(R.id.widget_controls, controls)

      views.setOnClickPendingIntent(
          R.id.widget_root,
          HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java))
      views.setOnClickPendingIntent(
          R.id.widget_prev, mediaButton(context, KeyEvent.KEYCODE_MEDIA_PREVIOUS))
      views.setOnClickPendingIntent(
          R.id.widget_play, mediaButton(context, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE))
      views.setOnClickPendingIntent(
          R.id.widget_next, mediaButton(context, KeyEvent.KEYCODE_MEDIA_NEXT))

      appWidgetManager.updateAppWidget(id, views)
    }
  }

  private fun mediaButton(context: Context, keyCode: Int): PendingIntent {
    val intent = Intent(Intent.ACTION_MEDIA_BUTTON).apply {
      component =
          ComponentName(context, "com.ryanheise.audioservice.MediaButtonReceiver")
      putExtra(Intent.EXTRA_KEY_EVENT, KeyEvent(KeyEvent.ACTION_DOWN, keyCode))
    }
    return PendingIntent.getBroadcast(
        context,
        keyCode,
        intent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
  }
}
