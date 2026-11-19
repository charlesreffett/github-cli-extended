#!/usr/bin/env bash
# Tests for gh-multi using a stub gh binary.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wrapper="$root/bin/gh-multi"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Stub gh: `auth token --user X` prints token-X; `auth status --json ... --jq` lists
# logins (alice is active); anything else echoes args and GH_TOKEN.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'EOF'
#!/usr/bin/env bash
if [[ "$1 $2 $3" == "auth status --json" ]]; then
  if [[ "$*" == *select* ]]; then echo alice; else printf '%s\n' alice bob carol dave erin frank; fi
  exit 0
fi
if [[ "$1 $2" == "auth token" ]]; then
  while [[ $# -gt 0 ]]; do
    [[ "$1" == "--user" ]] && { [[ "$2" == "missing" ]] && exit 1; echo "token-$2"; exit 0; }
    shift
  done
  exit 1
fi
echo "token=${GH_TOKEN:-none} args=$*"
EOF
chmod +x "$tmp/bin/gh"

export GH_MULTI_REAL_GH="$tmp/bin/gh"
export XDG_CONFIG_HOME="$tmp/config"
unset GH_ACCOUNT GH_TOKEN GH_HOST

pass=0 fail=0
check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    echo "FAIL: $name"
    echo "  expected: $expected"
    echo "  actual:   $actual"
  fi
}

work="$tmp/work"
mkdir -p "$work"
cd "$work"

check "no account passes through" \
  "token=none args=pr list" "$("$wrapper" pr list)"

check "--as flag" \
  "token=token-alice args=pr list" "$("$wrapper" --as alice pr list)"

check "--as= flag" \
  "token=token-alice args=repo view" "$("$wrapper" --as=alice repo view)"

check "GH_ACCOUNT env" \
  "token=token-bob args=issue list" "$(GH_ACCOUNT=bob "$wrapper" issue list)"

check "--as beats GH_ACCOUNT" \
  "token=token-alice args=issue list" "$(GH_ACCOUNT=bob "$wrapper" --as alice issue list)"

check "auth subcommand passes through" \
  "token=none args=auth status" "$("$wrapper" --as alice auth status)"

check "auth git-credential gets token" \
  "token=token-alice args=auth git-credential get" "$("$wrapper" --as alice auth git-credential get)"

check "--as later in args is not consumed" \
  "token=none args=api /user --as x" "$("$wrapper" api /user --as x)"

mkdir -p "$XDG_CONFIG_HOME/gh-multi"
cat > "$XDG_CONFIG_HOME/gh-multi/accounts" <<'EOF2'
# pattern            account
*                    frank
acme-corp            dave
acme-corp/side-gig   erin
EOF2

mkrepo() {
  local repo="$work/repo-$RANDOM$RANDOM"
  git init -q "$repo"
  git -C "$repo" remote add origin "$1"
  echo "$repo"
}

for url in https://github.com/Acme-Corp/app.git git@github.com:acme-corp/app.git ssh://git@github.com/acme-corp/app; do
  repo="$(mkrepo "$url")"
  check "owner mapping ($url)" \
    "token=token-dave args=pr list" "$(cd "$repo" && "$wrapper" pr list)"
done

for url in https://github.com/acme-corp/side-gig.git git@github.com:Acme-Corp/Side-Gig.git; do
  repo="$(mkrepo "$url")"
  check "repo mapping beats owner ($url)" \
    "token=token-erin args=pr list" "$(cd "$repo" && "$wrapper" pr list)"
done

repo="$(mkrepo https://github.com/acme-corp/side-gig-2.git)"
check "repo mapping is exact, not prefix" \
  "token=token-dave args=pr list" "$(cd "$repo" && "$wrapper" pr list)"

repo="$(mkrepo https://github.com/someone-else/repo.git)"
check "unmapped repo uses * default" \
  "token=token-frank args=pr list" "$(cd "$repo" && "$wrapper" pr list)"

check "outside a repo uses * default" \
  "token=token-frank args=repo list" "$("$wrapper" repo list)"

repo="$(mkrepo https://github.com/acme-corp/app.git)"
check "GH_ACCOUNT beats config" \
  "token=token-bob args=pr list" "$(cd "$repo" && GH_ACCOUNT=bob "$wrapper" pr list)"

sed -i '' '/^\*/d' "$XDG_CONFIG_HOME/gh-multi/accounts"
repo="$(mkrepo https://github.com/someone-else/repo.git)"
check "no match and no default passes through" \
  "token=none args=pr list" "$(cd "$repo" && "$wrapper" pr list)"

# --- gh account subcommands ---
export XDG_CONFIG_HOME="$tmp/config2"
cfg="$XDG_CONFIG_HOME/gh-multi/accounts"
repo="$(mkrepo git@github.com:Acme-Corp/App.git)"

check "account which with no config" \
  "(gh active account)" "$(cd "$repo" && "$wrapper" account)"

check "account list with no config" \
  "Logged in on github.com:
  alice (gh active account)
  bob
  carol
  dave
  erin
  frank

Mappings in $cfg:
  (none)" "$("$wrapper" account list)"

check "account use maps current repo" \
  "Acme-Corp/App → bob" "$(cd "$repo" && "$wrapper" account use bob)"

check "mapped repo uses account" \
  "token=token-bob args=pr list" "$(cd "$repo" && "$wrapper" pr list)"

check "account which reports pattern" \
  "bob (config: Acme-Corp/App)" "$(cd "$repo" && "$wrapper" account which)"

check "account use replaces existing mapping (case-insensitive)" \
  "acme-corp/app → carol" "$(cd "$repo" && "$wrapper" account use carol --for acme-corp/app)"

check "account use stores login as gh spells it" \
  "acme-corp/app → carol" "$(cd "$repo" && "$wrapper" account use CAROL --for acme-corp/app)"

check "config has one line per pattern" \
  "1" "$(grep -ci 'acme-corp/app' "$cfg")"

check "account use --owner" \
  "Acme-Corp → dave" "$(cd "$repo" && "$wrapper" account use dave --owner)"

check "account use --default works outside a repo" \
  "* → erin" "$("$wrapper" account use erin --default)"

check "account list marks the mapping in effect" \
  "→ acme-corp/app  carol
  Acme-Corp      dave
  *              erin" "$(cd "$repo" && "$wrapper" account list | tail -n 3)"

check "account forget removes current repo mapping" \
  "removed Acme-Corp/App" "$(cd "$repo" && "$wrapper" account forget)"

check "owner mapping applies after forget" \
  "dave (config: Acme-Corp)" "$(cd "$repo" && "$wrapper" account)"

echo "# keep me" >> "$cfg"
"$wrapper" account forget --default >/dev/null
check "forget keeps comments and other lines" \
  "Acme-Corp                dave
# keep me" "$(cat "$cfg")"

check_fails() {
  local name="$1" expected="$2"
  shift 2
  local out
  if out="$("$@" 2>&1)"; then
    check "$name" "nonzero exit" "exit 0"
  else
    check "$name" "$expected" "$out"
  fi
}

check "account use with several --for" \
  "Widgets/widget-a → bob
Widgets/widget-b → bob" "$("$wrapper" account use bob --for Widgets/widget-a --for Widgets/widget-b)"

repo2="$(mkrepo https://github.com/Widgets/widget-b.git)"
check "each --for pattern applies" \
  "bob (config: Widgets/widget-b)" "$(cd "$repo2" && "$wrapper" account)"

check "account use --repo --owner together" \
  "Widgets/widget-b → carol
Widgets → carol" "$(cd "$repo2" && "$wrapper" account use carol --repo --owner)"

check_fails "account forget is all-or-nothing" \
  "gh-multi: no mapping for 'Widgets/nope' in $cfg" \
  "$wrapper" account forget --for Widgets/widget-a --for Widgets/nope

check "failed forget left mappings alone" \
  "1" "$(grep -c '^Widgets/widget-a ' "$cfg")"

check "account forget with several --for" \
  "removed Widgets/widget-a
removed Widgets/widget-b" "$("$wrapper" account forget --for Widgets/widget-a --for Widgets/widget-b)"

check_fails "--for needs a value" \
  "gh-multi: --for requires a pattern (owner/repo, owner or *)" \
  "$wrapper" account use bob --for --default

check_fails "account use rejects unknown login" \
  "gh-multi: 'mallory' is not logged in on github.com; run: gh auth login (logged in: alice,bob,carol,dave,erin,frank)" \
  "$wrapper" account use mallory --default

check_fails "account use outside a repo needs a target" \
  "gh-multi: not in a repo with an origin remote; use --for <pattern> or --default" \
  "$wrapper" account use bob

check_fails "account forget with no mapping" \
  "gh-multi: no mapping for '*' in $cfg" \
  "$wrapper" account forget --default

check_fails "account rejects unknown subcommand" \
  "gh-multi: unknown command: gh account nope (see: gh account help)" \
  "$wrapper" account nope

check "--which reports source" \
  "alice (--as flag)" "$("$wrapper" --as alice --which)"

check "--which with no account" \
  "(gh active account)" "$("$wrapper" --which)"

if out="$("$wrapper" --as missing pr list 2>&1)"; then
  check "missing account fails" "nonzero exit" "exit 0"
else
  check "missing account fails" \
    "gh-multi: no token for account 'missing' on github.com (from --as flag); run: gh auth login" "$out"
fi

echo "$pass passed, $fail failed"
[[ $fail -eq 0 ]]
