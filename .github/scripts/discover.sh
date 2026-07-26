#!/usr/bin/env bash
# Decide which application folders this run should act on, and emit them as a
# JSON matrix for the build job.
#
# Inputs (environment):
#   EVENT          github.event_name: pull_request | push | workflow_dispatch
#   BASE_SHA       commit to diff against (empty for workflow_dispatch)
#   HEAD_SHA       commit being tested
#   INPUT_APP      workflow_dispatch: single app to target, or "" for all
#   INPUT_PUBLISH  workflow_dispatch: "true" to allow pushing to the registry
#   REGISTRY       e.g. docker.io
#   NAMESPACE      e.g. sondn98
#
# Outputs (to $GITHUB_OUTPUT):
#   matrix   JSON array of {app, version, image, platforms, build_args}
#   count    number of entries in the matrix
#   publish  "true" when this run is allowed to push images
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=.github/scripts/appconfig.sh
source "$script_dir/appconfig.sh"

: "${EVENT:?EVENT is required}"
: "${REGISTRY:?REGISTRY is required}"
: "${NAMESPACE:?NAMESPACE is required}"
INPUT_APP=${INPUT_APP:-}
INPUT_PUBLISH=${INPUT_PUBLISH:-false}
BASE_SHA=${BASE_SHA:-}
HEAD_SHA=${HEAD_SHA:-HEAD}

summary() { printf '%s\n' "$*" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"; }

# Only a push to master (a merged PR) or an explicit dispatch may publish.
# Pull requests can never write to the registry.
case $EVENT in
push) publish=true ;;
workflow_dispatch) publish=$INPUT_PUBLISH ;;
*) publish=false ;;
esac

read_lines all_apps < <(list_apps)
((${#all_apps[@]} > 0)) || die "no application folders found (expected top-level dirs with a Dockerfile and a VERSION)"

# ---------------------------------------------------------------------------
# Work out the candidate set.
# ---------------------------------------------------------------------------
declare -a candidates=()
declare -a changed_files=()

if [[ $EVENT == workflow_dispatch ]]; then
	# Manual escape hatch: no change detection, the operator picked the target.
	if [[ -n $INPUT_APP ]]; then
		printf '%s\n' "${all_apps[@]}" | grep -qxF "$INPUT_APP" ||
			die "app '$INPUT_APP' not found; known apps: ${all_apps[*]}"
		candidates=("$INPUT_APP")
	else
		candidates=("${all_apps[@]}")
	fi
else
	[[ -n $BASE_SHA ]] || die "BASE_SHA is required for $EVENT runs"
	read_lines changed_files < <(git diff --name-only "$BASE_SHA" "$HEAD_SHA")

	for app in "${all_apps[@]}"; do
		for f in "${changed_files[@]-}"; do
			[[ $f == "$app/"* ]] && {
				candidates+=("$app")
				break
			}
		done
	done
fi

# ---------------------------------------------------------------------------
# Build the matrix.
# ---------------------------------------------------------------------------
version_changed() {
	local app=$1 f
	for f in "${changed_files[@]-}"; do
		[[ $f == "$app/VERSION" ]] && return 0
	done
	return 1
}

entries=""
skipped=""

for app in "${candidates[@]-}"; do
	[[ -z $app ]] && continue

	version=$(read_version "$app")
	parse_app_config "$app"

	# On a push to master we only publish when VERSION actually moved. An
	# unrelated Dockerfile tweak with a stale VERSION is a no-op, by design.
	if [[ $EVENT == push ]] && ! version_changed "$app"; then
		skipped+="- \`$app\` — files changed but \`VERSION\` did not (still \`$version\`), nothing to publish"$'\n'
		continue
	fi

	# A ci.yaml image containing '/' is treated as already namespaced.
	if [[ $CFG_IMAGE == */* ]]; then
		image="$CFG_IMAGE"
	else
		image="$NAMESPACE/$CFG_IMAGE"
	fi

	entries+="${entries:+,}{\"app\":\"$app\",\"version\":\"$version\",\"image\":\"$REGISTRY/$image\",\"platforms\":\"$CFG_PLATFORMS\",\"build_args\":\"$(json_escape_newlines "$CFG_BUILD_ARGS")\"}"
	count=$((${count:-0} + 1))
done

matrix="[$entries]"
count=${count:-0}

{
	echo "matrix=$matrix"
	echo "count=$count"
	echo "publish=$publish"
} >>"${GITHUB_OUTPUT:-/dev/stdout}"

# ---------------------------------------------------------------------------
# Human-readable summary so the run page answers "what did this touch?".
# ---------------------------------------------------------------------------
summary "## Discovery"
summary ""
summary "Event: \`$EVENT\` · publish: \`$publish\` · apps found in repo: \`${#all_apps[@]}\`"
summary ""

if ((count == 0)); then
	summary "**No application folders selected for this run.**"
else
	summary "| App | Version | Image | Platforms |"
	summary "| --- | --- | --- | --- |"
	for app in "${candidates[@]-}"; do
		[[ -z $app ]] && continue
		[[ $EVENT == push ]] && ! version_changed "$app" && continue
		version=$(read_version "$app")
		parse_app_config "$app"
		if [[ $CFG_IMAGE == */* ]]; then image="$CFG_IMAGE"; else image="$NAMESPACE/$CFG_IMAGE"; fi
		summary "| \`$app\` | \`$version\` | \`$REGISTRY/$image\` | \`$CFG_PLATFORMS\` |"
	done
fi

if [[ -n $skipped ]]; then
	summary ""
	summary "**Skipped:**"
	summary ""
	summary "$skipped"
fi

echo "matrix=$matrix"
echo "count=$count publish=$publish"
