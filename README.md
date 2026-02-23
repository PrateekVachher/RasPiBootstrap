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
9. **Caddy SSL reverse proxy** for local HTTPS access

## SSL Access

After setup, services are available over HTTPS:

| URL | Service |
|-----|---------|
| `https://pipi.local/ha` | Home Assistant |
| `https://pipi.local/openclaw` | OpenClaw |
| `https://<pi-ip>/ha` | Home Assistant (via local IP) |
| `https://<pi-ip>/openclaw` | OpenClaw (via local IP) |
| `https://208.52.2.131/ha` | Home Assistant (via public IP) |
| `https://208.52.2.131/openclaw` | OpenClaw (via public IP) |

> **Public IP access** requires port forwarding ports 80 and 443 on your router to the Pi's local IP.

Caddy uses internally-generated self-signed certificates (`tls internal`). On first visit, your browser will show a certificate warning — accept it to proceed. To avoid the warning, install the Caddy root CA on your client devices from `/var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt`.

### Adding more services

Edit `/etc/caddy/Caddyfile` and add a new `handle_path` block:

```
handle_path /myapp/* {
    reverse_proxy localhost:PORT
}
```

Then reload: `sudo systemctl reload caddy`