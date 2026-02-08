import threading
import logging
from typing import Optional
import mpv

from .base import AudioPlayer
from .state import PlayerState


class LibMpvPlayer(AudioPlayer):
    """
    Audio player implementation for Linux Voice Assistant based on libmpv.

    Features:
    - Thread-safe state handling
    - Explicit pause / resume control
    - Proper volume handling with ducking support
    - Compatible with LVA AudioPlayer interface
    """

    def __init__(self, device: Optional[str] = None) -> None:
        """
        Initialize the mpv-based audio player.

        :param device: Optional mpv audio output device name
        """
        self._log = logging.getLogger(self.__class__.__name__)
        self._state: PlayerState = PlayerState.IDLE
        self._state_lock = threading.Lock()

        # Volume handling
        self._user_volume: float = 100.0   # User volume (0.0 – 100.0)
        self._duck_factor: float = 1.0     # Ducking factor (0.0 – 1.0)

        # mpv setup
        self._mpv = mpv.MPV(
            audio_display=False,
            log_handler=self._on_mpv_log,
            loglevel="error",
        )

        if device:
            self._log.info("Using audio device: %s", device)
            self._mpv["audio-device"] = device

    # -------- Core Playback Methods --------

    def play(self, url: str, paused: bool = False) -> None:
        """
        Start playback of a media URL.

        :param url: Media URL or file path
        :param paused: If True, playback starts paused
        """
        with self._state_lock:
            self._set_state(PlayerState.LOADING)

        # Explicitly set pause state before starting playback
        self._mpv.pause = paused

        self._log.info("Loading media: %s (paused=%s)", url, paused)
        self._mpv.play(url)

    def pause(self) -> None:
        """
        Pause playback.
        """
        with self._state_lock:
            self._mpv.pause = True
            self._set_state(PlayerState.PAUSED)

    def resume(self) -> None:
        """
        Resume playback if paused.
        """
        with self._state_lock:
            self._mpv.pause = False
            self._set_state(PlayerState.PLAYING)

    def stop(self) -> None:
        """
        Stop playback and reset player state to IDLE.
        """
        with self._state_lock:
            self._mpv.stop()
            self._set_state(PlayerState.IDLE)

    def state(self) -> PlayerState:
        """
        Get the current player state.

        :return: Current PlayerState
        """
        with self._state_lock:
            return self._state

    # -------- Volume / Ducking --------

    def set_volume(self, volume: float) -> None:
        """
        Set the user volume.

        :param volume: Volume level (0.0 – 100.0)
        """
        with self._state_lock:
            self._user_volume = max(0.0, min(100.0, float(volume)))
            self._apply_volume()

    def duck(self, factor: float = 0.5) -> None:
        """
        Temporarily reduce volume by a ducking factor.

        :param factor: Ducking factor (0.0 – 1.0)
        """
        with self._state_lock:
            self._duck_factor = max(0.0, min(1.0, float(factor)))
            self._apply_volume()

    def unduck(self) -> None:
        """
        Restore volume to the user-defined level.
        """
        with self._state_lock:
            self._duck_factor = 1.0
            self._apply_volume()

    # -------- Internal Helpers --------

    def _apply_volume(self) -> None:
        """
        Apply effective volume (user volume × duck factor) to mpv.
        """
        effective = self._user_volume * self._duck_factor
        self._mpv.volume = max(0.0, min(100.0, effective))

    def _on_mpv_log(self, level: str, prefix: str, text: str) -> None:
        """
        Handle mpv log messages.

        Errors and fatal messages transition the player into ERROR state.
        """
        if level in ("error", "fatal"):
            self._log.error("[mpv] %s", text.strip())
            with self._state_lock:
                self._set_state(PlayerState.ERROR)

    def _set_state(self, new_state: PlayerState) -> None:
        """
        Update internal player state with logging.
        """
        if self._state != new_state:
            self._log.debug("State %s → %s", self._state.name, new_state.name)
            self._state = new_state