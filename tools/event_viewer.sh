#!/bin/sh
# The event viewer: ride around town and step through every happening, call-out and challenge one at a time.
#   ] or N: next event    [ or P: previous    R: run it again
# Each starts right by you, in the season and at the time of day it needs. Your save is put back when you quit.
cd "$(dirname "$0")/.." && PIZZA_DEBUG=eventviewer exec godot --path . "$@"
