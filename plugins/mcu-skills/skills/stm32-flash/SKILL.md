---
name: stm32-flash
description: >
  This skill should be used when the user asks to flash, program, or upload firmware to an STM32
  device over UART, when testing STM32 firmware autonomously, when asked to "flash and verify" or
  "flash and test" an STM32 board, or when working with STM32WL targets (rak3172, russell) in a
  meshtastic-firmware PlatformIO project.
version: 1.1.0
---

# STM32 UART Flash & Verify Skill

Autonomous workflow for flashing STM32WL firmware over the UART bootloader and confirming the
device boots correctly. Covers the full sequence from environment checks through boot verification.

## Platform support

**macOS only.** This skill has only been tested on macOS. The port naming conventions (`cu.`/`tty.`
prefixes), lock file paths (`/private/tmp/LCK..`), and `lsof` usage are macOS-specific. It is not
expected to work on Windows without significant adaptation.

## Hardware context

- **Supported boards:** rak3172, russell (STM32WLE5CCU6)
- **Connection:** FT232R USB-UART adapter — only TX, RX, GND wired. No ST-Link, no NRST.
- **Bootloader:** STM32 system UART bootloader on USART2 (PA2/PA3).
- **BOOT0 on russell:** shared with the physical button (PH3). Hold button + power-cycle to enter
  bootloader when firmware is not running.

> **wio-e5 not supported for UART flashing.** The wio-e5 dev board's built-in USB-serial is wired
> to a UART that is **not** the STM32WL system UART bootloader port. The UART bootloader cannot be
> reached over the dev board USB connector. wio-e5 requires ST-Link/SWD for programming.

## Environment variables

| Variable              | Purpose                                       | Auto-discovered if unset?          |
|-----------------------|-----------------------------------------------|------------------------------------|
| `STM32_PROGRAMMER_CLI`| Full path to STM32CubeProgrammer CLI binary   | Yes — searched in standard macOS locations |
| `MESHTASTIC_PORT`     | Serial port (`tty.` form), e.g. `/dev/tty.usbserial-1234` | Yes — probed automatically (see Step 0) |

**macOS port rule:** all actual commands must substitute `cu.` for `tty.`:
`${MESHTASTIC_PORT/tty./cu.}`. STM32CubeProgrammer requires `cu.`; the meshtastic CLI returns
EBUSY on `tty.` immediately after the programmer releases the port.

## Step 0 — Resolve environment

```sh
# 1. Find STM32CubeProgrammer if not set
if [ -z "$STM32_PROGRAMMER_CLI" ]; then
  STM32_PROGRAMMER_CLI=$(find /Applications -name "STM32_Programmer_CLI" -path "*/Resources/bin/*" 2>/dev/null | head -1)
fi
[ -z "$STM32_PROGRAMMER_CLI" ] && echo "ERROR: STM32_Programmer_CLI not found" && exit 1
echo "Programmer: $STM32_PROGRAMMER_CLI"

# 2. Find and probe serial port if not set
if [ -z "$MESHTASTIC_PORT" ]; then
  MESHTASTIC_PORT=$(find_meshtastic_port)   # see port-probe logic below
fi
[ -z "$MESHTASTIC_PORT" ] && echo "ERROR: no device found" && exit 1
echo "Port: $MESHTASTIC_PORT"
```

### Port probe logic

When `MESHTASTIC_PORT` is not set, enumerate all USB serial ports and probe each one with a 10-
second timeout, trying two tests in order:

1. **Meshtastic firmware check** — connect with `meshtastic --port <cu.port>` and check for
   `Connected to radio` in the output within 10 s. If found, this port has running firmware.
2. **UART bootloader check** — probe with STM32CubeProgrammer `-info` within 10 s and check for
   `Activating device: OK`. If found, this port has a device in bootloader mode.

Accept the first port that passes either check. If no port passes either check, report all ports
tried and their outcomes, then abort.

```sh
# Enumerate candidates
CANDIDATES=$(ls /dev/tty.usbserial-* /dev/tty.usbmodem* 2>/dev/null)
if [ -z "$CANDIDATES" ]; then echo "ERROR: no USB serial ports found"; exit 1; fi

MESHTASTIC_PORT=""
for PORT in $CANDIDATES; do
  CU_PORT="${PORT/tty./cu.}"
  echo "Probing $PORT ..."

  # Test 1: meshtastic firmware
  if timeout 10 meshtastic --port "$CU_PORT" 2>&1 | grep -q "Connected to radio"; then
    echo "  → meshtastic firmware detected"
    MESHTASTIC_PORT="$PORT"; break
  fi

  # Test 2: UART bootloader
  if "$STM32_PROGRAMMER_CLI" -c port="$CU_PORT" br=115200 -info 2>&1 | grep -q "Activating device: OK"; then
    echo "  → STM32 UART bootloader detected"
    MESHTASTIC_PORT="$PORT"; break
  fi

  echo "  → no response (not a target device, or device off)"
done
```

## Step 1 — Clear stale processes and lock files

