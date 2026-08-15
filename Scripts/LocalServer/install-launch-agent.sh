#!/bin/bash
set -euo pipefail

readonly LABEL="dev.cherrypicker.localserver"
readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PLIST_TEMPLATE_PATH="$SCRIPT_DIR/dev.cherrypicker.localserver.plist.template"
readonly CONFIG_TEMPLATE_PATH="$SCRIPT_DIR/local-server-config.plist.template"

die() {
	printf 'CherryPicker local server install: %s\n' "$1" >&2
	exit 1
}

usage() {
	cat >&2 <<'EOF'
Usage: install-launch-agent.sh [--start] [BUILT_BINARY_PATH]

The binary path may instead be supplied with CHERRYPICKER_LOCAL_SERVER_BINARY.
CHERRYPICKER_ALLOWED_TAILSCALE_LOGIN must be supplied in the environment.
EOF
	exit 2
}

trim_ascii_space() {
	# Command substitution removes trailing newlines; the input is rejected for
	# embedded newlines below, so this is safe for the login value.
	printf '%s' "$1" | /usr/bin/sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
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
	local path="$1"
	local description="$2"
	if [[ -L "$path" ]]; then
		die "$description must not be a symlink"
	fi
}

insert_plist_string() {
	local key_path="$1"
	local value="$2"
	local plist_path="$3"
	/usr/bin/plutil -insert "$key_path" -string "$value" "$plist_path"
}

replace_plist_string() {
	local key_path="$1"
	local value="$2"
	local plist_path="$3"
	/usr/bin/plutil -replace "$key_path" -string "$value" "$plist_path"
}

validate_plist_value() {
	local key_path="$1"
	local expected="$2"
	local plist_path="$3"
	local actual
	actual="$(/usr/bin/plutil -extract "$key_path" raw -o - "$plist_path")" || die "rendered plist is missing $key_path"
	if [[ "$actual" != "$expected" ]]; then
		die "rendered plist has an unexpected $key_path value"
	fi
}

validate_plist_array_count() {
	local key_path="$1"
	local expected="$2"
	local plist_path="$3"
	local actual
	actual="$(/usr/bin/plutil -extract "$key_path" raw -o - "$plist_path")" || die "rendered plist is missing $key_path"
	if [[ "$actual" != "$expected" ]]; then
		die "rendered plist has an unexpected item count for $key_path"
	fi
}

validate_plist_key_absent() {
	local key_path="$1"
	local plist_path="$2"
	if /usr/bin/plutil -extract "$key_path" raw -o - "$plist_path" >/dev/null 2>&1; then
		die "rendered plist has an unexpected $key_path value"
	fi
}

render_launch_agent() {
	local target_path="$1"
	local binary_path="$2"
	local database_path="$3"
	local allowed_login="$4"
	local stdout_path="$5"
	local stderr_path="$6"
	local temporary_path

	temporary_path="$(mktemp "${target_path}.XXXXXX")" || die "could not create a temporary plist"
	cleanup_paths+=("$temporary_path")
	/bin/cp "$PLIST_TEMPLATE_PATH" "$temporary_path" || die "could not copy the plist template"
	insert_plist_string 'ProgramArguments.0' "$binary_path" "$temporary_path" || die "could not set the binary path"
	replace_plist_string 'EnvironmentVariables.CHERRYPICKER_ALLOWED_TAILSCALE_LOGIN' "$allowed_login" "$temporary_path" || die "could not set the allowed login"
	replace_plist_string 'EnvironmentVariables.CHERRYPICKER_DB_PATH' "$database_path" "$temporary_path" || die "could not set the database path"
	replace_plist_string 'StandardOutPath' "$stdout_path" "$temporary_path" || die "could not set the standard output path"
	replace_plist_string 'StandardErrorPath' "$stderr_path" "$temporary_path" || die "could not set the standard error path"
	/usr/bin/plutil -lint "$temporary_path" >/dev/null || die "rendered launch-agent plist is invalid"
	validate_plist_value 'Label' "$LABEL" "$temporary_path"
	validate_plist_value 'ProgramArguments.0' "$binary_path" "$temporary_path"
	validate_plist_array_count 'ProgramArguments' '1' "$temporary_path"
	validate_plist_key_absent 'ProgramArguments.1' "$temporary_path"
	validate_plist_value 'EnvironmentVariables.CHERRYPICKER_ALLOWED_TAILSCALE_LOGIN' "$allowed_login" "$temporary_path"
	validate_plist_value 'EnvironmentVariables.CHERRYPICKER_DB_PATH' "$database_path" "$temporary_path"
	validate_plist_value 'EnvironmentVariables.CHERRYPICKER_PORT' '8765' "$temporary_path"
	validate_plist_value 'StandardOutPath' "$stdout_path" "$temporary_path"
	validate_plist_value 'StandardErrorPath' "$stderr_path" "$temporary_path"
	validate_plist_value 'Umask' '63' "$temporary_path"
	/bin/chmod 0600 "$temporary_path"
	/bin/mv -f "$temporary_path" "$target_path" || die "could not install the launch-agent plist"
	cleanup_paths=()
}

