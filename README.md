# Linux-Voice-Assistant

[![CI](https://github.com/OHF-Voice/linux-voice-assistant/actions/workflows/docker-build-release.yml/badge.svg)](https://github.com/OHF-Voice/linux-voice-assistant/actions/workflows/docker-build-release.yml) [![GitHub Package Version](https://img.shields.io/github/v/tag/OHF-Voice/linux-voice-assistant?label=version)](https://github.com/OHF-Voice/linux-voice-assistant/pkgs/container/linux-voice-assistant) [![GitHub License](https://img.shields.io/github/license/OHF-Voice/linux-voice-assistant)](https://github.com/OHF-Voice/linux-voice-assistant/blob/main/LICENSE.md) [![GitHub last commit](https://img.shields.io/github/last-commit/OHF-Voice/linux-voice-assistant)](https://github.com/OHF-Voice/linux-voice-assistant/commits) [![GitHub Container Registry](https://img.shields.io/badge/Container%20Registry-GHCR-blue)](https://github.com/OHF-Voice/linux-voice-assistant/pkgs/container/linux-voice-assistant)

Experimental Linux-Voice-Assistant for [Home Assistant](https://www.home-assistant.io/) that uses the [ESPHome](https://esphome.io/) protocol.


## Features:

- Works with [Home Assistant](https://www.home-assistant.io/integrations/esphome/)
- Local wake word detection using integrated [OpenWakeWord](https://github.com/dscripka/openWakeWord) or [MicroWakeWord](https://github.com/kahrendt/microWakeWord)
- Supports multiple architectures (linux/amd64 and linux/aarch64)
- Automated builds with artifact attestation for security
- Supports multiple wake words and languages
- Supports announcments, start/continue conversation, and timers
- Tested with Python 3.13 and Python 3.11.
- Prebuild docker image available on [GitHub Container Registry](https://github.com/OHF-Voice/linux-voice-assistant/pkgs/container/linux-voice-assistant)
- Prebuild Raspberry Pi image


## Usage:

### Hardware:

You can for example use the Raspberry Pi Zero 2W with the [Satellite1 Hat Board](https://futureproofhomes.net/products/satellite1-top-microphone-board) or the [Respeaker 2Mic_Hat](https://wiki.seeedstudio.com/ReSpeaker_2_Mics_Pi_HAT/). A list for possible compatible hardware can be found in the [PiCompose documentation](https://github.com/florian-asche/PiCompose) but basically any microphone that works with [Pipewire](https://pipewire.org/) can be used.

### Software:

See [Linux-Voice-Assistant - Installation](docs/install.md)


## Build Information:

Image builds can be tracked in this repository's `Actions` tab, and utilize [artifact attestation](https://docs.github.com/en/actions/security-guides/using-artifact-attestations-to-establish-provenance-for-builds) to certify provenance.

The Docker images are built using GitHub Actions, which provides:

- Automated builds for different architectures
- Artifact attestation for build provenance verification
- Regular updates and maintenance

The documentation for the build process can be found in the [GitHub Actions Workflows](.github/workflow.md) file.
