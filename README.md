# StatMenu

A lightweight system monitor for the macOS menu bar, in the spirit of iStat Menus. Native Swift and SwiftUI, about 2% CPU while running.

## Features

- **CPU**: usage history, per-core load (efficiency/performance cores read from the device tree), clock speed per cluster against its maximum, power draw, top processes, load average, uptime
- **GPU**: utilization (device, renderer, tiler), clock speed, power draw, memory in use, temperature
- **Memory**: pressure, composition (app, wired, compressed, cached, free), swap, page-in/out and swap-in/out rates, top processes
- **Disks**: volume capacity, per-disk read/write rates, top processes by disk activity
- **Network**: upload/download rates, Wi-Fi details (signal, noise, SNR, channel, link rate, standard, security), daily and monthly data usage
- **Sensors**: temperatures, fan speeds, system power with a breakdown (CPU, GPU, Neural Engine, memory, rest of chip, rest of system)
- **Battery**: charge, health, cycles, power draw, and charge rate against the adapter's rating
- **History**: every value has a hover graph with min/average/max; charts switch between 2 minutes, 1 hour, 24 hours and 7 days, with long-term history saved across restarts
- One combined menu bar item (fits beside the notch) or separate items per module
- Launch at login, light and dark mode, °C/°F

## Requirements

- macOS 14 Sonoma or later
- Apple Silicon (clock speeds and power readings use Apple Silicon reporting)
- Xcode Command Line Tools

## Build and install

```bash
./scripts/build.sh            # builds build/StatMenu.app
./scripts/build.sh --install  # also copies it to /Applications and launches it
```

The app is ad-hoc signed. On another Mac, Gatekeeper will block the first launch; right-click the app and choose Open, or run `xattr -dr com.apple.quarantine /Applications/StatMenu.app`.

## Notes

- Clock speeds, power, and some temperatures come from undocumented macOS interfaces (IOReport, SMC, IOHID), the same approach used by other open-source monitors. They may change between macOS releases.
- Sensor names are shown only where their meaning is widely agreed; everything else is listed under the name the hardware reports.
- The Wi-Fi network name requires Location access (a macOS rule). StatMenu never reads your location.
- Data usage only counts traffic while StatMenu is running.
