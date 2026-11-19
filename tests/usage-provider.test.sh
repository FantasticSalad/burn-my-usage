#!/usr/bin/env bash
set -u
s=$(cd "$(dirname "$0")/../skills/burn-my-usage/scripts" && pwd)
# The same folder for Node, a native program: Git Bash doesn't convert a path with an
# apostrophe in it for one (tests/odd-path.test.sh).
sn=$s
command -v cygpath >/dev/null 2>&1 && sn=$(cygpath -m "$s")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export BURN_MY_USAGE_HOME="$tmp/home" BMU_HOST=codex
fail=0
check() { if ! eval "$2"; then echo "FAIL: $1"; fail=$((fail+1)); fi; }
mkdir -p "$BURN_MY_USAGE_HOME"
now=$(date +%s)
printf '{"captured_at":%s,"rate_limits":{"seven_day":{"used_percentage":5,"resets_at":%s}}}\n' "$now" "$((now+3600))" >"$BURN_MY_USAGE_HOME/usage.json"
out=$(node "$sn/usage-codex.mjs" read)
check 'Claude data cannot satisfy Codex' '[[ $out == *verdict=unknown* ]]'
if command -v node >/dev/null 2>&1; then
response() { printf '{"id":1,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":90,"windowDurationMins":10080,"resetsAt":%s},"secondary":{"usedPercent":5,"windowDurationMins":300,"resetsAt":%s}}}}' "$((now+3600))" "$((now+1800))"; }
response | node "$sn/usage-codex.mjs" ingest >/dev/null
out=$(node "$sn/usage-codex.mjs" read)
check 'weekly detected by duration and stop enforced' '[[ $out == *verdict=stop* && $out == *weekly_used=90* ]]'
printf '{"method":"account/rateLimits/updated","params":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":100,"windowDurationMins":300,"resetsAt":%s},"secondary":{"usedPercent":10,"windowDurationMins":10080,"resetsAt":%s}}}}' "$((now+1800))" "$((now+3600))" | node "$sn/usage-codex.mjs" ingest >/dev/null
out=$(node "$sn/usage-codex.mjs" read)
check 'short window can stop the run' '[[ $out == *verdict=stop* && $out == *limiting_window_minutes=300* ]]'
printf '{bad' | node "$sn/usage-codex.mjs" ingest >/dev/null 2>&1 || true
out=$(node "$sn/usage-codex.mjs" read)
check 'malformed update invalidates prior snapshot' '[[ $out == *verdict=unknown* ]]'
printf '{"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":10,"windowDurationMins":300,"resetsAt":%s}}}}' "$((now+1800))" | node "$sn/usage-codex.mjs" ingest >/dev/null 2>&1 || true
out=$(node "$sn/usage-codex.mjs" read)
check 'missing weekly is unknown' '[[ $out == *verdict=unknown* ]]'
response | node "$sn/usage-codex.mjs" ingest >/dev/null
node -e 'const fs=require("fs"),p=process.argv[1],s=JSON.parse(fs.readFileSync(p));s.capturedAt-=7200;fs.writeFileSync(p,JSON.stringify(s))' "$BURN_MY_USAGE_HOME/usage/codex.json"
out=$(node "$sn/usage-codex.mjs" read)
check 'stale snapshot unknown' '[[ $out == *verdict=unknown* ]]'
else
  echo 'SKIP optional Codex quota fixtures: Node 18+ is not installed'
fi
export BMU_HOST=claude-code
printf '{"captured_at":%s,"rate_limits":{"seven_day":{"used_percentage":1e2,"resets_at":%s}}}\n' "$now" "$((now+3600))" >"$BURN_MY_USAGE_HOME/usage.json"
out=$(bash "$s/usage.sh")
check 'Claude exponent is unknown instead of truncated' '[[ $out == *verdict=unknown* ]]'
printf '{"captured_at":%s,"rate_limits":{"seven_day":{"used_percentage":10,"resets_at":%s},"five_hour":{"used_percentage":100,"resets_at":%s}}}\n' "$now" "$((now+3600))" "$((now+1800))" >"$BURN_MY_USAGE_HOME/usage.json"
out=$(bash "$s/usage.sh")
check 'Claude exhausted short window stops' '[[ $out == *verdict=stop* ]]'
printf '{"captured_at":%s,"rate_limits":{"seven_day":{"used_percentage":10,"resets_at":%s},"five_hour":{"used_percentage":"bad"}}}\n' "$now" "$((now+3600))" >"$BURN_MY_USAGE_HOME/usage.json"
out=$(bash "$s/usage.sh")
check 'malformed optional window unknown' '[[ $out == *verdict=unknown* ]]'
printf '{"pro\\u0076ider":"codex","captured_at":%s,"rate_limits":{"seven_day":{"used_percentage":10,"resets_at":%s}}}\n' "$now" "$((now+3600))" >"$BURN_MY_USAGE_HOME/usage.json"
out=$(bash "$s/usage.sh")
check 'escaped provider key is refused' '[[ $out == *verdict=unknown* ]]'
printf '{"captured_at":%s,"rate_limits":{"seven_day":{"used_percentage":10,"resets_at":%s}}}\n' "$((now+30))" "$((now+3600))" >"$BURN_MY_USAGE_HOME/usage.json"
out=$(bash "$s/usage.sh")
check 'future capture is unknown' '[[ $out == *verdict=unknown* ]]'
echo "usage provider failures: $fail"
[ "$fail" = 0 ]
