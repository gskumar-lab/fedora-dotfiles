

#!/bin/bash

#if [[ $EUID -ne 0 ]]; then
#  echo "Run with sudo"
#  exit 1
#fi

ACTIVE_CONN=$(nmcli -t -f NAME connection show --active | head -n1)

if [[ -z "$ACTIVE_CONN" ]]; then
  echo "No active connection found"
  exit 1
fi

echo "Active connection: $ACTIVE_CONN"
echo
echo "1) Cloudflare"
echo "2) Google"
echo "3) Quad9"
echo "4) Reset to DHCP"

read -rp "Choice: " c

case $c in
  1) DNS="1.1.1.1 1.0.0.1" ;;
  2) DNS="8.8.8.8 8.8.4.4" ;;
  3) DNS="9.9.9.9 149.112.112.112" ;;
  4)
     nmcli con mod "$ACTIVE_CONN" ipv4.ignore-auto-dns no
     nmcli con mod "$ACTIVE_CONN" ipv4.dns ""
     nmcli con down "$ACTIVE_CONN"
     nmcli con up "$ACTIVE_CONN"
     echo "Restored DHCP DNS"
     exit 0
     ;;
  *) echo "Invalid"; exit 1 ;;
esac

nmcli con mod "$ACTIVE_CONN" ipv4.ignore-auto-dns yes
nmcli con mod "$ACTIVE_CONN" ipv4.dns "$DNS"
nmcli con down "$ACTIVE_CONN"
nmcli con up "$ACTIVE_CONN"

echo "DNS switched to $DNS"


