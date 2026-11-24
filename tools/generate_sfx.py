#!/usr/bin/env python3
"""Generate the game's sound library with ElevenLabs. Requires Python 3.9+ and FFmpeg for the regulator loop."""

import argparse
from array import array
from dataclasses import dataclass
import fcntl
import http.client
import json
import os
from pathlib import Path
from shutil import which
import stat
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request


PROJECT = Path(__file__).resolve().parents[1]
DESTINATION = PROJECT / "audio" / "generated"
KEY_FILE = Path(os.environ.get("ELEVENLABS_KEY_FILE", Path.home() / ".config" / "home-twenty" / "elevenlabs.key"))
ENDPOINT = "https://api.elevenlabs.io/v1/sound-generation?output_format=mp3_44100_128"


@dataclass(frozen=True)
class Cue:
    seconds: float
    loop: bool
    prompt: str


CUES = {
    "bell": Cue(12, True, "Field recording inside a cramped steel offshore diving bell. A steady ventilation blower close to the mic, a low electrical hum and the small irregular bearing rustle of an ageing fan. Warm enclosed dry machinery room tone. Even level throughout. No voices, music, drums, impacts or outside water."),
    "steel": Cue(15, True, "Quiet deep subsea platform jacket as heard by a worker beside a steel piling. Distant continuous machinery transmitted through a vast hollow steel tube, very soft midrange hydraulic whine over a dull low vibration. Sparse, ordinary industrial field ambience with occasional tiny ticks. No music, whale calls, sonar pings, surf or dramatic crescendos."),
    "breath": Cue(18, True, "Inside a sealed commercial diving helmet. Only the air valve: a smooth two-second shhh of demand air, a softer lower two-second outflow, a short quiet rest. Repeat four times at ordinary resting cadence. No tremor, voiced throat, shivering, chattering teeth, gasps, sniffing, bubbles or music. Boring warm steady equipment Foley with each breath very similar to the last. Seamless loop."),
    "comms": Cue(0.55, False, "One very quiet dull contact click and a trace of wire noise coming from a small wired industrial intercom earpiece. Close dry foley, crisp immediate attack. No radio tuning, beeps, ringing, speech, or music."),
    "adjust": Cue(0.55, False, "One precise little tactile notch from a knurled metal instrument selector, moved one detent by a gloved thumb underwater. Short dark tick transmitted through the instrument housing. Immediate onset. One click only; no beep, squeak or speech."),
    "accept": Cue(0.85, False, "One small positive closing click from a steel over-centre instrument latch fitting home, a tick and a deeper seated clunk in quick succession. Damp, close, solid and satisfying, restrained with no long tail. No music, beeps, ringing or speech."),
    "reject": Cue(0.65, False, "A tiny spring-loaded gauge detent slips back against its stop, two soft muted ticks very close together. Intimate handling foley on an old mechanical instrument. No buzzer, music, alarm, speech or background."),
    "groan": Cue(7, False, "Recorded underwater beside a vast steel offshore platform leg at depth. One slow, very low structural groan as a huge hollow steel tube flexes under load, a deep moan that bends slightly in pitch, carried through cold water, distant and enormous, fading into silence. No whale song, voices, music, sonar or explosions."),
    "knock": Cue(2.5, False, "Underwater, far away inside a huge steel structure: a single dull heavy knock on a hollow steel member, as if something solid bumped a pipe in the distance. Muffled through water, deep body, long soft reverberant tail. One impact only. No music, voices, bubbles or sonar."),
    "double_knock": Cue(3, False, "Underwater, far off and muffled: two dull heavy knocks about half a second apart, like a steel equipment basket landing on a deck and settling, transmitted through cold water and a steel structure. Long soft tail. No music, voices, bubbles or sonar."),
    "tick": Cue(1.2, False, "One small sharp metallic tick and faint ringing ping from cold steel contracting nearby underwater, heard through a diving helmet. Very short, clean, a little eerie. No music, beeps, voices or bubbles."),
    "chain": Cue(4.5, False, "Underwater, distant and high above: a heavy chain or steel wire rope dragging and clanking slowly against a steel structure, muffled through deep water with a long dark tail. No music, voices, bubbles, sonar or ship horns."),
    "static": Cue(1.2, False, "A short burst of crackling static and wire noise from a wired diving intercom earpiece as the signal briefly drops out, then cuts to silence. Dry close foley, rough and irregular. No speech, tones, beeps, radio tuning or music."),
    "flicker": Cue(0.8, False, "A tiny electrical relay chatter and brief buzzing sputter from a sealed helmet lamp heard from inside a diving helmet, two quick dull clicks. Close, dry and small. No music, beeps, alarm or speech."),
    "hatch": Cue(1.5, False,"Close inside a working diving bell: a heavy gloved hand pushes off a short steel ladder rung. One dull structural thunk, a tiny follow-up metal rattle and a soft water wash below the open wet porch. Industrial foley with a compact tail, no airlock jets, alarm, speech or music."),
}


