#!/usr/bin/env bash
# Pull-request governance checks, run once for every application folder the PR
# touches. Nothing here talks to a registry.
#
#   1. VERSION is well-formed semver.
#   2. If VERSION changed, CHANGES.md must have changed in the same PR.
#      (The inverse - CHANGES.md alone - is explicitly allowed.)
#   3. If VERSION changed, the new value must be strictly greater than the one
#      on the base branch, by semver precedence (so 3.2.3-rc1 < 3.2.3).
#      Brand-new folders with no baseline are exempt.
#
# Inputs (environment): BASE_SHA, HEAD_SHA, REPORT (markdown output path)
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=.github/scripts/appconfig.sh
source "$script_dir/appconfig.sh"
# shellcheck source=.github/scripts/semver.sh
source "$script_dir/semver.sh"

: "${BASE_SHA:?BASE_SHA is required}"
HEAD_SHA=${HEAD_SHA:-HEAD}
REPORT=${REPORT:-.ci-report/validation.md}
mkdir -p "$(dirname "$REPORT")"

read_lines changed_files < <(git diff --name-only "$BASE_SHA" "$HEAD_SHA")

changed() {
	local target=$1 f
	for f in "${changed_files[@]-}"; do
		[[ $f == "$target" ]] && return 0
	done
	return 1
}

read_lines all_apps < <(list_apps)

declare -a apps=()
for app in "${all_apps[@]}"; do
	for f in "${changed_files[@]-}"; do
		[[ $f == "$app/"* ]] && {
			apps+=("$app")
			break
		}
	done
done

if ((${#apps[@]} == 0)); then
	echo "No application folders changed; nothing to validate." | tee -a "$REPORT"
	exit 0
fi

failures=0

{
	echo "| App | Version | Semver | Bumped | Changelog |"
	echo "| --- | --- | --- | --- | --- |"
} >>"$REPORT"

for app in "${apps[@]}"; do
	# read_version already fails hard on empty or multi-line files.
	version=$(read_version "$app")

	col_semver="n/a"
	col_bump="n/a"
	col_changes="n/a"
	app_failed=0

	# --- 1. well-formed semver ------------------------------------------------
	if semver_valid "$version"; then
		col_semver="✅"
	else
		col_semver="❌"
		app_failed=1
		echo "::error file=$app/VERSION::$app: '$version' is not valid semver. Expected MAJOR.MINOR.PATCH with an optional -prerelease / +build suffix, and no leading 'v'."
	fi

	if changed "$app/VERSION"; then
		# --- 2. changelog rule ------------------------------------------------
		if changed "$app/CHANGES.md"; then
			col_changes="✅"
		else
			col_changes="❌"
			app_failed=1
			echo "::error file=$app/CHANGES.md::$app: VERSION changed to '$version' but $app/CHANGES.md was not updated in this PR. Every version bump needs a changelog entry."
		fi

		# --- 3. monotonic version --------------------------------------------
		if ! semver_valid "$version"; then
			# Already reported as invalid above; comparing it would be meaningless.
			col_bump="⚠️"
		elif base_version=$(git show "$BASE_SHA:$app/VERSION" 2>/dev/null); then
			base_version=$(printf '%s' "$base_version" | tr -d '\r' | tr -d '[:space:]')
			if ! semver_valid "$base_version"; then
				# The baseline is malformed; we cannot compare, so don't block on it.
				col_bump="⚠️"
				echo "::warning file=$app/VERSION::$app: base version '$base_version' on the target branch is not valid semver, skipping the increase check."
			elif [[ $(semver_cmp "$version" "$base_version") == "1" ]]; then
				col_bump="✅"
			else
				col_bump="❌"
				app_failed=1
				echo "::error file=$app/VERSION::$app: version must increase. '$version' is not greater than '$base_version' on the target branch."
			fi
		else
			# New application folder: no baseline to compare against.
			col_bump="🆕"
		fi
	else
		# CHANGES.md edited without a VERSION bump is allowed by design.
		col_changes="—"
		col_bump="—"
	fi

	echo "| \`$app\` | \`$version\` | $col_semver | $col_bump | $col_changes |" >>"$REPORT"
	((app_failed)) && failures=$((failures + 1))
done

{
	echo ""
	echo "<sub>Semver = VERSION is well-formed · Bumped = greater than the base branch (🆕 = new app) · Changelog = CHANGES.md updated alongside VERSION (— = VERSION unchanged)</sub>"
} >>"$REPORT"

cat "$REPORT" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"

if ((failures > 0)); then
	echo "::error::$failures application folder(s) failed validation. See the annotations above."
	exit 1
fi

echo "All ${#apps[@]} changed application folder(s) passed validation."
