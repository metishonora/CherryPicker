#!/bin/bash
set -euo pipefail

readonly LABEL="dev.cherrypicker.localserver"

die() {
	printf 'CherryPicker local server uninstall: %s\n' "$1" >&2
	exit 1
}

usage() {
	cat >&2 <<'EOF'
Usage: uninstall-launch-agent.sh

The SQLite database and logs are always preserved.
EOF
	exit 2
}

require_absolute_path() {
	case "$1" in
		/*) ;;
		*) die "$2 must be an absolute path" ;;
	esac
}

require_non_symlink() {
	local path="$1"
	local description="$2"
	if [[ -L "$path" ]]; then
		die "$description must not be a symlink"
	fi
}

delete_exact_file() {
	local path="$1"
	if [[ -e "$path" || -L "$path" ]]; then
		/bin/rm -f "$path" || die 'could not remove an installed file'
		return 0
	fi
	return 1
}

delete_empty_directory() {
	local path="$1"
	if [[ -d "$path" ]]; then
		/bin/rmdir "$path" 2>/dev/null || true
	fi
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--help|-h)
			usage
			;;
		*)
			usage
			;;
	esac
done

user_home="${HOME-}"
if [[ -z "$user_home" ]]; then
	die 'HOME must be set'
fi
require_absolute_path "$user_home" 'HOME'
if [[ "$user_home" == '/' ]]; then
	die 'HOME must not be the filesystem root'
fi
user_home="$(cd -- "$user_home" && pwd -P)" || die 'HOME must point to an existing directory'

install_root="$user_home/Library/Application Support/CherryPicker"
bin_dir="$install_root/bin"
config_dir="$install_root/config"
launch_agents_dir="$user_home/Library/LaunchAgents"
installed_binary_path="$bin_dir/CherryPickerLocalServer"
plist_path="$launch_agents_dir/$LABEL.plist"
config_path="$config_dir/local-server-config.plist"
database_path="$install_root/cherrypicker.sqlite"

for path in \
	"$user_home/Library" \
	"$user_home/Library/Application Support" \
	"$install_root" \
	"$bin_dir" \
	"$config_dir" \
	"$launch_agents_dir" \
	"$installed_binary_path" \
	"$plist_path" \
	"$config_path" \
	"$database_path"; do
	require_non_symlink "$path" 'an installation path'
done

domain="gui/$(/usr/bin/id -u)"
service="$domain/$LABEL"
if /bin/launchctl print "$service" >/dev/null 2>&1; then
	/bin/launchctl bootout "$service" || die 'launchctl could not boot out the launch agent'
fi

removed_artifact=false
for path in "$installed_binary_path" "$plist_path" "$config_path"; do
	if delete_exact_file "$path"; then
		removed_artifact=true
	fi
done

printf 'Preserved SQLite data and logs.\n'

delete_empty_directory "$bin_dir"
delete_empty_directory "$config_dir"
delete_empty_directory "$install_root"

if [[ "$removed_artifact" == true ]]; then
	printf 'Removed installed %s binary, plist, and config.\n' "$LABEL"
else
	printf 'No installed %s binary, plist, or config was present.\n' "$LABEL"
fi
