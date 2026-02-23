# RasPiBootstrap

Automated setup script for Raspberry Pi 5. Run with `sudo bash raspi5-setup.sh`.

## What it does

1. System updates & upgrades
2. Sets hostname to `pipi` (accessible as `pipi.local`)
3. Overclocking (arm_freq=3000, gpu_freq=1000)
4. CPU governor set to performance
5. Fan at full speed
6. Installs btop, Node.js LTS, Docker, Homebrew
7. Removes bloatware (Firefox, LibreOffice, etc.)
8. Optional: Home Assistant & OpenClaw via Docker

## Network Access

Services are exposed via [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/) on `prateekv.dev`.