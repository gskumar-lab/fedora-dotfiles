#!/usr/bin/env bash

set -e

SERVICES=(
  "nvidia-persistenced.service"
  "nvidia-powerd.service"
  "switcheroo-control.service"
)

enable_services() {
  echo "🔄 Enabling NVIDIA-related services (current session + boot)..."
  echo ""
  echo "⏱️ Nvidia gpu should be enabled in boot..."
  for svc in "${SERVICES[@]}"; do
    sudo systemctl enable --now "$svc"
    echo "✅ Enabled: $svc"
  done

  echo ""
  echo "✔ NVIDIA services are now ENABLED and will start automatically on boot."
  echo "👉 You can verify with option 3 (Status) in the menu."
}

disable_services() {
  echo "⏹️ Disabling NVIDIA-related services (stop + no auto-start)..."
  for svc in "${SERVICES[@]}"; do
    sudo systemctl disable --now "$svc"
    echo "❌ Disabled: $svc"
  done

  echo ""
  echo "⚠ Services are DISABLED and will NOT start on next boot."
  echo "👉 To re-enable at boot, use option 1 from the menu."
}

status_services() {
  echo "📊 NVIDIA Services Status:"
  for svc in "${SERVICES[@]}"; do
    systemctl is-active --quiet "$svc" && state="running" || state="stopped"
    systemctl is-enabled --quiet "$svc" && boot="enabled" || boot="disabled"
    printf "• %-35s → %-8s | boot: %s\n" "$svc" "$state" "$boot"
  done
}

show_menu() {
  echo ""
  echo "====================================="
  echo "   NVIDIA Services Management Menu   "
  echo "====================================="
  echo "  1) Enable NVIDIA services"
  echo "  2) Disable NVIDIA services"
  echo "  3) Show status of services"
  echo "  0) Exit"
  echo "====================================="
}

# Main menu loop
while true; do
  show_menu
  read -r -p "Select an option [1-4]: " choice
  echo ""
  
  case "$choice" in
    1)
      enable_services
      ;;
    2)
      disable_services
      ;;
    3)
      status_services
      ;;
    0)
      echo "👋 Exiting..."
      exit 0
      ;;
    *)
      echo "❌ Invalid option. Please enter a number between 1 and 4."
      ;;
  esac
done
