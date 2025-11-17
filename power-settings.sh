#!/usr/bin/env bash

set -euo pipefail

# Checks or sets power settings on Ubuntu
# Usage:
#   power-settings.sh list            # Show the governor for all cores/threads
#   power-settings.sh set <governor>  # Set all cores/threads to a governor

# Display usage information
usage() {
	echo "Usage: power-settings.sh <command> [<governor>]"
	echo ""
	echo "Commands:"
	echo "  list              Show the current CPU governor for all cores/threads"
	echo "  governors         Show available governors on this machine"
	echo "  set <governor>    Set all cores/threads to the specified governor"
	echo ""
	echo "Available governors: powersave, performance, ondemand, conservative, schedutil"
	exit 1
}

# List current governors for all CPUs
list_governors() {
	echo "Current CPU governors:"
	for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
		cpu_name=$(basename "${cpu}")
		governor=$(cat "${cpu}/cpufreq/scaling_governor" 2>/dev/null || echo "N/A")
		echo "  ${cpu_name}: ${governor}"
	done
}

# List available governors on this machine
list_available_governors() {
	local first_cpu="/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors"

	if [[ ! -f "${first_cpu}" ]]; then
		echo "Error: Could not find available governors file"
		echo "This machine may not support CPU frequency scaling"
		return 1
	fi

	echo "Available governors on this machine:"
	cat "${first_cpu}" | tr ' ' '\n' | sed 's/^/  /'
}

# Set governor for all CPUs
set_governor() {
	local governor=$1

	if [[ -z "${governor}" ]]; then
		echo "Error: Governor not specified"
		usage
	fi

	echo "Setting CPU governor to ${governor}..."
	for cpu in /sys/devices/system/cpu/cpu[0-9]*; do
		echo "${governor}" | sudo tee "${cpu}/cpufreq/scaling_governor" > /dev/null
	done
	echo "CPU governor set to ${governor}"
}

# Main script logic
if [[ $# -eq 0 ]]; then
	usage
fi

case "${1}" in
	list)
		list_governors
		;;
	governors)
		list_available_governors
		;;
	set)
		set_governor "${2}"
		;;
	*)
		echo "Error: Unknown command '${1}'"
		usage
		;;
esac