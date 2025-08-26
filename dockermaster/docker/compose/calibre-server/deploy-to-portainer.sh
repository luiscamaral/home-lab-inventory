#!/bin/bash
echo "=== Calibre to Portainer Migration Script ==="
echo "Timestamp: $(date)"

# Check if containers are running
echo "Checking for running calibre containers..."
RUNNING_CONTAINERS=$(docker ps --filter "name=calibre" --format "table {{.Names}}" | grep -v NAMES)

if [ ! -z "$RUNNING_CONTAINERS" ]; then
  echo "Found running calibre containers:"
  echo "$RUNNING_CONTAINERS"
  echo "Stopping calibre containers gracefully..."

  # Stop containers gracefully
  docker ps --filter "name=calibre" --format "{{.Names}}" | while read container; do
    echo "Stopping container: $container"
    docker stop "$container" --time 30
  done

  echo "Waiting for containers to stop..."
  sleep 5

  # Verify containers are stopped
  STILL_RUNNING=$(docker ps --filter "name=calibre" --format "{{.Names}}")
  if [ ! -z "$STILL_RUNNING" ]; then
    echo "WARNING: Some containers are still running: $STILL_RUNNING"
    echo "Consider manual intervention."
  else
    echo "All calibre containers stopped successfully."
  fi
else
  echo "No calibre containers currently running."
fi

# Verify volume preservation
echo ""
echo "Verifying volume preservation..."
if [ -d "/nfs/calibre" ]; then
  echo "✓ Calibre data volumes preserved at /nfs/calibre/"
  echo "  Library: /nfs/calibre/library"
  echo "  Config:  /nfs/calibre/config"
else
  echo "⚠ WARNING: /nfs/calibre directory not found - volumes may not be preserved!"
fi

echo ""
echo "Migration preparation complete!"
echo "Ready for Portainer deployment using docker-compose.portainer.yml"
echo "Next steps:"
echo "  1. Deploy stack in Portainer using the portainer-stack-config.json"
echo "  2. Set CALIBRE_PASSWORD environment variable in Portainer"
echo "  3. Verify deployment and access"
