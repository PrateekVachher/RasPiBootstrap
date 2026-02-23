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
echo "[1/10] Updating and upgrading system..."
apt update -y && apt full-upgrade -y && apt dist-upgrade -y
apt autoremove -y && apt autoclean -y

# --- 2. Overclocking & Fan Config in /boot/firmware/config.txt ---
echo "[2/10] Applying overclock and fan settings to /boot/firmware/config.txt..."
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

# --- 3. Set CPU Governor to Performance ---
echo "[3/10] Setting CPU governor to performance..."
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

# --- 4. Fan to Full Speed ---
echo "[4/10] Setting fan to full speed..."
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

# --- 5. Install btop ---
echo "[5/10] Installing btop..."
apt install -y btop

# --- 6. Install Latest Node.js (LTS via NodeSource) ---
echo "[6/10] Installing latest Node.js LTS..."
apt remove -y nodejs npm 2>/dev/null || true
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
apt install -y nodejs
echo "Node.js version: $(node --version)"
echo "npm version: $(npm --version)"

# --- 7. Remove Bloatware & Firefox ---
echo "[7/10] Removing Firefox and unnecessary software..."
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

# --- 8. Install Docker ---
echo "[8/10] Installing Docker..."
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

# --- 9. Ask what to install via Docker ---
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

# --- 10. Install Homebrew ---
echo "[10/10] Installing Homebrew..."
BREW_USER="${SUDO_USER:-pi}"
apt install -y build-essential
su - "$BREW_USER" -c 'NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
# Add Homebrew to the user's PATH
BREW_HOME="/home/$BREW_USER"
su - "$BREW_USER" -c "echo >> $BREW_HOME/.bashrc"
su - "$BREW_USER" -c "echo 'eval \"\$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)\"' >> $BREW_HOME/.bashrc"
su - "$BREW_USER" -c 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)" && brew install gcc'
echo "Homebrew installed for user $BREW_USER"

echo ""
echo "========================================="
echo " Setup Complete!"
echo "========================================="
echo ""
echo " Overclock: arm_freq=3000, gpu_freq=1000, over_voltage_delta=50000"
echo " CPU Governor: performance (persistent)"
echo " Fan: full speed (persistent)"
echo " Installed: btop, Node.js $(node --version), Docker, Homebrew"
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
