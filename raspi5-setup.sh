#!/bin/bash
# Raspberry Pi 5 Setup Script
# Run as: sudo bash raspi5-setup.sh

set -e

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root: sudo bash raspi5-setup.sh"
  exit 1
fi

echo "========================================="
echo " Raspberry Pi 5 Setup Script"
echo "========================================="

# --- 1. System Updates & Upgrades ---
echo "[1/12] Updating and upgrading system..."
apt update -y && apt -y -o Dpkg::Options::="--force-confnew" full-upgrade && apt -y -o Dpkg::Options::="--force-confnew" dist-upgrade
apt autoremove -y && apt autoclean -y

# --- 2. Set Hostname ---
echo "[2/12] Setting hostname to pipi..."
hostnamectl set-hostname pipi
sed -i 's/127\.0\.1\.1.*/127.0.1.1\tpipi/' /etc/hosts
echo "Hostname set to pipi (accessible as pipi.local on the network)"

# --- 3. Overclocking & Fan Config in /boot/firmware/config.txt ---
echo "[3/12] Applying overclock and fan settings to /boot/firmware/config.txt..."
CONFIG="/boot/firmware/config.txt"

# Remove existing overclock lines to avoid duplicates
sed -i '/^arm_freq=/d' "$CONFIG"
sed -i '/^gpu_freq=/d' "$CONFIG"
sed -i '/^over_voltage_delta=/d' "$CONFIG"

# Append overclock settings
cat >> "$CONFIG" <<EOF

# --- Overclock Settings ---
arm_freq=3000
gpu_freq=1000
over_voltage_delta=50000
EOF

echo "Overclock settings written to $CONFIG"

# --- 4. Set CPU Governor to Performance ---
echo "[4/12] Setting CPU governor to performance..."
echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Make it persistent across reboots
cat > /etc/systemd/system/cpu-performance.service <<EOF
[Unit]
Description=Set CPU governor to performance
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable cpu-performance.service

# --- 5. Fan to Full Speed ---
echo "[5/12] Setting fan to full speed..."
pinctrl FAN_PWM op dl

# Make fan setting persistent
cat > /etc/systemd/system/fan-full-speed.service <<EOF
[Unit]
Description=Set fan to full speed
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/bin/pinctrl FAN_PWM op dl
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable fan-full-speed.service

# --- 6. Install btop ---
echo "[6/12] Installing btop..."
apt install -y btop

# --- 7. Install Latest Node.js (LTS via NodeSource) ---
echo "[7/12] Installing latest Node.js LTS..."
apt remove -y nodejs npm 2>/dev/null || true
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
apt install -y nodejs
echo "Node.js version: $(node --version)"
echo "npm version: $(npm --version)"

# --- 8. Remove Bloatware & Firefox ---
echo "[8/12] Removing Firefox and unnecessary software..."
apt purge -y firefox-esr firefox 2>/dev/null || true
apt purge -y \
  libreoffice* \
  wolfram-engine \
  scratch* \
  minecraft-pi \
  sonic-pi \
  dillo \
  gpicview \
  penguinspuzzle \
  oracle-java8-jdk \
  openjdk-11-jdk \
  smartsim \
  claws-mail \
  galculator \
  bluej \
  greenfoot \
  geany \
  nuscratch \
  rpd-wallpaper \
  idle idle3 \
  python-games python3-games \
  piclone \
  debian-reference-en \
  dphys-swapfile \
  triggerhappy \
  xscreensaver \
  2>/dev/null || true

apt autoremove -y && apt autoclean -y

# --- 9. Install Docker ---
echo "[9/12] Installing Docker..."
curl -fsSL https://get.docker.com | bash
usermod -aG docker pi 2>/dev/null || true
# Add the current sudo user to docker group as well
if [ -n "$SUDO_USER" ]; then
  usermod -aG docker "$SUDO_USER"
fi
systemctl enable docker
systemctl start docker
echo "Docker version: $(docker --version)"

# Install Docker Compose plugin
apt install -y docker-compose-plugin 2>/dev/null || true
echo "Docker Compose version: $(docker compose version 2>/dev/null || echo 'not installed separately, included in Docker')"

# --- 10. Ask what to install via Docker ---
echo ""
echo "========================================="
echo " What would you like to install?"
echo "========================================="
echo "  1) OpenClaw only"
echo "  2) Home Assistant only"
echo "  3) Both OpenClaw and Home Assistant"
echo ""
read -p "Enter your choice (1/2/3): " INSTALL_CHOICE

INSTALL_OPENCLAW=false
INSTALL_HA=false

case "$INSTALL_CHOICE" in
  1) INSTALL_OPENCLAW=true ;;
  2) INSTALL_HA=true ;;
  3) INSTALL_OPENCLAW=true; INSTALL_HA=true ;;
  *) echo "Invalid choice. Skipping optional installs." ;;
esac

if [ "$INSTALL_HA" = true ]; then
  echo "Installing Home Assistant via Docker..."
  docker run -d \
    --name homeassistant \
    --restart=unless-stopped \
    --privileged \
    --network=host \
    -v ~/homeassistant:/config \
    -v /run/dbus:/run/dbus:ro \
    -e TZ=America/Los_Angeles \
    ghcr.io/home-assistant/home-assistant:stable
  echo "Home Assistant is running at http://<your-pi-ip>:8123"
fi

if [ "$INSTALL_OPENCLAW" = true ]; then
  echo "OpenClaw selected — set it up via Docker after reboot."
fi