def api_key():
    value = os.environ.get("ELEVENLABS_API_KEY", "").strip()
    if not value:
        try:
            with KEY_FILE.open(encoding="utf-8") as handle:
                info = os.fstat(handle.fileno())
                if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
                    raise ValueError(f"Use a key file owned by you with mode 600: {KEY_FILE}")
                value = handle.read(2048).strip()
        except FileNotFoundError:
            pass
    if not value:
        raise ValueError(f"Set ELEVENLABS_API_KEY or put the raw key in {KEY_FILE} (mode 600).")
    if not value.isascii() or not value.isprintable() or any(c.isspace() for c in value):
        raise ValueError("The API key must contain one token.")
    return value


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # A redirect must never forward the private xi-api-key header.
        return None


def looks_like_mp3(header):
    return header[:3] == b"ID3" or (len(header) >= 2 and header[0] == 0xFF and header[1] & 0xE0 == 0xE0)


def regular_breath(recording):
    """Cut four ordinary cycles from steady passages of the recorded demand valve."""
    ffmpeg = ["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error"]
    preview = subprocess.run(ffmpeg + ["-i", "pipe:0", "-ac", "1", "-ar", "8000", "-f", "s16le", "pipe:1"],
                             input=recording, capture_output=True, check=True).stdout
    samples = array("h")
    samples.frombytes(preview)
    if sys.byteorder != "little":
        samples.byteswap()
    # The generator varies where the valve opens. Choose a continuous, even
    # passage in each quarter, well clear of clicks and gaps between openings.
    blocks = [samples[i:i+400] for i in range(0, len(samples)-399, 400)]
    power = [sum(x*x for x in block) / len(block) for block in blocks]
    width = 20  # one second, in 50 ms blocks
    takes = []
    for quarter in range(4):
        start, end = len(power)*quarter//4, len(power)*(quarter+1)//4
        if end-start < width:
            raise ValueError("Regulator recording is too short to cut four cycles.")
        def stability(index):
            window = sorted(power[index:index+width])
            return window[2] / max(1.0, window[-3])**0.30
        best = max(range(start, end-width+1), key=stability)
        takes.append(best*0.05)

    filters, clips = [], []
    for i, period in enumerate((4.55, 4.72, 4.48, 4.65)):
        inhale = period*0.36
        exhale = period*0.43
        # Slower air leaving the helmet is lower and softer than the intake.
        phases = [(takes[i], inhale, 3000, 0.0, 0.12), (takes[(i+1)%4], exhale, 1150, -2.5, period-inhale-exhale-0.12)]
        for j, (source, duration, cutoff, gain, gap) in enumerate(phases):
            tag = f"phase{i}{j}"
            rate = round(44100/duration)
            filters.append(f"[0:a]atrim=start={source:.3f}:duration=1.0,asetpts=PTS-STARTPTS,"
                           f"aresample=44100,asetrate={rate},aresample=44100,highpass=f=100,lowpass=f={cutoff},"
                           f"volume={gain}dB,afade=t=in:d={duration*0.22:.3f}:curve=qsin,"
                           f"afade=t=out:st={duration*0.58:.3f}:d={duration*0.42:.3f}:curve=qsin,"
                           f"apad=pad_dur={gap:.3f}[{tag}]")
            clips.append(f"[{tag}]")
    filters.append("".join(clips) + "concat=n=8:v=0:a=1,loudnorm=I=-31:TP=-9:LRA=6,aresample=44100[loop]")
    return subprocess.run(ffmpeg + ["-i", "pipe:0", "-filter_complex", ";".join(filters), "-map", "[loop]",
                                     "-ac", "1", "-codec:a", "libmp3lame", "-b:a", "128k", "-f", "mp3", "pipe:1"],
                          input=recording, capture_output=True, check=True).stdout


