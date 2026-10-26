#!/bin/sh
# Stops a running Kigo. Deliberately not `hey ... quit`: scripting Kigo with
# hey coincided with a full VM hang on 2026-10-25 (Haiku arm64, UTM).
for team in $(ps | awk '$1 ~ /(^|\/)(Kigo|kigo)$/ {print $(NF-3)}'); do
	kill "$team"
done
true
