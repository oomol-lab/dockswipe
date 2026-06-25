#!/bin/bash
# Compute the version for a stable release from git tags.
#
# This project ships stable releases only — there is no beta/nightly channel.
# Local builds are always 0.0.0-development (Makefile default); real versions
# exist only in CI, derived from tags by this script. Requires the full tag
# list (checkout with fetch-depth: 0 + fetch-tags: true).
#
# Usage:
#   compute_version.sh
#     env: EXPECTED_VERSION  optional explicit version (1.2.3; a leading "v" is
#                            accepted). Empty -> auto-bump from the latest tag.
#                            An explicit stable version may only move forward:
#                            it must be >= the latest tag (a newer-created
#                            release would otherwise steal "Latest").
#          VERSION_BUMP      segment to bump when EXPECTED_VERSION is empty:
#                            patch | minor | major (default patch).
#
# Output (appended to $GITHUB_OUTPUT when set, always echoed):
#   version=1.2.3   display version (baked into the binary as DOCKSWIPE_VERSION)
#   tag=v1.2.3      git tag / GitHub Release tag
set -euo pipefail

# Numeric segments reject leading zeros ("01" would later be read as octal by
# bash arithmetic).
NUM='(0|[1-9][0-9]*)'
VERSION_RE="^${NUM}\.${NUM}\.${NUM}$"

# Newest tag that is exactly vX.Y.Z.
latest_stable() {
	git tag -l 'v*' --sort=-v:refname \
		| grep -E "^v${NUM}\.${NUM}\.${NUM}$" \
		| head -n1 \
		|| true
}

expected="${EXPECTED_VERSION:-}"
bump="${VERSION_BUMP:-patch}"

if [ -n "$expected" ]; then
	version="${expected#v}"
	if ! [[ "$version" =~ $VERSION_RE ]]; then
		echo "error: version must be X.Y.Z (got '$expected')" >&2
		exit 1
	fi
	# A stable explicit version may only move forward (no backfills).
	latest="$(latest_stable)"
	latest="${latest#v}"
	if [ -n "$latest" ] && [ "$version" != "$(printf '%s\n%s\n' "$latest" "$version" | sort -V | tail -n1)" ]; then
		echo "error: $version is not newer than the latest release $latest (backfill releases are not supported)" >&2
		exit 1
	fi
else
	base="$(latest_stable)"
	base="${base#v}"
	base="${base:-0.0.0}"
	IFS=. read -r major minor patch <<<"$base"
	case "$bump" in
	major) version="$((major + 1)).0.0" ;;
	minor) version="${major}.$((minor + 1)).0" ;;
	patch) version="${major}.${minor}.$((patch + 1))" ;;
	*)
		echo "error: unsupported bump '$bump'" >&2
		exit 1
		;;
	esac
fi

tag="v${version}"
git check-ref-format "refs/tags/${tag}" || {
	echo "error: '${tag}' is not a valid tag name" >&2
	exit 1
}
if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
	# Allow re-dispatching the same version for the same commit: a publish run
	# that failed after its tag was created can be retried verbatim.
	if [ "$(git rev-parse "refs/tags/${tag}^{commit}")" = "$(git rev-parse HEAD)" ]; then
		echo "warning: tag ${tag} already exists and points at HEAD — re-publishing it" >&2
	else
		echo "error: tag ${tag} already exists (and points at a different commit)" >&2
		exit 1
	fi
fi

out="version=${version}
tag=${tag}"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
	echo "$out" >>"$GITHUB_OUTPUT"
fi
echo "$out"
