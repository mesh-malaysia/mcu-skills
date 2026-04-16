# mcu-skills

Claude Code plugin providing skills for autonomous MCU firmware development, flashing, and testing.

## Skills

### `stm32-flash`

Full autonomous workflow for flashing STM32WL firmware over the UART bootloader and verifying boot.

Covers:
- Auto-discovery of `STM32_Programmer_CLI` and serial port
- Clearing stale processes and macOS serial lock files
- Entering the STM32 UART bootloader (software via `meshtastic --enter-dfu` or hardware via BOOT0 button)
- Flashing, verifying, and jumping to the application (`-w -v -g 0x08000000`)
- Boot verification via `meshtastic --info`
- Failure recovery table for every known failure mode

**Trigger phrases:** "flash the STM32", "flash and test", "flash and verify", "autonomous testing", working with rak3172 / russell / wio-e5 targets in a meshtastic-firmware PlatformIO project.

## Installation

```sh
/plugin install mcu-skills@local --path ~/Development/mcu-skills
```

Or add to your project's `.claude/settings.json` plugins list.

## Hardware context

Initially built for the [Meshtastic Malaysia](https://github.com/Meshtastic-Malaysia) STM32WL board family:

| Board | MCU | Flash path | BOOT0 |
|-------|-----|-----------|-------|
| rak3172 | STM32WLE5CCU6 | UART bootloader via FT232R | Hardware pin |
| russell | STM32WLE5CCU6 | UART bootloader via FT232R | Shared with physical button (PH3) |
| wio-e5 | STM32WLE5JC | UART bootloader via FT232R | Hardware pin |

All boards: TX/RX/GND only — no ST-Link, no NRST wired.
