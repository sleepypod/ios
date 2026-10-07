#!/bin/sh
# Release archive with stateless version stamping (same scheme as nana/peanut).
# Nothing tracked is edited: the build number and marketing version are passed
# to xcodebuild as overrides, so a cancelled archive never dirties the tree.
set -eu

# Minute-resolution stamp gives every archive a unique, monotonic CFBundleVersion.
# App Store Connect rejects a duplicate build number at upload, so never run two
# release archives within the same minute.
STAMP="$(date +%y%m%d%H%M)"

# MARKETING_VERSION comes from the latest reachable v* tag (v1.2.2 -> 1.2.2).
# Tags are cut by semantic-release on main; only three-part semver is accepted.
# With no valid tag, the static MARKETING_VERSION in project.yml ships.
SHORT="$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null | sed 's/^v//' || true)"
printf '%s' "$SHORT" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || SHORT=""
ARCHIVE_PATH="${1:-build/Sleepypod.xcarchive}"

# The pbxproj is tracked but generated; make sure it matches project.yml.
command -v xcodegen >/dev/null 2>&1 && xcodegen generate

xcodebuild -project Sleepypod.xcodeproj -scheme Sleepypod -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE_PATH" archive \
  -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$STAMP" ${SHORT:+MARKETING_VERSION="$SHORT"}

# A custom -archivePath alone does not show up in Organizer; copy it into
# Xcode's dated archive library so it can be uploaded from there.
ORGANIZER_DIR="$HOME/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)"
ORGANIZER_ARCHIVE="$ORGANIZER_DIR/sleepypod-${SHORT:-unversioned}-$STAMP.xcarchive"
mkdir -p "$ORGANIZER_DIR"
if [ "$ARCHIVE_PATH" != "$ORGANIZER_ARCHIVE" ]; then
  if [ -e "$ORGANIZER_ARCHIVE" ]; then
    echo "Organizer archive already exists; refusing to overwrite: $ORGANIZER_ARCHIVE" >&2
    exit 4
  fi
  ditto "$ARCHIVE_PATH" "$ORGANIZER_ARCHIVE"
fi
printf 'Build %s, version %s\nOrganizer archive: %s\n' "$STAMP" "${SHORT:-$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)}" "$ORGANIZER_ARCHIVE"

if [ -t 1 ]; then
  open "$ORGANIZER_ARCHIVE"
fi
