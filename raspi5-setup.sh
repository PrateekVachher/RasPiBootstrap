#!/bin/bash
# Raspberry Pi 5 Setup Script
# Run as: sudo bash raspi5-setup.sh
VERSION="1.0.0"

set -e

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root: sudo bash raspi5-setup.sh"
  exit 1
fi

echo "========================================="
echo " Raspberry Pi 5 Setup Script v${VERSION}"
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
if command -v btop &>/dev/null; then
  echo "btop already installed, skipping."
else
  apt install -y btop
fi

# --- 7. Install Latest Node.js (LTS via NodeSource) ---
echo "[7/12] Installing latest Node.js LTS..."
if command -v node &>/dev/null; then
  echo "Node.js already installed ($(node --version)), skipping."
else
  apt remove -y nodejs npm 2>/dev/null || true
  curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
  apt install -y nodejs
fi
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
if command -v docker &>/dev/null; then
  echo "Docker already installed, skipping install."
else
  curl -fsSL https://get.docker.com | bash
fi
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

INSTALL_OPENCLAW=false
INSTALL_HA=false

while true; do
  read -p "Enter your choice (1/2/3): " INSTALL_CHOICE
  case "$INSTALL_CHOICE" in
    1) INSTALL_OPENCLAW=true; break ;;
    2) INSTALL_HA=true; break ;;
    3) INSTALL_OPENCLAW=true; INSTALL_HA=true; break ;;
    *) echo "Invalid choice. Please enter 1, 2, or 3." ;;
  esac
done

if [ "$INSTALL_HA" = true ]; then
  if docker ps -a --format '{{.Names}}' | grep -q '^homeassistant$'; then
    echo "Home Assistant container already exists, skipping."
  else
    echo "Installing Home Assistant via Docker..."

    # Pre-create config directory and configure trusted proxies for Cloudflare Tunnel
    HA_CONFIG_DIR="${SUDO_USER:+/home/$SUDO_USER}/homeassistant"
    HA_CONFIG_DIR="${HA_CONFIG_DIR:-~/homeassistant}"
    mkdir -p "$HA_CONFIG_DIR"
    if [ ! -f "$HA_CONFIG_DIR/configuration.yaml" ]; then
      cat > "$HA_CONFIG_DIR/configuration.yaml" <<EOF
# Home Assistant configuration
default_config:

homeassistant:
  external_url: "https://ha.prateekv.dev"
  internal_url: "http://pipi.local:8123"

http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 172.16.0.0/12
    - 127.0.0.1
    - ::1
EOF
    fi

    docker run -d \
      --name homeassistant \
      --restart=unless-stopped \
      --privileged \
      --network=host \
      -v "$HA_CONFIG_DIR":/config \
      -v /run/dbus:/run/dbus:ro \
      -e TZ=America/Los_Angeles \
      ghcr.io/home-assistant/home-assistant:stable
  fi
  echo "Home Assistant is running:"
  echo "  Local:    http://pipi.local:8123"
  echo "  External: https://ha.prateekv.dev (via Cloudflare Tunnel)"
fi

if [ "$INSTALL_OPENCLAW" = true ]; then
  echo "OpenClaw selected — set it up via Docker after reboot."
fi

# --- 11. Install Cloudflared ---
echo "[11/12] Installing cloudflared..."
if command -v cloudflared &>/dev/null; then
  echo "cloudflared already installed, skipping."
else
  mkdir -p --mode=0755 /usr/share/keyrings
  curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null
  echo 'deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main' | tee /etc/apt/sources.list.d/cloudflared.list
  apt update -y && apt install -y cloudflared
fi
echo "cloudflared version: $(cloudflared --version)"

# --- 12. Install Homebrew ---
echo "[12/12] Installing Homebrew..."
BREW_USER="${SUDO_USER:-pi}"
if su - "$BREW_USER" -c 'command -v brew' &>/dev/null; then
  echo "Homebrew already installed, skipping."
else
  apt install -y build-essential
  su - "$BREW_USER" -c 'NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  # Add Homebrew to the user's PATH
  BREW_HOME="/home/$BREW_USER"
  su - "$BREW_USER" -c "echo >> $BREW_HOME/.bashrc"
  su - "$BREW_USER" -c "echo 'eval \"\$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)\"' >> $BREW_HOME/.bashrc"
  su - "$BREW_USER" -c 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)" && brew install gcc'
fi
echo "Homebrew installed for user $BREW_USER"

echo ""
echo "========================================="
echo " Setup Complete!"
echo "========================================="
echo ""
echo " Overclock: arm_freq=3000, gpu_freq=1000, over_voltage_delta=50000"
echo " CPU Governor: performance (persistent)"
echo " Fan: full speed (persistent)"
echo " Installed: btop, Node.js $(node --version), Docker, Homebrew, cloudflared"
echo " Removed: Firefox, LibreOffice, bloatware"
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
