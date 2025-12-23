#!/bin/bash
# Diretta UPnP Renderer - Startup Wrapper Script
# This script builds the command line with all configured parameters

# Source configuration
if [ -f /opt/diretta-renderer-upnp/diretta-renderer.conf ]; then
    . /opt/diretta-renderer-upnp/diretta-renderer.conf
fi

# Build command with defaults
CMD="/opt/diretta-renderer-upnp/DirettaRendererUPnP"
CMD="$CMD --target ${TARGET:-1}"
CMD="$CMD --port ${PORT:-4005}"
CMD="$CMD --buffer ${BUFFER:-2.0}"

# Advanced Diretta SDK settings with defaults
CMD="$CMD --thread-mode ${THREAD_MODE:-1}"
CMD="$CMD --cycle-time ${CYCLE_TIME:-10000}"
CMD="$CMD --cycle-min-time ${CYCLE_MIN_TIME:-333}"
CMD="$CMD --info-cycle ${INFO_CYCLE:-5000}"

# Optional parameters (only if set)
[ -n "$MTU_OVERRIDE" ] && CMD="$CMD --mtu $MTU_OVERRIDE"
[ -n "$GAPLESS" ] && CMD="$CMD $GAPLESS"
[ -n "$VERBOSE" ] && CMD="$CMD $VERBOSE"

# Execute
exec $CMD
