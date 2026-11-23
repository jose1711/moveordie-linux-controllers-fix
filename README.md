# Move or Die on Linux – only one gamepad works

[Slovenská verzia nižšie](#slovensky)

## Symptoms

- [Move or Die](https://store.steampowered.com/app/323850/Move_or_Die/) (Steam appid 323850,
  native Linux build, buildid 15175566) only reacts to one gamepad, although several are connected.
- Gamepads connected after the game was started are never picked up.
- Bluetooth pads (e.g. 8BitDo SN30 Pro in X-input mode) don't work at all on a desktop with
  many input devices.
- After replacing the SDL library (see below) some pads (a wireless Xbox 360 clone, the
  Steam Input virtual pad) react in the in-game *controller mapping* screen, but **can't join
  in the character select screen**.

## Cause

1. **Old bundled SDL2.** The game ships its own `Love/linux32/libSDL2-2.0.so.0` (LÖVE 0.9,
   SDL 2.0.x built without udev). Without udev this SDL only scans `/dev/input/event0` …
   `event31` and has no hotplug. On a desktop with keyboards, mice, audio jacks, virtual devices
   (ydotool, keymapper, …) these 32 slots are taken, newer pads get `event256+` and the game
   never sees them.

   `SDL_JOYSTICK_DEVICE=/dev/input/eventNNN` makes the joystick part open them, but the game then
   **crashes** (SIGSEGV in `SDL_SYS_HapticOpenFromJoystick`): the haptic subsystem has the same
   32-device limit. Don't use it.

2. **Broken mappings written by the game.** The game keeps its own gamepad mappings in
   `~/.local/share/love/Move Or Die/usercontrollerdb.txt`. With newer SDL, GUIDs carry a CRC
   and SDL's mapping strings contain a `crc:` field. The game mangles those when saving:

   ```
   030081b85e0400008e02000073050000,Xbox 360 Controller,crc:b881,platform:Linux,platform:Linux,
   0300d6405e040000e002000000006800,Xbox One S Controller,crc:40d6,platform:Linuxa:b0,b:b1,...
   ```

   The first entry has **no buttons at all** – that pad can't join. The in-game mapping screen
   reads raw buttons, which is why the pad seems to "work" there.

3. **Steam Controller via Steam Input.** The virtual pad created by Steam Input
   (`28de:11ff`) suffers from (2) too. Letting SDL talk to the controller directly (HIDAPI)
   avoids it.

## Fix

```sh
git clone https://github.com/jose1711/moveordie-linux-controllers-fix
cd moveordie-linux-controllers-fix
./fix.sh                        # auto-detects the game in your Steam libraries
./fix.sh "/path/to/steamapps/common/Move or Die"
./fix.sh --restore              # put the bundled SDL and the last mappings backup back
```

The script

- moves the bundled SDL to `libSDL2-2.0.so.0.orig` (only the exact known file,
  sha256 `61bd049e…21adb2`). The game then loads SDL 2.32 from the Steam Linux Runtime
  (`/usr/lib/i386-linux-gnu/libSDL2-2.0.so.0` inside the container) – with udev-less hotplug,
  HIDAPI drivers and no 32-device limit;
- repairs `usercontrollerdb.txt`, keeping a timestamped backup: empty entries of X-input pads
  (`045e:028e` – xpad and its clones, `28de:11ff` – Steam Input virtual pad) get the standard
  Xbox 360 layout, other empty entries are removed (SDL's built-in mapping applies), glued
  `platform:Linuxa:b0` entries are fixed.

Then, in Steam → Move or Die → Properties:

- **Controller:** *Disable Steam Input* (only needed for a Steam Controller)
- **Launch Options:**

  ```
  SDL_JOYSTICK_HIDAPI_STEAM=1 SDL_GAMECONTROLLER_IGNORE_DEVICES= %command%
  ```

  `SDL_JOYSTICK_HIDAPI_STEAM=1` lets SDL drive the Steam Controller directly,
  `SDL_GAMECONTROLLER_IGNORE_DEVICES=` clears the list Steam sets, which hides the real
  Steam Controller (`0x28de/0x1106`).

  If some non-gamepad device shows up as a joystick (e.g. the ErgoDox EZ "System Control"
  interface, `3297:4975`), hide it with `SDL_JOYSTICK_BLACKLIST_DEVICES=0x3297/0x4975`
  (comma-separated `0xVID/0xPID` list). `SDL_GAMECONTROLLER_IGNORE_DEVICES` doesn't hide plain
  joysticks.

Notes:

- **Don't use the in-game controller mapping screen**, it writes broken entries again. If it
  happens, quit the game and run `./fix.sh` again.
- **A game update or *Verify integrity of game files* restores the bundled SDL** – run
  `./fix.sh` again.
- Tested with 2× 8BitDo SN30 Pro (Bluetooth, X-input), Steam Controller (BLE) and SPEEDLINK
  TORID (X-input receiver, `045e:028e`) at the same time, Steam Linux Runtime soldier
  2.0.20261021, Arch Linux.

No game files are distributed in this repository.

## Debugging tips

- What the game has open: `ls -l /proc/$(pgrep -x lt-love)/fd | grep -E 'input|hidraw'`
- Which SDL it loaded: `grep -o '/[^ ]*libSDL2[^ ]*' /proc/$(pgrep -x lt-love)/maps | sort -u`
- Game log: Steam console output, look for `assigned input N to slot M` and `Saving mapping`.

---

<a name="slovensky"></a>
## Slovensky

**Problém:** v Move or Die (Steam, natívna linuxová verzia) funguje len jeden gamepad. Pady
pripojené počas hry hra nevidí, Bluetooth pady nefungujú vôbec. Po výmene SDL niektoré pady
reagujú v mapovaní ovládania, ale na výbere hráča sa pridať nedajú.

**Príčina:**
- Hra má pribalené staré SDL2 bez udev. To vidí len `/dev/input/event0` až `event31` a nemá
  hotplug. Na bežnom desktope sú tieto čísla obsadené, takže novšie pady (`event256+`) hra
  nevidí. `SDL_JOYSTICK_DEVICE` nepomôže, hra potom spadne v haptike (tá má rovnaký limit).
- Hra si ukladá vlastné mapovania do `~/.local/share/love/Move Or Die/usercontrollerdb.txt`
  a s GUID novšieho SDL (pole `crc:`) ich zapíše pokazené, často úplne bez tlačidiel. Takýto
  pad sa na výbere hráča nepridá.
- Virtuálny pad Steam Input trpí tým istým, Steam Controller je lepšie pripojiť priamo cez
  HIDAPI.

**Riešenie:** `./fix.sh` odsunie pribalenú SDL (hra potom použije SDL 2.32 zo Steam Runtime)
a opraví `usercontrollerdb.txt` (so zálohou). V Steame vypni pre hru Steam Input a do Launch
Options daj `SDL_JOYSTICK_HIDAPI_STEAM=1 SDL_GAMECONTROLLER_IGNORE_DEVICES= %command%`.
Mapovanie ovládania v hre nepoužívaj. Po update hry alebo overení súborov v Steame spusti
skript znova. Návrat: `./fix.sh --restore`.
