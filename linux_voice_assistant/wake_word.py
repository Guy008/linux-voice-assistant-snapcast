#!/usr/bin/env python3
import json
import logging
from pathlib import Path
from typing import Dict, List, Optional, Set, Union

from pymicro_wakeword import MicroWakeWord
from pyopen_wakeword import OpenWakeWord

from .models import AvailableWakeWord, WakeWordType


_LOGGER = logging.getLogger(__name__)


def find_available_wake_words(wake_word_dirs: List[Path], stop_model_id: str) -> Dict[str, AvailableWakeWord]:
    """
    Sucht alle verfügbaren Wake Words in den angegebenen Verzeichnissen.
    Lädt Konfigurationen und erstellt AvailableWakeWord Objekte.
    
    Args:
        wake_word_dirs: Liste mit Verzeichnissen in denen nach Wake Words gesucht wird
        stop_model_id: ID des Stop-Modells welches nicht als verfügbares Wake Word angezeigt wird
        
    Returns:
        Dictionary mit Wake Word ID als Schlüssel und AvailableWakeWord Objekt als Wert
    """
    available_wake_words: Dict[str, AvailableWakeWord] = {}
    
    for wake_word_dir in wake_word_dirs:
        for model_config_path in wake_word_dir.glob("*.json"):
            model_id = model_config_path.stem
            if model_id == stop_model_id:
                # Stop Modell nicht als verfügbares Wake Word anzeigen
                continue
                
            with open(model_config_path, "r", encoding="utf-8") as model_config_file:
                model_config = json.load(model_config_file)
                model_type = WakeWordType(model_config["type"])
                
                if model_type == WakeWordType.OPEN_WAKE_WORD:
                    wake_word_path = model_config_path.parent / model_config["model"]
                else:
                    wake_word_path = model_config_path
                    
                available_wake_words[model_id] = AvailableWakeWord(
                    id=model_id,
                    type=WakeWordType(model_type),
                    wake_word=model_config["wake_word"],
                    trained_languages=model_config.get("trained_languages", []),
                    wake_word_path=wake_word_path,
                )
                
    _LOGGER.debug("Verfügbare Wake Words: %s", list(sorted(available_wake_words.keys())))
    return available_wake_words


def load_wake_models(
    available_wake_words: Dict[str, AvailableWakeWord],
    active_wake_word_ids: Optional[List[str]],
    default_wake_word_id: str
) -> tuple[Dict[str, Union[MicroWakeWord, OpenWakeWord]], Set[str]]:
    """
    Lädt die angegebenen Wake Word Modelle.
    
    Wenn keine aktiven Wake Words angegeben sind wird das Standard Modell geladen.
    
    Args:
        available_wake_words: Dictionary mit allen verfügbaren Wake Words
        active_wake_word_ids: Liste mit IDs der zu ladenden Wake Words (kann None sein)
        default_wake_word_id: ID des Standard Modells welches geladen wird wenn keine anderen angegeben sind
        
    Returns:
        Tuple mit (Dictionary der geladenen Modelle, Set der aktiven Wake Word IDs)
    """
    active_wake_words: Set[str] = set()
    wake_models: Dict[str, Union[MicroWakeWord, OpenWakeWord]] = {}
    
    if active_wake_word_ids:
        # Bevorzugte Modelle laden
        for wake_word_id in active_wake_word_ids:
            wake_word = available_wake_words.get(wake_word_id)
            if wake_word is None:
                _LOGGER.warning("Unbekannte Wake Word ID: %s", wake_word_id)
                continue
                
            _LOGGER.debug("Lade Wake Modell: %s", wake_word_id)
            wake_models[wake_word_id] = wake_word.load()
            active_wake_words.add(wake_word_id)
            
    if not wake_models:
        # Standard Modell laden
        wake_word_id = default_wake_word_id
        wake_word = available_wake_words[wake_word_id]
        
        _LOGGER.debug("Lade Wake Modell: %s", wake_word_id)
        wake_models[wake_word_id] = wake_word.load()
        active_wake_words.add(wake_word_id)
        
    return wake_models, active_wake_words


def load_stop_model(wake_word_dirs: List[Path], stop_model_id: str) -> Optional[MicroWakeWord]:
    """
    Lädt das Stop Wort Modell.
    
    Args:
        wake_word_dirs: Liste mit Verzeichnissen in denen nach dem Stop Modell gesucht wird
        stop_model_id: ID des Stop Modells
        
    Returns:
        Geladenes MicroWakeWord Objekt oder None falls nicht gefunden
    """
    for wake_word_dir in wake_word_dirs:
        stop_config_path = wake_word_dir / f"{stop_model_id}.json"
        if not stop_config_path.exists():
            continue
            
        _LOGGER.debug("Lade Stop Modell: %s", stop_config_path)
        return MicroWakeWord.from_config(stop_config_path)
        
    return None
