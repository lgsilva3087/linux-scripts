#!/usr/bin/env bash

set -euo pipefail

usage() {
	echo "Usage: $(basename "$0") [--yes] [--skip-ubuntu] [--skip-cli]"
	echo ""
	echo "Options:"
	echo "  -y, --yes       Run apt dist-upgrade without the review prompt"
	echo "  --skip-ubuntu   Skip apt update/list/dist-upgrade"
	echo "  --skip-cli      Skip Codex and Claude updates"
	echo "  -h, --help      Show this help"
}

require_regular_user() {
	if [[ "${EUID}" -eq 0 ]]; then
		echo "Do not run this script with sudo." >&2
		echo "Run it as your regular user: ./$(basename "$0")" >&2
		echo "The script will ask for sudo only when running apt commands." >&2
		exit 1
	fi
}

confirm_dist_upgrade() {
	local response

	read -r -p "Run sudo apt dist-upgrade now? [y/N] " response
	case "${response}" in
		[yY]|[yY][eE][sS])
			return 0
			;;
		*)
			return 1
			;;
	esac
}

update_ubuntu() {
	local assume_yes=$1

	echo "Updating apt package indexes..."
	sudo apt update

	echo ""
	echo "Upgradable packages:"
	apt list --upgradable

	echo ""
	if [[ "${assume_yes}" == "true" ]] || confirm_dist_upgrade; then
		echo "Running apt dist-upgrade..."
		sudo apt dist-upgrade
	else
		echo "Skipping apt dist-upgrade."
	fi
}

update_command() {
	local command_name=$1

	if command -v "${command_name}" >/dev/null 2>&1; then
		echo ""
		echo "Updating ${command_name}..."
		"${command_name}" update
	else
		echo ""
		echo "Skipping ${command_name}: command not found."
	fi
}

assume_yes=false
skip_ubuntu=false
skip_cli=false

while [[ $# -gt 0 ]]; do
	case "$1" in
		-y|--yes)
			assume_yes=true
			;;
		--skip-ubuntu)
			skip_ubuntu=true
			;;
		--skip-cli)
			skip_cli=true
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			echo "Unknown option: $1" >&2
			usage >&2
			exit 1
			;;
	esac
	shift
done

require_regular_user

if [[ "${skip_ubuntu}" == "false" ]]; then
	update_ubuntu "${assume_yes}"
fi

if [[ "${skip_cli}" == "false" ]]; then
	update_command codex
	update_command claude
fi
