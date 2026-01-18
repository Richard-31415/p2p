#!/bin/bash
# WiFi Setup Script for Raspberry Pi P2P Chat
# Device A creates hotspot, Device B connects to it
# Run with sudo: sudo ./setup_adhoc.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.json"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root: sudo $0"
    exit 1
fi

# Read config
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: config.json not found"
    exit 1
fi

DEVICE=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['device'].upper())")
INTERFACE=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('interface', 'wlan0'))")

if [ "$DEVICE" == "A" ]; then
    IP="192.168.4.1"
elif [ "$DEVICE" == "B" ]; then
    IP="192.168.4.2"
else
    echo "Error: Invalid device in config"
    exit 1
fi

SSID="PI_P2P_NETWORK"
PASSWORD="p2pchat123"

echo "========================================"
echo "  P2P WiFi Setup for Device $DEVICE"
echo "========================================"
echo "Interface: $INTERFACE"
echo "SSID: $SSID"
echo "Password: $PASSWORD"
echo ""

if [ "$DEVICE" == "A" ]; then
    echo "[Device A - Creating Hotspot]"
    echo ""

    # Install hostapd and dnsmasq if not present
    if ! command -v hostapd &> /dev/null; then
        echo "[Installing hostapd...]"
        apt-get update && apt-get install -y hostapd
    fi

    if ! command -v dnsmasq &> /dev/null; then
        echo "[Installing dnsmasq...]"
        apt-get install -y dnsmasq
    fi

    # Stop services
    echo "[1/6] Stopping services..."
    systemctl stop hostapd 2>/dev/null || true
    systemctl stop dnsmasq 2>/dev/null || true
    systemctl stop wpa_supplicant 2>/dev/null || true
    nmcli device disconnect $INTERFACE 2>/dev/null || true
    nmcli radio wifi off 2>/dev/null || true
    rfkill unblock wifi 2>/dev/null || true

    # Configure interface
    echo "[2/6] Configuring interface..."
    ip link set $INTERFACE down
    ip addr flush dev $INTERFACE
    ip link set $INTERFACE up
    ip addr add $IP/24 dev $INTERFACE

    # Create hostapd config
    echo "[3/6] Creating hostapd config..."
    cat > /tmp/hostapd.conf << EOF
interface=$INTERFACE
driver=nl80211
ssid=$SSID
hw_mode=g
channel=6
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$PASSWORD
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

    # Create dnsmasq config for DHCP
    echo "[4/6] Creating dnsmasq config..."
    cat > /tmp/dnsmasq.conf << EOF
interface=$INTERFACE
dhcp-range=192.168.4.2,192.168.4.20,255.255.255.0,24h
bind-interfaces
EOF

    # Start dnsmasq
    echo "[5/6] Starting DHCP server..."
    dnsmasq -C /tmp/dnsmasq.conf &
    sleep 1

    # Start hostapd
    echo "[6/6] Starting hotspot..."
    hostapd /tmp/hostapd.conf &
    sleep 2

    echo ""
    echo "========================================"
    echo "  Hotspot Active!"
    echo "========================================"
    echo "Device: A (Hotspot)"
    echo "Interface: $INTERFACE"
    echo "IP: $IP"
    echo "SSID: $SSID"
    echo "Password: $PASSWORD"
    echo ""
    echo "Device B should connect to this WiFi network."
    echo "Then run: python3 master.py"
    echo ""

elif [ "$DEVICE" == "B" ]; then
    echo "[Device B - Connecting to Hotspot]"
    echo ""

    # Stop interfering services
    echo "[1/3] Preparing interface..."
    systemctl stop wpa_supplicant 2>/dev/null || true
    nmcli device disconnect $INTERFACE 2>/dev/null || true

    # Connect using wpa_supplicant
    echo "[2/3] Connecting to $SSID..."

    cat > /tmp/wpa_supplicant.conf << EOF
network={
    ssid="$SSID"
    psk="$PASSWORD"
}
EOF

    ip link set $INTERFACE up
    wpa_supplicant -B -i $INTERFACE -c /tmp/wpa_supplicant.conf
    sleep 3

    # Get IP via DHCP or set static
    echo "[3/3] Getting IP address..."
    dhclient $INTERFACE 2>/dev/null || ip addr add $IP/24 dev $INTERFACE

    sleep 2

    # Show status
    CURRENT_IP=$(ip addr show $INTERFACE | grep "inet " | awk '{print $2}' | cut -d/ -f1)

    echo ""
    echo "========================================"
    echo "  Connected!"
    echo "========================================"
    echo "Device: B (Client)"
    echo "Interface: $INTERFACE"
    echo "IP: $CURRENT_IP"
    echo "Connected to: $SSID"
    echo ""
    echo "Run: python3 master.py"
    echo ""
fi
