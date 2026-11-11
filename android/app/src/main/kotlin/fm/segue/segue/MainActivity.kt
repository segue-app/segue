package fm.segue.segue

import com.ryanheise.audioservice.AudioServiceActivity

// audio_service needs its own activity so playback survives the UI closing.
class MainActivity : AudioServiceActivity()
