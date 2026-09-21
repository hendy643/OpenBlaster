#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Does the card's DSP fold 5.1 down to the headphones when Surround is on?
#
#   scripts/surround-test.sh [--wait] [CARD]      (default: the first Creative card)
#   --wait   stop before playing, so you can send the DSP a command from another terminal first
#
# Put the card on Headphone with Surround on (in OpenBlaster), put your headphones on, and run this. It switches
# PipeWire to the 5.1 output profile, has speaker-test announce each of the six channels in turn ("Front Left",
# "Front Right", "Rear Left", ...) at your current volume, and switches back to the profile you had, also on Ctrl-C.
# Changes no card setting. What you hear tells you:
#   all six announced (in the headphones)    -> the DSP downmixes 5.1: output 5.1 whenever Headphone + Surround is on
#   only Front Left / Front Right            -> it does not: the DSP takes stereo only, so keep PipeWire at stereo
set -euo pipefail

wait=0
[[ ${1:-} == --wait ]] && { wait=1; shift; }
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
echo "auto-detect: $(amixer -c"$card" cget name='HP/Speaker Auto Detect Playback Switch' | sed -n 's/.*: values=//p') (headphones may stay silent unless this is on)"

# the volume you have now, to give every channel of the 5.1 output: PipeWire starts a new 5.1 sink with the
# rear, centre and LFE channels at 0% and the front pair low, which sounds like a broken card
stereo_sink=$(pactl get-default-sink)
volume=$(pactl get-sink-volume "$stereo_sink" | grep -o "[0-9]*%" | head -1)
# Activating the 5.1 profile makes PipeWire unmute "Front Playback Switch", which the driver takes for "use the speakers":
# Output Select flips from Headphone to Speakers and the six channels go to the speaker jacks. Put it back.
out=$(amixer -c"$card" cget name='Output Select' | sed -n 's/.*: values=//p')
old=$(pactl list cards | awk -v n="$name" '$0 ~ "Name: " n {f=1} f && /Active Profile:/ {print $3; exit}')
restore() { pactl set-card-profile "$name" "$old" 2>/dev/null || true; amixer -q -c"$card" cset name='Output Select' "$out" || true; echo "back to $old"; }
trap restore EXIT
pactl set-card-profile "$name" output:analog-surround-51+input:analog-stereo
sleep 1
amixer -q -c"$card" cset name='Output Select' "$out"
sink=$(pactl list short sinks | awk -v p="pci-${pci//:/_}" 'index($2, p) && /surround-51/ {print $2; exit}')
[[ -n $sink ]] || { echo "no 5.1 sink appeared for $name" >&2; exit 1; }
pactl set-sink-mute "$sink" 0
pactl set-sink-volume "$sink" "$volume"   # all six channels, the same as your stereo volume
((wait)) && read -rp "Output is back on your choice. Press Enter to play (send the DSP command now if you want to) " _
echo "playing on $sink at $volume (each channel announced once) ..."
PULSE_SINK=$sink speaker-test -D pulse -c 6 -t wav -l 1