**Do this before every flash attempt.** A previous `meshtastic` or `STM32_Programmer_CLI`
invocation left running in the background will silently hold the port; STM32CubeProgrammer will
hang after printing its header banner with no error.

```sh
PIDS=$(lsof 2>/dev/null | grep "$(basename $MESHTASTIC_PORT | sed 's/tty\./cu./')" | awk '{print $2}' | sort -u)
[ -n "$PIDS" ] && kill $PIDS 2>/dev/null
rm -f /private/tmp/LCK..cu.usbserial-* /private/tmp/LCK..tty.usbserial-*
```

Diagnosis: if STM32CubeProgrammer connects successfully it will print
`Serial Port /dev/cu.usbserial-... is successfully opened.` within ~1 second. If you see only the
banner header and nothing else, there is still a process or lock file blocking the port.

## Step 2 — Enter bootloader

Two paths — try software first; fall back to hardware if the device has no running firmware.

### Software path (firmware already running)

```sh
meshtastic --port "${MESHTASTIC_PORT/tty./cu.}" --enter-dfu
```

Wait for the CLI to print a success message before proceeding. If it hangs, the device is not
running meshtastic firmware — use the hardware path.

### Hardware path (blank, bricked, or unresponsive)

1. Hold the **BOOT0 button** on the board (on russell: the physical button, PH3 = BOOT0)
2. Cycle power (unplug/replug USB)
3. Release the button

Confirm bootloader is active before flashing:

```sh
"$STM32_PROGRAMMER_CLI" -c port="${MESHTASTIC_PORT/tty./cu.}" br=115200 -info 2>&1 | grep -E "Activating|Chip|Device name"
```

- `Activating device: OK` → proceed
- `Activating device: KO` → device is not in bootloader mode; repeat Step 2
- `Cannot open port` → repeat Step 1 (stale lock)

## Step 3 — Flash and verify

PlatformIO writes `.hex` files to `.pio/build/<env>/`. Locate the latest and flash over UART.
`-v` verifies; `-g 0x08000000` issues the UART bootloader GO command to jump to the application
without requiring a power cycle.

```sh
ENV=russell   # or rak3172
HEX=$(ls -t .pio/build/${ENV}/firmware-${ENV}-*.hex 2>/dev/null | head -1)
if [ -z "$HEX" ]; then echo "ERROR: no hex found for env $ENV"; exit 1; fi
echo "Flashing: $HEX"
"$STM32_PROGRAMMER_CLI" -c port="${MESHTASTIC_PORT/tty./cu.}" br=115200 -w "$HEX" -v -g 0x08000000 2>&1
```

Expected successful completion output:
```
Download verified successfully
RUNNING Program ...
  Address:      : 0x8000000
Start operation achieved successfully
```

If `Start operation achieved successfully` is not present, the flash or verify failed — do not
proceed to Step 4.

## Step 4 — Verify boot

Allow ~3 seconds for the firmware to initialise, then query the device:

```sh
meshtastic --port "${MESHTASTIC_PORT/tty./cu.}" --info 2>&1
```

A healthy device responds with JSON node info. Key fields to confirm:

| Field              | Expected value                          |
|--------------------|-----------------------------------------|
| `pioEnv`           | Matches `$ENV` (e.g. `"russell"`)       |
| `firmwareVersion`  | Matches the build (e.g. `"2.7.23.abc"`) |
| `rebootCount`      | `0` on first clean boot                 |

If the command hangs, the device has not booted — check for a crash loop on the raw UART:

```sh
python -m serial.tools.miniterm "${MESHTASTIC_PORT/tty./cu.}" 115200
# exit: Ctrl-A Ctrl-\
```

## Expected first-boot sequence after a format-break LittleFS update

When `block_size` or `block_count` changed (as in `feat/stm32-lfs-cleanup`), the on-disk
superblock will not match and LittleFS will reformat on first mount. This is normal.

Look for on the raw UART:
1. `[LittleFS] Formatting...` then `[LittleFS] Mounted` — expected, not an error
2. `[NodeDB] Loading...` followed by node lines — config rebuilt from scratch
3. No reboot loop — a loop within the first 10 s indicates a hard fault; capture the panic address
   before reflashing

## Failure recovery

| Symptom | Cause | Fix |
|---------|-------|-----|
| No ports found in Step 0 | No USB serial adapters connected | Connect the device |
| All ports time out in Step 0 | Device off, wrong board, or wio-e5 (unsupported) | Power on device; check it is rak3172 or russell |
| Programmer hangs after header banner | Stale process/lock | Step 1 |
| `Activating device: KO` | Device not in bootloader | Repeat Step 2 |
| `Cannot open port` | Lock file from previous run | `rm -f /private/tmp/LCK..cu.usbserial-*` |
| `meshtastic --info` EBUSY | Using `tty.` instead of `cu.` | Use `${MESHTASTIC_PORT/tty./cu.}` |
| `meshtastic --info` hangs | Device crashed or not booted | Check raw UART for panic |
| Flash succeeds but GO fails | Should not happen with `-g 0x08000000`; if it does, power-cycle | |