# --- 11. Install Homebrew ---
echo "[11/12] Installing Homebrew..."
BREW_USER="${SUDO_USER:-pi}"
apt install -y build-essential
su - "$BREW_USER" -c 'NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
# Add Homebrew to the user's PATH
BREW_HOME="/home/$BREW_USER"
su - "$BREW_USER" -c "echo >> $BREW_HOME/.bashrc"
su - "$BREW_USER" -c "echo 'eval \"\$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)\"' >> $BREW_HOME/.bashrc"
su - "$BREW_USER" -c 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)" && brew install gcc'
echo "Homebrew installed for user $BREW_USER"

# --- 12. Install Caddy & Configure SSL Reverse Proxy ---
echo "[12/12] Installing Caddy and configuring SSL reverse proxy..."
apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt update -y
apt install -y caddy

# Detect the Pi's local IP address
PI_IP=$(hostname -I | awk '{print $1}')

# Create the Caddyfile with SSL reverse proxy
cat > /etc/caddy/Caddyfile <<EOF
{
	# Use internal self-signed certificates for local network
	local_certs
}

# Serve via pipi.local hostname
https://pipi.local {
	tls internal

	handle_path /ha/* {
		reverse_proxy localhost:8123
	}

	handle_path /openclaw/* {
		reverse_proxy localhost:18789
	}

	handle /cert {
		root * /var/www/caddy-ca
		rewrite * /root.crt
		file_server
		header Content-Disposition "attachment; filename=caddy-root.crt"
	}

	handle / {
		respond "pipi.local — Use /ha for Home Assistant, /openclaw for OpenClaw, /cert to download CA cert" 200
	}
}

# Serve via local IP address
https://${PI_IP} {
	tls internal

	handle_path /ha/* {
		reverse_proxy localhost:8123
	}

	handle_path /openclaw/* {
		reverse_proxy localhost:18789
	}

	handle / {
		respond "pipi — Use /ha for Home Assistant, /openclaw for OpenClaw" 200
	}
}

# Serve via public IP address (requires port forwarding 80/443 on router)
https://208.52.2.131 {
	tls internal

	handle_path /ha/* {
		reverse_proxy localhost:8123
	}

	handle_path /openclaw/* {
		reverse_proxy localhost:18789
	}

	handle / {
		respond "pipi (public) — Use /ha for Home Assistant, /openclaw for OpenClaw" 200
	}
}
EOF

# Also serve the CA cert over plain HTTP so it can be downloaded without SSL warnings
cat > /etc/caddy/Caddyfile.http <<EOF
http://pipi.local:80 {
	handle /cert {
		root * /var/www/caddy-ca
		rewrite * /root.crt
		file_server
		header Content-Disposition "attachment; filename=caddy-root.crt"
	}
	handle / {
		respond "Visit /cert to download the CA certificate" 200
	}
}
EOF

# Merge HTTP config into main Caddyfile
cat /etc/caddy/Caddyfile.http >> /etc/caddy/Caddyfile
rm /etc/caddy/Caddyfile.http

# Install the Caddy root CA into the system trust store so local clients trust it
caddy trust 2>/dev/null || true

# Export the CA cert so other devices can download and trust it
CADDY_CA_SRC="/var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt"
CADDY_CA_DST="/var/www/caddy-ca"
mkdir -p "$CADDY_CA_DST"
cp "$CADDY_CA_SRC" "$CADDY_CA_DST/root.crt" 2>/dev/null || true

systemctl enable caddy
systemctl restart caddy

# Wait for Caddy to generate the CA cert (first startup)
sleep 3
if [ ! -f "$CADDY_CA_DST/root.crt" ] && [ -f "$CADDY_CA_SRC" ]; then
  cp "$CADDY_CA_SRC" "$CADDY_CA_DST/root.crt"
fi
echo "Caddy SSL reverse proxy configured"
echo "  https://pipi.local/ha         -> Home Assistant (port 8123)"
echo "  https://pipi.local/openclaw   -> OpenClaw (port 18789)"
echo "  https://${PI_IP}/ha           -> Home Assistant (port 8123)"
echo "  https://${PI_IP}/openclaw     -> OpenClaw (port 18789)"
echo "  https://208.52.2.131/ha       -> Home Assistant (public IP)"
echo "  https://208.52.2.131/openclaw -> OpenClaw (public IP)"
echo "  NOTE: Public IP access requires port forwarding 80/443 on your router"

echo ""
echo "========================================="
echo " Setup Complete!"
echo "========================================="
echo ""
echo " Overclock: arm_freq=3000, gpu_freq=1000, over_voltage_delta=50000"
echo " CPU Governor: performance (persistent)"
echo " Fan: full speed (persistent)"
echo " Installed: btop, Node.js $(node --version), Docker, Homebrew, Caddy"
echo " Removed: Firefox, LibreOffice, bloatware"
echo " SSL: https://pipi.local/ha, https://pipi.local/openclaw"
echo ""
if [ "$INSTALL_OPENCLAW" = true ] && [ "$INSTALL_HA" = true ]; then
  echo " Installed: OpenClaw (pending setup), Home Assistant (running)"
elif [ "$INSTALL_OPENCLAW" = true ]; then
  echo " Installed: OpenClaw (pending setup)"
elif [ "$INSTALL_HA" = true ]; then
  echo " Installed: Home Assistant (running)"
fi
echo ""
echo " >>> REBOOT REQUIRED for overclock settings <<<"
echo ""
read -p "Reboot now? (y/n): " REBOOT
if [ "$REBOOT" = "y" ] || [ "$REBOOT" = "Y" ]; then
  reboot
fi
