#!/bin/bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
readonly PLIST_TEMPLATE_PATH="$SCRIPT_DIR/dev.cherrypicker.localserver.plist.template"
readonly CONFIG_TEMPLATE_PATH="$SCRIPT_DIR/local-server-config.plist.template"
readonly RECOVERY_SCRIPT_PATH="$SCRIPT_DIR/recover-launch-agent.sh"

die() {
	printf 'CherryPicker local server validation: %s\n' "$1" >&2
	exit 1
}

replace_plist_string() {
	local key_path="$1"
	local value="$2"
	local plist_path="$3"
	/usr/bin/plutil -replace "$key_path" -string "$value" "$plist_path"
}

insert_plist_string() {
	local key_path="$1"
	local value="$2"
	local plist_path="$3"
	/usr/bin/plutil -insert "$key_path" -string "$value" "$plist_path"
}

expect_value() {
	local key_path="$1"
	local expected="$2"
	local plist_path="$3"
	local actual
	actual="$(/usr/bin/plutil -extract "$key_path" raw -o - "$plist_path")" || die "missing plist key $key_path"
	if [[ "$actual" != "$expected" ]]; then
		die "unexpected value for plist key $key_path"
	fi
}

expect_array_count() {
	local key_path="$1"
	local expected="$2"
	local plist_path="$3"
	local actual
	actual="$(/usr/bin/plutil -extract "$key_path" raw -o - "$plist_path")" || die "missing plist array $key_path"
	if [[ "$actual" != "$expected" ]]; then
		die "unexpected item count for plist array $key_path"
	fi
}

expect_absent() {
	local key_path="$1"
	local plist_path="$2"
	if /usr/bin/plutil -extract "$key_path" raw -o - "$plist_path" >/dev/null 2>&1; then
		die "unexpected plist key $key_path"
	fi
}

for script_path in "$SCRIPT_DIR/install-launch-agent.sh" "$SCRIPT_DIR/uninstall-launch-agent.sh" "$SCRIPT_DIR/validate-launch-agent.sh" "$RECOVERY_SCRIPT_PATH"; do
	/bin/bash -n "$script_path" || die 'bash syntax check failed'
done

/usr/bin/plutil -lint "$PLIST_TEMPLATE_PATH" >/dev/null || die 'launch-agent plist template is invalid'
/usr/bin/plutil -lint "$CONFIG_TEMPLATE_PATH" >/dev/null || die 'config plist template is invalid'

for product_asset in \
	"$SCRIPT_DIR/install-launch-agent.sh" \
	"$SCRIPT_DIR/uninstall-launch-agent.sh" \
	"$RECOVERY_SCRIPT_PATH" \
	"$PLIST_TEMPLATE_PATH" \
	"$CONFIG_TEMPLATE_PATH"; do
	if /usr/bin/grep -E 'CherryPickerSpike|localserver\.spike|Issue ?7|Issue7|CherryPickerApp|SwiftData' "$product_asset" >/dev/null; then
		die 'product asset contains a spike or native-app path'
	fi
done

fixture_dir="$(mktemp -d -t cherrypicker-localserver-validation)" || die 'could not create fixture directory'
fixture_dir="$(cd -- "$fixture_dir" && pwd -P)" || die 'could not resolve fixture directory'
fixture_plist="$fixture_dir/rendered-launch-agent.plist"
fixture_config="$fixture_dir/rendered-config.plist"
fixture_binary="$fixture_dir/CherryPickerLocalServer"
fixture_home="$fixture_dir/home"
cleanup() {
	/bin/rm -f "$fixture_plist" "$fixture_config" "$fixture_binary"
	if [[ "$fixture_home" == "$fixture_dir/home" ]]; then
		/bin/rm -rf "$fixture_home"
	fi
	/bin/rmdir "$fixture_dir" 2>/dev/null || true
}
trap cleanup EXIT HUP INT TERM

/bin/cp "$PLIST_TEMPLATE_PATH" "$fixture_plist"
/bin/cp "$CONFIG_TEMPLATE_PATH" "$fixture_config"