def generate(name, key, destination):
    cue = CUES[name]
    if name == "breath" and which("ffmpeg") is None:
        raise ValueError("Install FFmpeg before generating the regulator loop.")
    body = json.dumps({
        "text": cue.prompt,
        "duration_seconds": cue.seconds,
        "loop": cue.loop,
        "model_id": "eleven_text_to_sound_v2",
    }).encode()
    request = urllib.request.Request(ENDPOINT, data=body, headers={
        "Content-Type": "application/json", "Accept": "audio/mpeg", "xi-api-key": key,
    })
    opener = urllib.request.build_opener(NoRedirect())
    try:
        with opener.open(request, timeout=120) as response:
            sound = response.read()
            expected = response.headers.get("Content-Length")
            if (expected and int(expected) != len(sound)) or len(sound) < 512 or not looks_like_mp3(sound):
                raise ValueError(f"{name}: ElevenLabs returned incomplete or unexpected audio.")
    except urllib.error.HTTPError as error:
        error.close()
        raise ValueError(f"{name}: ElevenLabs returned HTTP {error.code}. Check key permissions, credits and rate limits.") from None
    except http.client.IncompleteRead:
        raise ValueError(f"{name}: transfer ended early. No audio file was written.") from None
    if name == "breath":
        try:
            sound = regular_breath(sound)
        except subprocess.CalledProcessError as error:
            raise ValueError(f"Could not prepare the regulator loop: {error.stderr.decode(errors='replace').strip()}") from None
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=destination.parent, prefix=f".{name}-", delete=False) as handle:
            temporary = Path(handle.name)
            handle.write(sound)
            handle.flush()
            os.fsync(handle.fileno())
        temporary.replace(destination)
    finally:
        if temporary:
            temporary.unlink(missing_ok=True)


def run():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cues", nargs="*", metavar="CUE", help="one or more cue IDs from --list")
    parser.add_argument("--list", action="store_true", help="list cues without contacting ElevenLabs")
    parser.add_argument("--all", action="store_true", help="generate all missing cues (uses API credits)")
    args = parser.parse_args()
    if args.list:
        for name, cue in CUES.items():
            print(f"{name:15s} {cue.seconds:4.1f}s  {'loop' if cue.loop else 'one-shot'}")
        return
    if bool(args.cues) == args.all:
        parser.error("specify cue IDs or --all")
    names = list(CUES) if args.all else list(dict.fromkeys(args.cues))
    unknown = [name for name in names if name not in CUES]
    if unknown:
        parser.error("unknown cue(s): " + ", ".join(unknown))
    DESTINATION.mkdir(parents=True, exist_ok=True)
    # Serialize generation across simultaneous CLI calls to avoid duplicate paid requests.
    directory_fd = os.open(DESTINATION, os.O_RDONLY)
    try:
        fcntl.flock(directory_fd, fcntl.LOCK_EX)
        key = None
        for name in names:
            destination = DESTINATION / f"{name}.mp3"
            if destination.exists():
                with destination.open("rb") as handle:
                    if destination.stat().st_size < 512 or not looks_like_mp3(handle.read(4)):
                        raise ValueError(f"{destination} is not a valid MP3. Move it aside before regenerating.")
                print(f"Kept {destination.name}")
                continue
            if key is None:
                key = api_key()
            print(f"Generating {name}…", flush=True)
            generate(name, key, destination)
            print(f"Wrote {destination.name}")
    finally:
        os.close(directory_fd)


if __name__ == "__main__":
    try:
        run()
    except (ValueError, OSError) as error:
        sys.exit(str(error))
