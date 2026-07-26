#!/usr/bin/env bash
# Application discovery and per-app config parsing.
#
# An "application" is any TOP-LEVEL directory that is tracked by git and
# contains both a Dockerfile and a VERSION file. There is no hardcoded list
# anywhere in the pipeline: dropping in a new folder is enough to onboard it.
#
# Per-app configuration lives in an OPTIONAL <app>/ci.yaml. We parse a small,
# strictly-validated YAML subset by hand rather than depending on yq/python,
# neither of which is guaranteed on the self-hosted ARC runner image. The
# supported subset is documented in docs/ci.md and is deliberately flat:
#
#   image: arc-runner                        # optional, defaults to folder name
#   platforms: linux/amd64,linux/arm64       # optional, comma-separated ON ONE LINE
#   build_args:                              # optional, list of KEY=value
#     - RUNNER_VERSION=2.336.0
#
# Comments must be on their own line. Anything else is rejected loudly rather
# than silently ignored, so a typo can never quietly change what gets built.

# Defaults applied when <app>/ci.yaml is absent or omits a key.
DEFAULT_PLATFORMS="linux/amd64,linux/arm64"

die() {
	echo "::error::$*" >&2
	exit 1
}

trim() {
	local s=$1
	s=${s#"${s%%[![:space:]]*}"}
	s=${s%"${s##*[![:space:]]}"}
	printf '%s' "$s"
}

# read_lines <arrayname> — fill the named array from stdin, one element per line.
# A portable stand-in for `mapfile -t`, which does not exist in bash 3.2 (the
# version macOS ships), so these scripts stay runnable outside CI too.
read_lines() {
	local __name=$1 __line
	eval "$__name=()"
	while IFS= read -r __line || [[ -n $__line ]]; do
		eval "$__name+=(\"\$__line\")"
	done
}

# list_apps -> one app folder name per line, sorted.
# Uses `git ls-files` so untracked scratch directories are never picked up.
list_apps() {
	local f d
	while IFS= read -r f; do
		d=${f%/Dockerfile}
		# Top-level only: reject nested paths like foo/bar/Dockerfile.
		case $d in
		*/*) continue ;;
		esac
		[[ -f $d/VERSION ]] || continue
		printf '%s\n' "$d"
	done < <(git ls-files -- '*/Dockerfile') | sort -u
}

# read_version <app> -> the trimmed contents of <app>/VERSION.
# Fails loudly on empty files or anything spanning more than one line, so a
# malformed VERSION can never become an image tag.
read_version() {
	local app=$1 file="$1/VERSION" raw
	[[ -f $file ]] || die "$app: VERSION file is missing"

	raw=$(tr -d '\r' <"$file")

	local -a lines=()
	local line
	while IFS= read -r line; do
		[[ -n $(trim "$line") ]] && lines+=("$(trim "$line")")
	done <<<"$raw"

	((${#lines[@]} == 1)) ||
		die "$app/VERSION must contain exactly one non-empty line (found ${#lines[@]})"

	printf '%s' "${lines[0]}"
}

# parse_app_config <app>
# Sets globals CFG_IMAGE, CFG_PLATFORMS, CFG_BUILD_ARGS (newline-separated).
parse_app_config() {
	local app=$1 file="$1/ci.yaml"

	CFG_IMAGE=$app
	CFG_PLATFORMS=$DEFAULT_PLATFORMS
	CFG_BUILD_ARGS=""

	[[ -f $file ]] || return 0

	local line key val current_key="" seen_args=0
	local lineno=0
	while IFS= read -r line || [[ -n $line ]]; do
		lineno=$((lineno + 1))
		line=${line%$'\r'}

		# Skip blank lines and whole-line comments.
		[[ -z $(trim "$line") ]] && continue
		[[ $(trim "$line") == \#* ]] && continue

		if [[ $line =~ ^([a-z_]+):[[:space:]]*(.*)$ ]]; then
			key=${BASH_REMATCH[1]}
			val=$(trim "${BASH_REMATCH[2]}")
			current_key=$key

			case $key in
			image)
				[[ -n $val ]] || die "$file:$lineno: 'image' must have a value"
				CFG_IMAGE=$val
				;;
			platforms)
				[[ -n $val ]] ||
					die "$file:$lineno: 'platforms' must be a comma-separated string on one line, e.g. 'platforms: linux/amd64,linux/arm64' (a YAML block list is not supported)"
				CFG_PLATFORMS=$val
				;;
			build_args)
				[[ -z $val ]] ||
					die "$file:$lineno: 'build_args' must be a list of '- KEY=value' lines, not an inline value"
				seen_args=1
				;;
			*)
				die "$file:$lineno: unknown key '$key' (supported: image, platforms, build_args)"
				;;
			esac
		elif [[ $line =~ ^[[:space:]]+-[[:space:]]*(.*)$ ]]; then
			val=$(trim "${BASH_REMATCH[1]}")
			[[ $current_key == build_args && $seen_args -eq 1 ]] ||
				die "$file:$lineno: list item '- $val' does not belong to a 'build_args:' block"
			CFG_BUILD_ARGS+="${CFG_BUILD_ARGS:+$'\n'}$val"
		else
			die "$file:$lineno: cannot parse '$line' (see docs/ci.md for the supported ci.yaml subset)"
		fi
	done <"$file"

	validate_app_config "$app" "$file"
}

# validate_app_config <app> <file>
# Rejects values that would be unsafe to interpolate into JSON, a shell command
# or a registry reference. Being strict here is what lets the rest of the
# pipeline build JSON without jq.
validate_app_config() {
	local app=$1 file=$2

	[[ $CFG_IMAGE =~ ^[a-z0-9][a-z0-9._/-]*$ ]] ||
		die "$file: image '$CFG_IMAGE' is not a valid Docker repository name (lowercase alphanumerics, '.', '_', '-', '/')"

	local p
	local -a _plats
	IFS=, read -r -a _plats <<<"$CFG_PLATFORMS"
	((${#_plats[@]} > 0)) || die "$file: platforms must not be empty"
	for p in "${_plats[@]}"; do
		p=$(trim "$p")
		[[ $p =~ ^linux/[a-z0-9]+(/v[0-9]+)?$ ]] ||
			die "$file: platform '$p' is not valid (expected e.g. linux/amd64, linux/arm64, linux/arm/v7)"
	done

	local a
	while IFS= read -r a; do
		[[ -z $a ]] && continue
		[[ $a =~ ^[A-Za-z_][A-Za-z0-9_]*=[^\"\\]*$ ]] ||
			die "$file: build arg '$a' must be KEY=value and must not contain quotes or backslashes"
	done <<<"$CFG_BUILD_ARGS"
}

# json_escape_newlines <string> -> the string with real newlines replaced by \n.
# Safe because validate_app_config already rejected quotes and backslashes.
json_escape_newlines() {
	local s=$1
	printf '%s' "${s//$'\n'/\\n}"
}