fixture_database="$fixture_dir/cherrypicker.sqlite"
fixture_login='fixture-device@example.test'
fixture_stdout="$fixture_dir/localserver.stdout.log"
fixture_stderr="$fixture_dir/localserver.stderr.log"
fixture_plist_path="$fixture_home/Library/LaunchAgents/dev.cherrypicker.localserver.plist"
fixture_config_path="$fixture_home/Library/Application Support/CherryPicker/config/local-server-config.plist"

insert_plist_string 'ProgramArguments.0' "$fixture_binary" "$fixture_plist"
replace_plist_string 'EnvironmentVariables.CHERRYPICKER_ALLOWED_TAILSCALE_LOGIN' "$fixture_login" "$fixture_plist"
replace_plist_string 'EnvironmentVariables.CHERRYPICKER_DB_PATH' "$fixture_database" "$fixture_plist"
replace_plist_string 'StandardOutPath' "$fixture_stdout" "$fixture_plist"
replace_plist_string 'StandardErrorPath' "$fixture_stderr" "$fixture_plist"
/usr/bin/plutil -lint "$fixture_plist" >/dev/null || die 'rendered launch-agent fixture is invalid'
expect_value 'Label' 'dev.cherrypicker.localserver' "$fixture_plist"
expect_value 'ProgramArguments.0' "$fixture_binary" "$fixture_plist"
expect_array_count 'ProgramArguments' '1' "$fixture_plist"
expect_absent 'ProgramArguments.1' "$fixture_plist"
expect_value 'EnvironmentVariables.CHERRYPICKER_ALLOWED_TAILSCALE_LOGIN' "$fixture_login" "$fixture_plist"
expect_value 'EnvironmentVariables.CHERRYPICKER_DB_PATH' "$fixture_database" "$fixture_plist"
expect_value 'EnvironmentVariables.CHERRYPICKER_PORT' '8765' "$fixture_plist"
expect_value 'StandardOutPath' "$fixture_stdout" "$fixture_plist"
expect_value 'StandardErrorPath' "$fixture_stderr" "$fixture_plist"
expect_value 'Umask' '63' "$fixture_plist"

replace_plist_string 'BinaryPath' "$fixture_binary" "$fixture_config"
replace_plist_string 'DatabasePath' "$fixture_database" "$fixture_config"
replace_plist_string 'LaunchAgentPlistPath' "$fixture_plist_path" "$fixture_config"
replace_plist_string 'StandardOutPath' "$fixture_stdout" "$fixture_config"
replace_plist_string 'StandardErrorPath' "$fixture_stderr" "$fixture_config"
/usr/bin/plutil -lint "$fixture_config" >/dev/null || die 'rendered config fixture is invalid'
expect_value 'BinaryPath' "$fixture_binary" "$fixture_config"
expect_value 'DatabasePath' "$fixture_database" "$fixture_config"
expect_value 'LaunchAgentLabel' 'dev.cherrypicker.localserver' "$fixture_config"
expect_value 'LaunchAgentPlistPath' "$fixture_plist_path" "$fixture_config"
expect_value 'Port' '8765' "$fixture_config"
expect_value 'StandardOutPath' "$fixture_stdout" "$fixture_config"
expect_value 'StandardErrorPath' "$fixture_stderr" "$fixture_config"

/bin/mkdir -p "$(/usr/bin/dirname "$fixture_plist_path")" "$(/usr/bin/dirname "$fixture_config_path")"
/usr/bin/touch "$fixture_binary"
/bin/chmod 0755 "$fixture_binary"
/bin/cp "$fixture_plist" "$fixture_plist_path"
/bin/cp "$fixture_config" "$fixture_config_path"
/bin/chmod 0600 "$fixture_plist_path" "$fixture_config_path"
HOME="$fixture_home" "$RECOVERY_SCRIPT_PATH" --check >/dev/null || die 'recovery fixture validation failed'

/usr/bin/plutil -replace 'Port' -string '8766' "$fixture_config_path"
if HOME="$fixture_home" "$RECOVERY_SCRIPT_PATH" --check >/dev/null 2>&1; then
	die 'recovery fixture accepted a mismatched configured port'
fi

printf 'CherryPicker product launch-agent assets and temporary fixtures validated.\n'