render_config() {
	local target_path="$1"
	local binary_path="$2"
	local database_path="$3"
	local plist_path="$4"
	local stdout_path="$5"
	local stderr_path="$6"
	local temporary_path

	temporary_path="$(mktemp "${target_path}.XXXXXX")" || die "could not create a temporary config plist"
	cleanup_paths+=("$temporary_path")
	/bin/cp "$CONFIG_TEMPLATE_PATH" "$temporary_path" || die "could not copy the config template"
	replace_plist_string 'BinaryPath' "$binary_path" "$temporary_path" || die "could not set the config binary path"
	replace_plist_string 'DatabasePath' "$database_path" "$temporary_path" || die "could not set the config database path"
	replace_plist_string 'LaunchAgentPlistPath' "$plist_path" "$temporary_path" || die "could not set the config plist path"
	replace_plist_string 'StandardOutPath' "$stdout_path" "$temporary_path" || die "could not set the config output path"
	replace_plist_string 'StandardErrorPath' "$stderr_path" "$temporary_path" || die "could not set the config error path"
	/usr/bin/plutil -lint "$temporary_path" >/dev/null || die "rendered config plist is invalid"
	validate_plist_value 'BinaryPath' "$binary_path" "$temporary_path"
	validate_plist_value 'DatabasePath' "$database_path" "$temporary_path"
	validate_plist_value 'LaunchAgentLabel' "$LABEL" "$temporary_path"
	validate_plist_value 'LaunchAgentPlistPath' "$plist_path" "$temporary_path"
	validate_plist_value 'Port' '8765' "$temporary_path"
	validate_plist_value 'StandardOutPath' "$stdout_path" "$temporary_path"
	validate_plist_value 'StandardErrorPath' "$stderr_path" "$temporary_path"
	/bin/chmod 0600 "$temporary_path"
	/bin/mv -f "$temporary_path" "$target_path" || die "could not install the launch-agent config"
	cleanup_paths=()
}

cleanup() {
	local path
	for path in "${cleanup_paths[@]:-}"; do
		if [[ -n "$path" && ( -e "$path" || -L "$path" ) ]]; then
			/bin/rm -f "$path"
		fi
	done
}

start_launch_agent() {
	local domain="gui/$(/usr/bin/id -u)"
	local service="$domain/$LABEL"
	if /bin/launchctl print "$service" >/dev/null 2>&1; then
		/bin/launchctl bootout "$service" || die "launchctl could not unload the existing launch agent"
	fi
	/bin/launchctl bootstrap "$domain" "$plist_path" || die "launchctl could not bootstrap the launch agent"
	/bin/launchctl kickstart -k "$service" || die "launchctl could not start the launch agent"
}

