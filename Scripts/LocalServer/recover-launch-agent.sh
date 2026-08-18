#!/bin/bash
set -euo pipefail

readonly LABEL="dev.cherrypicker.localserver"
readonly DEFAULT_TIMEOUT_SECONDS=20

die() {
	printf 'CherryPicker local server recovery: %s\n' "$1" >&2
	exit 1
}

usage() {
	printf '%s\n' \
		'Usage: recover-launch-agent.sh [--check] [--timeout SECONDS]' \
		'' \
		'Without --check, validates the installed service, starts it only when' \
		'needed, and waits for the loopback health endpoint. It does not install' \
		'artifacts, change SQLite data, or modify Tailscale Serve.' >&2
	exit 2
}

require_absolute_path() {
	case "$1" in
		/*) ;;
		*) die "$2 must be an absolute path" ;;
	esac
	case "$1" in
		*$'\n'*|*$'\r'*) die "$2 contains a line break" ;;
	esac
}

require_non_symlink() {
	if [[ -L "$1" ]]; then
		die "$2 must not be a symlink"
	fi
}

plist_value() {
	local key_path="$1"
	local plist_path="$2"
	/usr/bin/plutil -extract "$key_path" raw -o - "$plist_path" 2>/dev/null ||
		die "installed configuration is missing $key_path"
}

require_equal() {
	if [[ "$1" != "$2" ]]; then
		die "$3 does not match the installed launch agent"
	fi
}

health_is_ok() {
	local response
	response="$(/usr/bin/curl --fail --silent --max-time 2 "$health_url" 2>/dev/null || true)"
	[[ "$response" == 'ok' ]]
}

check_only=false
timeout_seconds="$DEFAULT_TIMEOUT_SECONDS"
while [[ $# -gt 0 ]]; do
	case "$1" in
		--check)
			check_only=true
			shift
			;;
		--timeout)
			[[ $# -ge 2 ]] || usage
			timeout_seconds="$2"
			shift 2
			;;
		--help|-h)
			usage
			;;
		*)
			usage
			;;
	esac
done

case "$timeout_seconds" in
	''|*[!0-9]*) die 'timeout must be a positive integer' ;;
esac
if (( timeout_seconds < 1 || timeout_seconds > 300 )); then
	die 'timeout must be between 1 and 300 seconds'
fi

user_home="${HOME-}"
[[ -n "$user_home" ]] || die 'HOME must be set'
require_absolute_path "$user_home" 'HOME'
[[ "$user_home" != '/' ]] || die 'HOME must not be the filesystem root'
user_home="$(cd -- "$user_home" && pwd -P)" || die 'HOME must point to an existing directory'

install_root="$user_home/Library/Application Support/CherryPicker"
config_path="$install_root/config/local-server-config.plist"
expected_plist_path="$user_home/Library/LaunchAgents/$LABEL.plist"

for path in \
	"$user_home/Library" \
	"$user_home/Library/Application Support" \
	"$install_root" \
	"$install_root/config" \
	"$user_home/Library/LaunchAgents" \
	"$config_path" \
	"$expected_plist_path"; do
	require_non_symlink "$path" 'an installed service path'
done

[[ -f "$config_path" ]] || die 'installed config is missing; run install-launch-agent.sh first'
[[ -f "$expected_plist_path" ]] || die 'installed LaunchAgent plist is missing; run install-launch-agent.sh first'
/usr/bin/plutil -lint "$config_path" >/dev/null || die 'installed config plist is invalid'
/usr/bin/plutil -lint "$expected_plist_path" >/dev/null || die 'installed LaunchAgent plist is invalid'

binary_path="$(plist_value 'BinaryPath' "$config_path")"
database_path="$(plist_value 'DatabasePath' "$config_path")"
configured_label="$(plist_value 'LaunchAgentLabel' "$config_path")"
configured_plist_path="$(plist_value 'LaunchAgentPlistPath' "$config_path")"
configured_port="$(plist_value 'Port' "$config_path")"
configured_stdout="$(plist_value 'StandardOutPath' "$config_path")"
configured_stderr="$(plist_value 'StandardErrorPath' "$config_path")"

require_equal "$configured_label" "$LABEL" 'configured label'
require_equal "$configured_plist_path" "$expected_plist_path" 'configured plist path'
require_absolute_path "$binary_path" 'configured binary path'
require_absolute_path "$database_path" 'configured database path'
require_absolute_path "$configured_stdout" 'configured stdout path'
require_absolute_path "$configured_stderr" 'configured stderr path'

for path in "$binary_path" "$database_path" "$configured_stdout" "$configured_stderr"; do
	require_non_symlink "$path" 'a configured service path'
done
[[ -f "$binary_path" && -x "$binary_path" ]] || die 'installed server binary is missing or not executable'

plist_label="$(plist_value 'Label' "$expected_plist_path")"
plist_binary="$(plist_value 'ProgramArguments.0' "$expected_plist_path")"
plist_database="$(plist_value 'EnvironmentVariables.CHERRYPICKER_DB_PATH' "$expected_plist_path")"
plist_port="$(plist_value 'EnvironmentVariables.CHERRYPICKER_PORT' "$expected_plist_path")"
plist_stdout="$(plist_value 'StandardOutPath' "$expected_plist_path")"
plist_stderr="$(plist_value 'StandardErrorPath' "$expected_plist_path")"
run_at_load="$(plist_value 'RunAtLoad' "$expected_plist_path")"
keep_alive="$(plist_value 'KeepAlive' "$expected_plist_path")"
argument_count="$(plist_value 'ProgramArguments' "$expected_plist_path")"

require_equal "$plist_label" "$LABEL" 'LaunchAgent label'
require_equal "$plist_binary" "$binary_path" 'server binary path'
require_equal "$plist_database" "$database_path" 'database path'
require_equal "$plist_port" "$configured_port" 'server port'
require_equal "$plist_stdout" "$configured_stdout" 'stdout path'
require_equal "$plist_stderr" "$configured_stderr" 'stderr path'
require_equal "$run_at_load" 'true' 'RunAtLoad setting'
require_equal "$keep_alive" 'true' 'KeepAlive setting'
require_equal "$argument_count" '1' 'ProgramArguments count'

case "$configured_port" in
	''|*[!0-9]*) die 'configured port must be an integer' ;;
esac
if (( configured_port < 1 || configured_port > 65535 )); then
	die 'configured port is outside the valid range'
fi

health_url="http://127.0.0.1:$configured_port/healthz"
if [[ "$check_only" == true ]]; then
	printf 'CherryPicker local server installation is ready for recovery.\n'
	exit 0
fi

domain="gui/$(/usr/bin/id -u)"
service="$domain/$LABEL"
service_is_loaded=false
if /bin/launchctl print "$service" >/dev/null 2>&1; then
	service_is_loaded=true
fi

if [[ "$service_is_loaded" == true ]] && health_is_ok; then
	printf 'CherryPicker local server is already healthy at %s.\n' "$health_url"
	exit 0
fi

if [[ "$service_is_loaded" == true ]]; then
	/bin/launchctl kickstart -k "$service" || die 'launchctl could not restart the registered service'
else
	if ! /bin/launchctl bootstrap "$domain" "$expected_plist_path"; then
		/bin/launchctl print "$service" >/dev/null 2>&1 || die 'launchctl could not register the installed service'
	fi
	/bin/launchctl kickstart -k "$service" || die 'launchctl could not start the registered service'
fi

elapsed=0
while (( elapsed < timeout_seconds )); do
	if health_is_ok; then
		printf 'CherryPicker local server recovered and is healthy at %s.\n' "$health_url"
		exit 0
	fi
	/bin/sleep 1
	elapsed=$((elapsed + 1))
done

printf 'CherryPicker local server recovery: health check failed after %s seconds.\n' "$timeout_seconds" >&2
printf 'Inspect the configured error log: %s\n' "$configured_stderr" >&2
exit 1
