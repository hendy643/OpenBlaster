# Channel test for OpenBlaster's virtual surround sink.
#
#   scripts/virtual-surround-test.sh [--volume PCT] [--noise] [--loops N]
#
# Turn "Virtual surround" on in OpenBlaster first (its page, pick an effect). This plays a voice on each of the eight
# channels of the virtual 7.1 sink in turn: Front Left, Front Right, Center, LFE (noise), Rear Left, Rear Right,
# Side Left, Side Right. Each voice is sent to exactly that channel by name (pw-cat --channel-map), so the sink's
# own order is what is tested. Put your headphones on: the sound is meant to be placed around you.
#
#   --volume PCT  the sink's volume for the test (default 30): a new virtual sink starts at 100%, which is loud in
#                 headphones. Your volume is put back afterwards.
#   --noise       noise on each channel instead of a voice (easier to place)
#   --loops N     repeat the round N times (default 1)
set -euo pipefail

sink=openblaster_virtual_surround
volume=30 noise=0 loops=1
while (($#)); do
    case $1 in
    --volume) volume=${2:?--volume needs a percentage}; shift 2 ;;
    --noise) noise=1; shift ;;
    --loops) loops=${2:?--loops needs a number}; shift 2 ;;
    -h | --help) sed -n 4,16p "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1 (try --help)" >&2; exit 2 ;;
    esac
done
[[ $volume =~ ^[0-9]+$ && $volume -le 100 ]] || { echo "--volume must be 0 to 100" >&2; exit 2; }
[[ $loops =~ ^[1-9][0-9]*$ ]] || { echo "--loops must be a positive number" >&2; exit 2; }
for tool in pactl pw-cat python3; do
    command -v "$tool" >/dev/null || { echo "$tool is not installed" >&2; exit 1; }
done

if ! pactl list short sinks | awk -v s="$sink" '$2 == s {f=1} END {exit !f}'; then
    echo "The virtual sink ($sink) is not there." >&2
    echo "Switch \"Virtual surround\" on in OpenBlaster (Virtual surround page) and try again." >&2
    exit 1
fi
channels=$(pactl list sinks | awk -v s="$sink" '$0 ~ "Name: " s {f=1} f && /Sample Specification/ {print $4; exit}')
channels=${channels%ch}
echo "sink: $sink (${channels:-?} channels)"

# restore the sink's volume and mute state when we are done, however we end
old_volume=$(pactl get-sink-volume "$sink" | grep -o '[0-9]*%' | head -1)
old_mute=$(pactl get-sink-mute "$sink" | awk '{print $2}')
restore() {
    pactl set-sink-volume "$sink" "${old_volume:-100%}" 2>/dev/null || true
    pactl set-sink-mute "$sink" "$([[ $old_mute == yes ]] && echo 1 || echo 0)" 2>/dev/null || true
}
trap restore EXIT
pactl set-sink-mute "$sink" 0
pactl set-sink-volume "$sink" "${volume}%"
echo "playing at ${volume}% (was ${old_volume:-?}); Ctrl-C stops"

# The sink's channels in its own order: position, the voice for it (ALSA's sound files), what to call it.
# Each voice goes to exactly one channel of an 8-channel raw stream whose channel map is spelled out, so what is
# tested is the sink's own order, not speaker-test's or a file's.
sounds=/usr/share/sounds/alsa
positions=(FL FR FC LFE RL RR SL SR)
files=(Front_Left Front_Right Front_Center Noise Rear_Left Rear_Right Side_Left Side_Right)
names=("Front Left" "Front Right" "Center" "LFE (noise)" "Rear Left" "Rear Right" "Side Left" "Side Right")
[[ -f $sounds/Noise.wav ]] || { echo "the ALSA sound files are missing ($sounds; install alsa-utils)" >&2; exit 1; }
map=$(IFS=,; echo "${positions[*]}")

# 8 interleaved s16 channels at 48 kHz with only channel $1 carrying the sound of file $2, then half a second of quiet
one_channel() {
    python3 - "$1" "$2" <<'PY'
import array, sys, wave
ch, path = int(sys.argv[1]), sys.argv[2]
w = wave.open(path)
assert w.getnchannels() == 1 and w.getsampwidth() == 2 and w.getframerate() == 48000, path
mono = array.array("h", w.readframes(w.getnframes()))
out = array.array("h", bytes(2 * 8 * (len(mono) + 24000)))
for i, v in enumerate(mono):
    out[i * 8 + ch] = v
sys.stdout.buffer.write(out.tobytes())
PY
}

for ((round = 1; round <= loops; round++)); do
    for i in "${!positions[@]}"; do
        file=$sounds/${files[i]}.wav
        ((noise)) && file=$sounds/Noise.wav
        printf ' %-4s %s\n' "${positions[i]}" "${names[i]}"
        one_channel "$i" "$file" |
            pw-cat -p -a --target "$sink" --rate 48000 --format s16 --channels 8 --channel-map "$map" -
    done
done
