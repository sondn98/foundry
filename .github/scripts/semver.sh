#!/usr/bin/env bash
# Semantic-version helpers (https://semver.org), no external dependencies.
#
# Sourced by validate.sh and discover.sh. Deliberately dependency-free: the
# self-hosted ARC runner image only ships curl/git/tar/helm/kubectl/helmfile,
# so we cannot assume jq, yq or python3 are on PATH.

# Official semver regex, translated to POSIX ERE (\d -> [0-9]) for bash's =~.
SEMVER_RE='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*)(\.(0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*))*))?(\+([0-9a-zA-Z-]+(\.[0-9a-zA-Z-]+)*))?$'

# semver_valid <string> -> 0 if the string is a well-formed semver version.
semver_valid() {
	[[ $1 =~ $SEMVER_RE ]]
}

# semver_is_prerelease <version> -> 0 if the version carries a -prerelease part.
semver_is_prerelease() {
	local v=${1%%+*} # drop build metadata, it never contains '-' semantics we care about
	[[ $v == *-* ]]
}

# _semver_core <version> -> "major minor patch"
_semver_core() {
	local v=${1%%+*}
	v=${v%%-*}
	printf '%s %s %s' "${v%%.*}" "$(cut -d. -f2 <<<"$v")" "${v##*.}"
}

# _semver_prerelease <version> -> the prerelease string, or "" when absent.
_semver_prerelease() {
	local v=${1%%+*}
	[[ $v == *-* ]] && printf '%s' "${v#*-}"
}

# semver_cmp <a> <b> -> prints -1 (a<b), 0 (a==b) or 1 (a>b).
# Implements semver precedence: build metadata is ignored, and a version with a
# prerelease sorts *before* the same version without one (1.0.0-rc1 < 1.0.0).
semver_cmp() {
	local a=$1 b=$2
	local -a ac bc
	read -r -a ac <<<"$(_semver_core "$a")"
	read -r -a bc <<<"$(_semver_core "$b")"

	local i
	for i in 0 1 2; do
		if ((10#${ac[i]} > 10#${bc[i]})); then
			echo 1
			return
		elif ((10#${ac[i]} < 10#${bc[i]})); then
			echo -1
			return
		fi
	done

	local ap bp
	ap=$(_semver_prerelease "$a")
	bp=$(_semver_prerelease "$b")

	# No prerelease outranks a prerelease; two absent prereleases are equal.
	if [[ -z $ap && -z $bp ]]; then
		echo 0
		return
	elif [[ -z $ap ]]; then
		echo 1
		return
	elif [[ -z $bp ]]; then
		echo -1
		return
	fi

	# Compare dot-separated identifiers left to right.
	local -a ai bi
	IFS=. read -r -a ai <<<"$ap"
	IFS=. read -r -a bi <<<"$bp"

	local n=${#ai[@]}
	((${#bi[@]} > n)) && n=${#bi[@]}

	for ((i = 0; i < n; i++)); do
		local x=${ai[i]-} y=${bi[i]-}
		# A shorter set of identifiers sorts lower when all preceding are equal.
		if [[ -z $x ]]; then
			echo -1
			return
		fi
		if [[ -z $y ]]; then
			echo 1
			return
		fi
		[[ $x == "$y" ]] && continue

		if [[ $x =~ ^[0-9]+$ && $y =~ ^[0-9]+$ ]]; then
			# Both numeric: compare numerically.
			if ((10#$x > 10#$y)); then echo 1; else echo -1; fi
			return
		elif [[ $x =~ ^[0-9]+$ ]]; then
			# Numeric identifiers always sort lower than alphanumeric ones.
			echo -1
			return
		elif [[ $y =~ ^[0-9]+$ ]]; then
			echo 1
			return
		else
			# Both alphanumeric: ASCII sort order.
			if [[ $x > $y ]]; then echo 1; else echo -1; fi
			return
		fi
	done

	echo 0
}
