#!/bin/sh
# Black-box native helper smoke checks; expanded resource cases follow.
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cc -std=c11 -O2 -Wall -Wextra -Werror "$root/priv/pdf_runner.c" -o /tmp/lens-pdf-native-check
work=$(mktemp -d)
trap 'rm -rf "$work" /tmp/lens-pdf-native-check' EXIT
cat > "$work/extractor" <<'EXTRACTOR'
#!/bin/sh
if [ "$1" = -v ]; then printf 'fixture 1\n'; exit 0; fi
printf 'Revenue\n\nProfit' > "$7"
EXTRACTOR
chmod 700 "$work/extractor"
printf 'PDF fixture' > "$work/input.pdf"
mkfifo "$work/owner"
exec 3<> "$work/owner"
result=$(/tmp/lens-pdf-native-check "$work/extractor" "$work/input.pdf" "$work/text" "$work/version" 2000 1024 < "$work/owner")
[ "$result" = ok ]
[ "$(cat "$work/text")" = "$(printf 'Revenue\n\nProfit')" ]
[ "$(cat "$work/version")" = 'fixture 1' ]
# Overflow precedes nonzero exit and the result never carries text.
cat > "$work/extractor" <<'EXTRACTOR'
#!/bin/sh
if [ "$1" = -v ]; then printf 'fixture 1\n'; exit 0; fi
printf '12345' > "$7"
exit 1
EXTRACTOR
result=$(/tmp/lens-pdf-native-check "$work/extractor" "$work/input.pdf" "$work/text" "$work/version" 2000 4 < "$work/owner")
[ "$result" = output_limit ]
rm "$work/text"
cat > "$work/extractor" <<'EXTRACTOR'
#!/bin/sh
if [ "$1" = -v ]; then printf 'fixture 1\n'; exit 0; fi
sleep 30
EXTRACTOR
result=$(/tmp/lens-pdf-native-check "$work/extractor" "$work/input.pdf" "$work/text" "$work/version" 100 1024 < "$work/owner")
[ "$result" = timeout ]
# Closing the caller pipe requests cancellation before the phase deadline.
result=$(/tmp/lens-pdf-native-check "$work/extractor" "$work/input.pdf" "$work/text" "$work/version" 2000 1024 < /dev/null)
[ "$result" = process_error ]
cc -std=c11 -O2 -Wall -Wextra -Werror "$root/test/fixtures/pdf_process_fixture.c" -o "$work/process-fixture"
export LENS_FIXTURE_MARKER="$work/marker" LENS_FIXTURE_PID="$work/child-pid"
for mode in child probe_child timeout_child probe_timeout; do
  export LENS_FIXTURE_MODE="$mode"
  rm -f "$work/marker" "$work/child-pid"
  timeout=2000
  case "$mode" in *timeout*) timeout=100;; esac
  result=$(/tmp/lens-pdf-native-check "$work/process-fixture" "$work/input.pdf" "$work/text" "$work/version" "$timeout" 1024 < "$work/owner")
  case "$mode" in *timeout*) [ "$result" = timeout ];; *) [ "$result" = ok ];; esac
  sleep 0.75
  [ ! -e "$work/marker" ]
  [ ! -e "/proc/$(cat "$work/child-pid")" ]
done
for mode in limits memory cpu; do
  export LENS_FIXTURE_MODE="$mode"
  result=$(/tmp/lens-pdf-native-check "$work/process-fixture" "$work/input.pdf" "$work/text" "$work/version" 2000 1024 < "$work/owner")
  case "$mode" in limits) [ "$result" = ok ];; memory) [ "$result" = unreadable ];; cpu) [ "$result" = unreadable ] || [ "$result" = timeout ];; esac
done
printf 'native helper process checks passed\n'  
