#!/bin/sh
# Self-check for bin/neuraldeep's normalization. Stubs curl, so it runs
# offline and never needs a real key.
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

mkdir -p "$tmp/bin"
cat > "$tmp/bin/curl" <<'CURL'
#!/bin/sh
for last; do :; done
case "$last" in
  */limits) cat "$FIXTURES/limits.json" ;;
  */models) cat "$FIXTURES/models.json" ;;
  *) exit 22 ;;
esac
CURL
chmod +x "$tmp/bin/curl"

cat > "$tmp/limits.json" <<'JSON'
{
  "observed_at": "2026-11-06T14:10:08Z",
  "tier": "free",
  "key": { "name": "primary", "status": "ok", "billing_mode": "wallet" },
  "chat": { "session": { "used": null, "limit": null } },
  "parallel_limit": 16,
  "daily_capacity": { "pct_used": 12.5, "exhausted": false, "resets_at": "2026-11-07T00:00:00+00:00" },
  "night": { "enabled": true, "active": false },
  "wallet": { "balance_rub": 2297.282463, "spent_rub_30d": 1202.717762 }
}
JSON

cat > "$tmp/models.json" <<'JSON'
{
  "data": [
    { "id": "expensive", "type": "chat", "limit": { "context": 1000000 }, "pricing": { "input_per_1m": 12.75, "output_per_1m": 63.75 } },
    { "id": "cheap", "type": "chat", "limit": { "context": 262144 }, "pricing": { "input_per_1m": 0.111563, "output_per_1m": 0.6375 } },
    { "id": "embed", "type": "embedding", "pricing": { "input_per_1m": 3.12, "output_per_1m": 0 } }
  ]
}
JSON

export FIXTURES="$tmp"
out=$(PATH="$tmp/bin:$PATH" NEURALDEEP_API_KEY=test \
  NEURALDEEP_BASE_URL=https://example.test/v1 "$here/bin/neuraldeep")

echo "$out" | jq -e '.ok == true' >/dev/null || { echo "FAIL ok"; exit 1; }
echo "$out" | jq -e '.wallet.balance == 2297.282463' >/dev/null || { echo "FAIL balance"; exit 1; }
echo "$out" | jq -e '.daily.pct == 12.5' >/dev/null || { echo "FAIL daily pct"; exit 1; }
echo "$out" | jq -e '.parallelLimit == 16' >/dev/null || { echo "FAIL parallel"; exit 1; }
echo "$out" | jq -e '.models | length == 2' >/dev/null || { echo "FAIL chat-only filter"; exit 1; }
echo "$out" | jq -e '.models[0].id == "cheap" and .models[1].id == "expensive"' >/dev/null \
  || { echo "FAIL price sort"; exit 1; }

out=$(NEURALDEEP_OPENCODE_CONFIG="$tmp/missing.json" NEURALDEEP_API_KEY= \
  "$here/bin/neuraldeep")
echo "$out" | jq -e '.ok == false and .error == "no-key"' >/dev/null \
  || { echo "FAIL no-key path"; exit 1; }

printf 'sk-file\n' > "$tmp/key"
out=$(PATH="$tmp/bin:$PATH" NEURALDEEP_API_KEY= NEURALDEEP_KEY_FILE="$tmp/key" \
  NEURALDEEP_OPENCODE_CONFIG="$tmp/missing.json" NEURALDEEP_BASE_URL=https://example.test/v1 \
  "$here/bin/neuraldeep")
echo "$out" | jq -e '.ok == true' >/dev/null \
  || { echo "FAIL key-file path"; exit 1; }

echo "neuraldeep: ok"