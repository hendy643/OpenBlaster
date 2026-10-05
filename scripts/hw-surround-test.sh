#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Does each channel come out of the card's DSP where it should, on Headphone with Surround on?
#
#   scripts/hw-surround-test.sh [--volume PCT] [CARD]      (default: the first Creative card)
#   --volume   the volume while testing (default 30): a new 5.1 sink starts at 100%, which is loud in headphones.
#
# Needs the card profile set from install/openblaster-ae5.conf (see the udev rule), which gives the 5.1 sink the
# driver's channel order, FL FR FC LFE RL RR. The script checks that, then sends a voice to each channel BY NAME and
# says where you should hear it. Put the card on Headphone with Surround on (in OpenBlaster), put your headphones on:
#   Front Left / Front Right   in front, left / right
#   Center                     in front, in the middle
#   LFE (noise)                bass-heavy noise, no direction
#   Rear Left / Rear Right     behind you, left / right (duller than the fronts: that is the HRTF)
# Changes no card setting; the profile and Output Select you had are put back afterwards, also on Ctrl-C.
set -euo pipefail

volume=30
while (($#)); do
    case $1 in
    --volume) volume=${2:?--volume needs a percentage}; shift 2 ;;
    -h | --help) sed -n 4,16p "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) break ;;
    esac
done
[[ $volume =~ ^[0-9]+$ && $volume -le 100 ]] || { echo "--volume must be 0 to 100" >&2; exit 2; }
for tool in pactl amixer python3; do command -v "$tool" >/dev/null || { echo "$tool is not installed" >&2; exit 1; }; done
command -v pw-cat >/dev/null || { echo "pw-cat is not installed" >&2; exit 1; }

card=${1:-}
if [[ -z $card ]]; then   # the first Creative (PCI vendor 0x1102) sound card
    for d in /sys/class/sound/card[0-9]*; do
        [[ $(cat "$d/device/vendor" 2>/dev/null) == 0x1102 ]] && { card=${d##*card}; break; }
    done
fi
[[ -n $card ]] || { echo "no Creative card found" >&2; exit 1; }
pci=$(basename "$(readlink -f "/sys/class/sound/card$card/device")")   # 0000:0b:00.0
name=alsa_card.pci-${pci//:/_}
echo "card $card = $name"
echo "output:   $(amixer -c"$card" sget 'Output Select' | sed -n 's/.*Item0: //p')"
echo "surround: $(amixer -c"$card" cget name='FX: Surround Playback Switch' | sed -n 's/.*: values=//p')"
echo "channel map: $(amixer -c"$card" cget name='Playback Channel Map' | grep -o 'chmap-fixed=FL,FR,FC[A-Z,]*' | head -1)"

sounds=/usr/share/sounds/alsa
[[ -f $sounds/Front_Left.wav ]] || { echo "the ALSA sound files are missing ($sounds; install alsa-utils)" >&2; exit 1; }
positions=(FL FR FC LFE RL RR)   # the driver's slot order
files=(Front_Left Front_Right Front_Center Noise Rear_Left Rear_Right)
names=("Front Left: front, left" "Front Right: front, right" "Center: front, middle" "LFE: bass noise, no direction" "Rear Left: behind, left" "Rear Right: behind, right")

# 6 interleaved s16 channels at 48 kHz with only channel $1 carrying the sound of file $2, then half a second of quiet
one_channel() {
    python3 - "$1" "$2" <<'PY'
import array, sys, wave
ch, path = int(sys.argv[1]), sys.argv[2]
w = wave.open(path)
assert w.getnchannels() == 1 and w.getsampwidth() == 2 and w.getframerate() == 48000, path
mono = array.array("h", w.readframes(w.getnframes()))
out = array.array("h", bytes(2 * 6 * (len(mono) + 24000)))
for i, v in enumerate(mono):
    out[i * 6 + ch] = v
sys.stdout.buffer.write(out.tobytes())
PY
}

# Changing the profile makes PipeWire unmute "Front Playback Switch", which the driver takes for "use the speakers":
# Output Select flips from Headphone to Speakers. Put it back.
out=$(amixer -c"$card" cget name='Output Select' | sed -n 's/.*: values=//p')
old=$(pactl list cards | awk -v n="$name" '$0 ~ "Name: " n {f=1} f && /Active Profile:/ {print $3; exit}')
stereo_sink=$(pactl get-default-sink)
old_volume=$(pactl get-sink-volume "$stereo_sink" | grep -o "[0-9]*%" | head -1)
restore() { pactl set-card-profile "$name" "$old" 2>/dev/null || true; amixer -q -c"$card" cset name='Output Select' "$out" || true; echo "back to $old"; }
trap restore EXIT

pactl set-card-profile "$name" output:analog-surround-51+input:analog-stereo
sleep 1
amixer -q -c"$card" cset name='Output Select' "$out"
sink=$(pactl list short sinks | awk -v p="pci-${pci//:/_}" 'index($2, p) && /surround-51/ {print $2; exit}')
[[ -n $sink ]] || { echo "no 5.1 sink appeared for $name" >&2; exit 1; }
map_now=$(pactl list sinks | awk -v s="$sink" '$0 ~ "Name: " s {f=1} f && /Channel Map/ {print $3; exit}')
echo "sink $sink: $map_now"
[[ $map_now == front-left,front-right,front-center,lfe,rear-left,rear-right ]] || {
    echo "The sink's channel map is not the driver's order (front-left,front-right,front-center,lfe,rear-left,rear-right)." >&2
    echo "Install install/openblaster-ae5.conf and the udev rule, restart pipewire and wireplumber, and run this again." >&2
    exit 1
}
pactl set-sink-mute "$sink" 0
pactl set-sink-volume "$sink" "${volume}%"
map=$(IFS=,; echo "${positions[*]}")
for i in "${!positions[@]}"; do
    printf ' %-4s %s\n' "${positions[i]}" "${names[i]}"
    one_channel "$i" "$sounds/${files[i]}.wav" |
        pw-cat -p -a --target "$sink" --rate 48000 --format s16 --channels 6 --channel-map "$map" -
done
