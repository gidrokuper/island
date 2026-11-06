#!/bin/bash
# Пересобирает Island.icns из make-icon.swift
set -e
cd "$(dirname "$0")"
T=$(mktemp -d)
swift make-icon.swift "$T/1024.png"
mkdir -p "$T/Island.iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s "$T/1024.png" --out "$T/Island.iconset/icon_${s}x${s}.png" >/dev/null
  d=$((s*2)); sips -z $d $d "$T/1024.png" --out "$T/Island.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$T/Island.iconset" -o Island.icns
cp "$T/1024.png" preview.png
rm -rf "$T"
echo "OK icon"
