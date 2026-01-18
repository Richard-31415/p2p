#!/bin/bash
# WiFi Setup Script for Raspberry Pi P2P Chat
# Device A creates hotspot, Device B connects to it
# Run with sudo: sudo ./setup_adhoc.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.json"

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root: sudo $0"
    exit 1
fi

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

SSID="PI_P2P_CHAT"
PASSWORD="p2pchat123"

echo "========================================"
echo "  P2P WiFi Setup - Device $DEVICE"
echo "========================================"
echo "Interface: $INTERFACE"
echo "SSID: $SSID"
echo "Password: $PASSWORD"
echo ""

if [ "$DEVICE" == "A" ]; then
    echo "[Device A - Creating Hotspot]"
    echo ""

    # Check/install dependencies
    if ! command -v hostapd &> /dev/null; then
        echo "[Installing hostapd...]"
        apt-get update && apt-get install -y hostapd
    fi
    if ! command -v dnsmasq &> /dev/null; then
        echo "[Installing dnsmasq...]"
        apt-get install -y dnsmasq
    fi

    # Stop everything and block NetworkManager
    echo "[1/5] Stopping services..."
    systemctl stop hostapd 2>/dev/null || true
    systemctl stop dnsmasq 2>/dev/null || true
    systemctl stop wpa_supplicant 2>/dev/null || true
    killall hostapd 2>/dev/null || true
    killall dnsmasq 2>/dev/null || true
    killall wpa_supplicant 2>/dev/null || true

    # Tell NetworkManager to leave this interface alone
    nmcli device set $INTERFACE managed no 2>/dev/null || true
    nmcli device disconnect $INTERFACE 2>/dev/null || true

    # Configure interface
    echo "[2/5] Configuring interface..."
    ip link set $INTERFACE down
    ip addr flush dev $INTERFACE
    ip link set $INTERFACE up
    ip addr add $IP/24 dev $INTERFACE

    # hostapd config
    echo "[3/5] Creating hotspot config..."
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

    # dnsmasq config
    cat > /tmp/dnsmasq.conf << EOF
interface=$INTERFACE
bind-interfaces
dhcp-range=192.168.4.2,192.168.4.20,255.255.255.0,24h
EOF

    # Start services
    echo "[4/5] Starting DHCP server..."
    dnsmasq -C /tmp/dnsmasq.conf

    echo "[5/5] Starting hotspot..."
    hostapd /tmp/hostapd.conf -B
    sleep 2

    echo ""
    echo "========================================"
    echo "  Hotspot Active!"
    echo "========================================"
    echo "SSID: $SSID"
    echo "Password: $PASSWORD"
    echo "IP: $IP"
    echo ""
    echo "Interface status:"
    iwconfig $INTERFACE 2>/dev/null | head -3
    echo ""
    echo "Now run on Device B: sudo ./setup_adhoc.sh"
    echo "Then on both: python3 master.py"
    echo ""

elif [ "$DEVICE" == "B" ]; then
    echo "[Device B - Connecting to Hotspot]"
    echo ""

    # Stop interfering services
    echo "[1/4] Stopping services..."
    killall wpa_supplicant 2>/dev/null || true
    nmcli device disconnect $INTERFACE 2>/dev/null || true

    # Create wpa_supplicant config
    echo "[2/4] Creating connection config..."
    cat > /tmp/wpa_p2p.conf << EOF
ctrl_interface=/var/run/wpa_supplicant
network={
    ssid="$SSID"
    psk="$PASSWORD"
    key_mgmt=WPA-PSK
}
EOF

    # Connect
    echo "[3/4] Connecting to $SSID..."
    ip link set $INTERFACE up
    wpa_supplicant -B -i $INTERFACE -c /tmp/wpa_p2p.conf
    sleep 3

    # Get IP
    echo "[4/4] Getting IP address..."
    dhclient -v $INTERFACE 2>&1 | head -5 || true
    sleep 2

    CURRENT_IP=$(ip addr show $INTERFACE | grep "inet " | awk '{print $2}' | cut -d/ -f1)

    echo ""
    echo "========================================"
    echo "  Connected to Hotspot!"
    echo "========================================"
    echo "Connected to: $SSID"
    echo "IP: $CURRENT_IP"
    echo ""
    echo "Now run: python3 master.py"
    echo ""
fi
