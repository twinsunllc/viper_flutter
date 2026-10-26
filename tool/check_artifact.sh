#!/usr/bin/env bash
# Checks a built Flutter artifact for Viper, in either direction (D336).
#
#   tool/check_artifact.sh <artifact> refuse   a production build: no Viper in it
#   tool/check_artifact.sh <artifact> expect   a staging build: Viper is in it
#
# <artifact> is a libapp.so, an App.framework (or the App binary inside one), or an .apk, .aab
# or .ipa holding them. The Dart AOT snapshot keeps string constants as plain bytes, so what the
# build can say is readable from the artifact itself:
#
#   - the implementation's marker, `viper-flutter-implementation`, a constant every call the
#     package makes sends, so it's in any build that can run Viper and in none that can't;
#   - the Viper host (VIPER_HOST, or --host; viper-volatile.twinsun.dev by default);
#   - the widget key (VIPER_KEY, or --key), when given.
#
# refuse fails if any Dart snapshot in the artifact has any of them. expect fails unless every
# snapshot has the marker, and the host and key when given. Exit 0 or 1; the messages name what
# was found, never the host's or the key's value. Debug builds have no AOT snapshot: check a
# release or profile build.
set -uo pipefail
# libapp.so is bytes, not text: grep byte-wise so a byte above 0x7F can't hide what follows it.
export LC_ALL=C

MARKER='viper-flutter-implementation'

usage() {
  echo "Usage: $0 <libapp.so|App.framework|App|.apk|.aab|.ipa> <expect|refuse> [--host <host>] [--key <key>]" >&2
  exit 2
}

fail() {
  echo "$1"
  [ "${GITHUB_ACTIONS:-}" = "true" ] && echo "::error::$1"
  exit 1
}

ARTIFACT=${1:-}
DIRECTION=${2:-}
[ -n "$ARTIFACT" ] && [ -n "$DIRECTION" ] || usage
shift 2
HOST=${VIPER_HOST:-https://viper-volatile.twinsun.dev}
KEY=${VIPER_KEY:-}
while [ $# -gt 0 ]; do
  case "$1" in
    --host) HOST=${2:-}; shift 2 ;;
    --key) KEY=${2:-}; shift 2 ;;
    *) usage ;;
  esac
done
case "$DIRECTION" in expect|refuse) ;; *) usage ;; esac
[ -e "$ARTIFACT" ] || fail "No artifact at $ARTIFACT"

# The host as it sits in the snapshot: the name, without a scheme or path.
HOST_NAME=$(printf '%s' "$HOST" | sed -E 's#^[a-z]+://##; s#[/?].*$##')

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Every Dart AOT snapshot in the artifact.
snapshots=()
case "$ARTIFACT" in
  *.apk|*.aab|*.ipa|*.zip)
    command -v unzip >/dev/null 2>&1 || fail "unzip is not installed; cannot read $ARTIFACT"
    unzip -qq -o "$ARTIFACT" -d "$WORK" 'lib/*/libapp.so' 'base/lib/*/libapp.so' 'Payload/*/Frameworks/App.framework/App' 2>/dev/null
    while IFS= read -r file; do snapshots+=("$file"); done < <(find "$WORK" -type f \( -name libapp.so -o -path '*App.framework/App' \) | sort)
    ;;
  *.framework)
    [ -f "$ARTIFACT/App" ] && snapshots+=("$ARTIFACT/App")
    ;;
  *)
    [ -f "$ARTIFACT" ] && snapshots+=("$ARTIFACT")
    ;;
esac
[ ${#snapshots[@]} -gt 0 ] || fail "No Dart snapshot (libapp.so or App.framework/App) in $ARTIFACT"

has() {  # has <file> <text>
  grep -F -a -q -- "$2" "$1"
}

problems=0
for snapshot in "${snapshots[@]}"; do
  name=${snapshot#"$WORK"/}
  marker=no; host=no; key=no
  has "$snapshot" "$MARKER" && marker=yes
  [ -n "$HOST_NAME" ] && has "$snapshot" "$HOST_NAME" && host=yes
  [ -n "$KEY" ] && has "$snapshot" "$KEY" && key=yes
  if [ "$DIRECTION" = refuse ]; then
    found=()
    [ $marker = yes ] && found+=("the implementation's marker")
    [ $host = yes ] && found+=("the Viper host")
    [ $key = yes ] && found+=("the widget key")
    if [ ${#found[@]} -gt 0 ]; then
      echo "$name has Viper in it: $(IFS=,; echo "${found[*]}" | sed 's/,/, /g')"
      problems=$((problems + 1))
    else
      echo "$name: no Viper"
    fi
  else
    missing=()
    [ $marker = no ] && missing+=("the implementation's marker")
    [ -n "$HOST_NAME" ] && [ $host = no ] && missing+=("the Viper host")
    [ -n "$KEY" ] && [ $key = no ] && missing+=("the widget key")
    if [ ${#missing[@]} -gt 0 ]; then
      echo "$name is missing $(IFS=,; echo "${missing[*]}" | sed 's/,/, /g')"
      problems=$((problems + 1))
    else
      echo "$name: Viper is in it"
    fi
  fi
done

if [ $problems -gt 0 ]; then
  if [ "$DIRECTION" = refuse ]; then
    fail "Refused: Viper is in a build that must not have it (D336)."
  fi
  fail "Refused: this build should carry Viper and doesn't. Was it built from main_staging.dart with --dart-define=VIPER=true?"
fi
echo "OK: ${#snapshots[@]} snapshot(s) checked ($DIRECTION)."