cleanup_paths=()
trap cleanup EXIT HUP INT TERM

start_requested=false
binary_argument=''
while [[ $# -gt 0 ]]; do
	case "$1" in
		--start)
			start_requested=true
			shift
			;;
		--help|-h)
			usage
			;;
		-*)
			usage
			;;
		*)
			if [[ -n "$binary_argument" ]]; then
				usage
			fi
			binary_argument="$1"
			shift
			;;
	esac
done

if [[ -z "${CHERRYPICKER_ALLOWED_TAILSCALE_LOGIN+x}" ]]; then
	die 'CHERRYPICKER_ALLOWED_TAILSCALE_LOGIN must be set in the environment (never pass it as an argument)'
fi
allowed_login="$(trim_ascii_space "${CHERRYPICKER_ALLOWED_TAILSCALE_LOGIN-}")"
if [[ -z "$allowed_login" ]]; then
	die 'CHERRYPICKER_ALLOWED_TAILSCALE_LOGIN must not be empty'
fi
case "$allowed_login" in
	*$'\n'*|*$'\r'*) die 'CHERRYPICKER_ALLOWED_TAILSCALE_LOGIN must not contain a line break' ;;
esac

binary_from_environment="${CHERRYPICKER_LOCAL_SERVER_BINARY-}"
if [[ -n "$binary_argument" && -n "$binary_from_environment" && "$binary_argument" != "$binary_from_environment" ]]; then
	die 'binary path argument and CHERRYPICKER_LOCAL_SERVER_BINARY disagree'
fi
binary_source="$binary_argument"
if [[ -z "$binary_source" ]]; then
	binary_source="$binary_from_environment"
fi
if [[ -z "$binary_source" ]]; then
	die 'provide the built binary path as an argument or CHERRYPICKER_LOCAL_SERVER_BINARY'
fi
require_absolute_path "$binary_source" 'built binary path'
if [[ ! -f "$binary_source" || ! -x "$binary_source" ]]; then
	die 'built binary path must point to an executable file'
fi

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
log_dir="$user_home/Library/Logs/CherryPicker"
launch_agents_dir="$user_home/Library/LaunchAgents"
installed_binary_path="$bin_dir/CherryPickerLocalServer"
plist_path="$launch_agents_dir/$LABEL.plist"
config_path="$config_dir/local-server-config.plist"
database_path="$install_root/cherrypicker.sqlite"
stdout_path="$log_dir/localserver.stdout.log"
stderr_path="$log_dir/localserver.stderr.log"

for path in \
	"$user_home/Library" \
	"$user_home/Library/Application Support" \
	"$install_root" \
	"$bin_dir" \
	"$config_dir" \
	"$log_dir" \
	"$launch_agents_dir" \
	"$installed_binary_path" \
	"$plist_path" \
	"$config_path" \
	"$database_path" \
	"$stdout_path" \
	"$stderr_path"; do
	require_non_symlink "$path" 'an installation path'
done

for path in "$install_root" "$bin_dir" "$config_dir" "$log_dir" "$launch_agents_dir"; do
	/bin/mkdir -p "$path" || die 'could not create an installation directory'
done

/bin/chmod 0700 "$install_root" "$bin_dir" "$config_dir" "$log_dir" || die 'could not protect installation directories'

/usr/bin/install -m 0755 "$binary_source" "$installed_binary_path" || die 'could not install the built binary'
render_launch_agent "$plist_path" "$installed_binary_path" "$database_path" "$allowed_login" "$stdout_path" "$stderr_path"
render_config "$config_path" "$installed_binary_path" "$database_path" "$plist_path" "$stdout_path" "$stderr_path"

if [[ "$start_requested" == true ]]; then
	start_launch_agent
fi

if [[ "$start_requested" == true ]]; then
	printf 'Installed and started %s.\n' "$LABEL"
else
	printf 'Installed %s (not started; pass --start to invoke launchctl).\n' "$LABEL"
fi
