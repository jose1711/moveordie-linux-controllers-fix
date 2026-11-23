#!/usr/bin/env bash
# Make more than one gamepad work in Move or Die (Steam appid 323850, native Linux build).
#
#  1. Moves the bundled, old libSDL2 (no udev, only /dev/input/event0..31, no hotplug)
#     out of the way, so the game uses the newer SDL2 from the Steam Linux Runtime.
#  2. Repairs usercontrollerdb.txt, which the game corrupts for GUIDs produced by newer SDL
#     (entries containing "crc:" end up with no button mappings at all).
#
# Usage: ./fix.sh [path/to/steamapps/common/Move or Die]
#        ./fix.sh --restore [path/to/steamapps/common/Move or Die]
set -euo pipefail

ORIG_SDL_SHA=61bd049e7370c1eb80c156704e39c796b0ae174a84ef85cb9d04f666fe21adb2
REL=Love/linux32/libSDL2-2.0.so.0
DB="${XDG_DATA_HOME:-$HOME/.local/share}/love/Move Or Die/usercontrollerdb.txt"

restore=0
if [[ ${1:-} == --restore ]]; then restore=1; shift; fi

find_game() {
    local vdf p
    for vdf in ~/.local/share/Steam/steamapps/libraryfolders.vdf \
               ~/.steam/steam/steamapps/libraryfolders.vdf \
               ~/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/libraryfolders.vdf; do
        [[ -f $vdf ]] || continue
        while read -r p; do
            [[ -f "$p/steamapps/common/Move or Die/start_linux32.sh" ]] && { echo "$p/steamapps/common/Move or Die"; return; }
        done < <(sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"/\1/p' "$vdf")
    done
    return 1
}

game=${1:-$(find_game)} || { echo "Move or Die not found, pass the game directory as an argument." >&2; exit 1; }
lib=$game/$REL
[[ -f "$game/start_linux32.sh" ]] || { echo "Not a Move or Die directory: $game" >&2; exit 1; }

if pgrep -x lt-love >/dev/null; then
    echo "The game is running, quit it first." >&2; exit 1
fi

if (( restore )); then
    if [[ -f $lib.orig ]]; then
        mv "$lib.orig" "$lib"; echo "Restored bundled SDL: $lib"
    else
        echo "No $lib.orig (nothing to restore, or Steam already put the file back)."
    fi
    last=$(ls -1t "$DB".bak-* 2>/dev/null | head -1 || true)
    if [[ -n $last ]]; then
        cp -p "$last" "$DB"; echo "Restored $DB from $last"
    fi
    exit 0
fi

# 1. bundled SDL
if [[ -f $lib ]]; then
    have=$(sha256sum "$lib" | cut -d' ' -f1)
    if [[ $have != "$ORIG_SDL_SHA" ]]; then
        echo "Unknown version of $lib (game was updated?). Not touching it." >&2; exit 1
    fi
    mv -n "$lib" "$lib.orig"
    echo "Moved bundled SDL aside: $lib.orig"
elif [[ -f $lib.orig ]]; then
    echo "Bundled SDL already moved aside."
else
    echo "Warning: $lib not found at all." >&2
fi

# 2. usercontrollerdb.txt
if [[ -f $DB ]]; then
    bak=$DB.bak-$(date +%Y%m%d-%H%M%S)
    cp -p "$DB" "$bak"
    python3 -I - "$DB" <<'EOF'
import sys
path = sys.argv[1]
meta = ("platform:", "crc:", "hint:", "sdk")
# evdev X-input pads (xpad driver, Steam Input virtual pad): standard layout, verified in-game
X360 = ("a:b0,b:b1,x:b2,y:b3,back:b6,start:b7,guide:b8,leftshoulder:b4,rightshoulder:b5,"
        "leftstick:b9,rightstick:b10,dpup:h0.1,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,"
        "leftx:a0,lefty:a1,lefttrigger:a2,rightx:a3,righty:a4,righttrigger:a5,platform:Linux,")
XINPUT = {("045e", "028e"), ("28de", "11ff")}
def vidpid(guid):                             # SDL GUID: bus(2) crc(2) vid(2) 0 pid(2) ... little endian
    g = guid.lower()
    return (g[10:12] + g[8:10], g[18:20] + g[16:18]) if len(g) == 32 else None
out, dropped, filled, fixed = [], 0, 0, 0
for line in open(path, encoding="utf-8").read().splitlines():
    f = line.split(",")
    if len(f) < 3 or line.startswith("#"):
        out.append(line); continue
    rest = ",".join(f[2:])
    if "platform:Linuxa:" in rest:           # glued "platform:Linux" + "a:b0"
        rest = rest.replace("platform:Linuxa:", "a:"); fixed += 1
    binds = [x for x in rest.split(",") if x and not x.startswith(meta)]
    if not binds:                             # e.g. "crc:b881,platform:Linux,platform:Linux,"
        if vidpid(f[0]) in XINPUT:
            crc = [x for x in rest.split(",") if x.startswith("crc:")]
            rest = (crc[0] + "," if crc else "") + X360; filled += 1
        else:
            dropped += 1; continue            # let SDL's built-in mapping apply
    out.append(",".join(f[:2] + [rest]))
open(path, "w", encoding="utf-8").write("\n".join(out) + "\n")
print(f"usercontrollerdb.txt: filled {filled} empty X-input mapping(s), removed {dropped} other empty one(s), "
      f"fixed {fixed} glued one(s)")
EOF
    echo "Backup: $bak"
else
    echo "No $DB yet (game never saved mappings), nothing to repair."
fi

cat <<'EOT'

Done. For a Steam Controller also set in Steam > Move or Die > Properties:
  Controller:     Disable Steam Input
  Launch Options: SDL_JOYSTICK_HIDAPI_STEAM=1 SDL_GAMECONTROLLER_IGNORE_DEVICES= %command%
Avoid the in-game "controller mapping" screen, it writes broken mappings again
(just run ./fix.sh again if it happens).
EOT
