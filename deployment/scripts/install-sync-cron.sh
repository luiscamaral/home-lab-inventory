#!/bin/bash
# Install GitHub sync as a cron job or systemd timer
# Run this on the dockermaster server

set -e

SCRIPT_PATH="/usr/local/bin/github-sync.sh"
SYSTEMD_SERVICE="/etc/systemd/system/docker-deploy-sync.service"
SYSTEMD_TIMER="/etc/systemd/system/docker-deploy-sync.timer"

echo "Docker Deployment Auto-Sync Installer"
echo "======================================"
echo ""
echo "Choose installation method:"
echo "1) Cron job (every 5 minutes)"
echo "2) Systemd timer (every 5 minutes)"
echo "3) Manual setup"
echo ""
read -p "Enter choice [1-3]: " choice

# Copy the sync script
echo "Installing sync script..."
sudo cp ./github-sync.sh "$SCRIPT_PATH"
sudo chmod +x "$SCRIPT_PATH"

case $choice in
    1)
        echo "Installing cron job..."
        # Add cron job for every 5 minutes
        (crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" ; echo "*/5 * * * * $SCRIPT_PATH >> /var/log/docker-deploy-cron.log 2>&1") | crontab -
        echo "Cron job installed. Check 'crontab -l' to verify."
        echo "Logs will be written to /var/log/docker-deploy.log"
        ;;

    2)
        echo "Installing systemd timer..."

        # Create systemd service
        sudo tee "$SYSTEMD_SERVICE" > /dev/null <<EOF
[Unit]
Description=Docker Deployment Sync from GitHub
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=$SCRIPT_PATH
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

        # Create systemd timer
        sudo tee "$SYSTEMD_TIMER" > /dev/null <<EOF
[Unit]
Description=Run Docker Deployment Sync every 5 minutes
Requires=docker-deploy-sync.service

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF

        # Enable and start timer
        sudo systemctl daemon-reload
        sudo systemctl enable docker-deploy-sync.timer
        sudo systemctl start docker-deploy-sync.timer

        echo "Systemd timer installed and started."
        echo "Check status with: systemctl status docker-deploy-sync.timer"
        echo "View logs with: journalctl -u docker-deploy-sync.service -f"
        ;;

    3)
        echo "Manual setup selected."
        echo ""
        echo "The sync script has been installed to: $SCRIPT_PATH"
        echo ""
        echo "To run manually:"
        echo "  $SCRIPT_PATH"
        echo ""
        echo "To add to cron manually, add this line to crontab:"
        echo "  */5 * * * * $SCRIPT_PATH"
        echo ""
        echo "To use with systemd, create service and timer files as shown in the script."
        ;;

    *)
        echo "Invalid choice. Script installed but not scheduled."
        echo "Run manually: $SCRIPT_PATH"
        ;;
esac

echo ""
echo "Installation complete!"
echo ""
echo "Additional configuration:"
echo "1. Make sure Docker is configured to access ghcr.io"
echo "2. For private images, configure Docker credentials:"
echo "   docker login ghcr.io -u USERNAME -p GITHUB_PAT"
echo "3. Update docker-compose files to use ghcr.io images"
echo "4. Add 'com.centurylinklabs.watchtower.enable=true' label for Watchtower"
