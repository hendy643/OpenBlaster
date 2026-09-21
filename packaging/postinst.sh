#!/bin/sh
# After install or upgrade: apply the udev rule (audio-group access to the LED register file) to a card that is
# already plugged in; otherwise it would wait for the next boot.
udevadm control --reload >/dev/null 2>&1 || true
udevadm trigger --subsystem-match=pci --action=add >/dev/null 2>&1 || true
exit 0
