#!/bin/bash
cd "$(dirname "$0")"
pkill -f "Lobby.app/Contents/MacOS/Lobby" 2>/dev/null || true
./release.sh 2>&1 | tail -8
open build/Lobby.app
sleep 3
pgrep -fl Lobby.app | head -1
