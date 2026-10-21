#!/bin/sh
# usage: swiftlint-ratchet.sh [check|update|selftest]
#   check    새 위반이 있거나, 기준 파일에 고친 위반이 남았거나, 기준 파일이 BASE_REF 보다 늘었으면 실패
#   update   지금 위반으로 기준 파일을 다시 쓴다
#   selftest 규칙마다 Violations.swift 에서 잡히고 Clean.swift 에서 0건인지
set -eu

cd "$(git rev-parse --show-toplevel)"
baseline=.swiftlint-baseline.json
fixtures=.github/swiftlint-fixtures
reporter="${SWIFTLINT_REPORTER:-xcode}"
root="file://$(pwd)/"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

count() {
  jq 'length' "$1"
}

rule_ids() {
  awk '/^custom_rules:/ { inside = 1; next } inside && /^  [a-z_]+:$/ { sub(/:$/, ""); print $1 }' "$1"
}

write_current() {
  swiftlint lint --quiet --write-baseline "$1" >/dev/null 2>&1 || true
}

to_absolute() {
  jq --arg root "$root" 'map(.violation.location.file |= $root + .)' "$1" > "$2"
}

to_relative() {
  {
    echo '['
    jq -c --arg root "$root" \
      'map(.violation.location.file |= ltrimstr($root))
       | sort_by(.violation.location.file, .violation.ruleIdentifier, .text)
       | .[]' "$1" | sed '$!s/$/,/'
    echo ']'
  } > "$2"
}

update() {
  write_current "$tmp/current.json"
  to_relative "$tmp/current.json" "$baseline"
  echo "기준 파일: $(count "$baseline")건"
}

check() {
  to_absolute "$baseline" "$tmp/baseline.json"
  if ! swiftlint lint --quiet --reporter "$reporter" --baseline "$tmp/baseline.json"; then
    echo "새 SwiftLint 위반이 있다. 고치거나, 규칙이 틀렸으면 규칙을 고친다(기준 파일에 더하지 않는다)."
    exit 1
  fi

  committed=$(count "$baseline")
  write_current "$tmp/current.json"
  current=$(count "$tmp/current.json")
  if [ "$current" -lt "$committed" ]; then
    echo "고친 위반 $((committed - current))건이 기준 파일에 남아 있다. $0 update 로 기준 파일을 줄인다."
    exit 1
  fi

  if [ -n "${BASE_REF:-}" ] && git cat-file -e "origin/$BASE_REF:$baseline" 2>/dev/null; then
    git show "origin/$BASE_REF:$baseline" > "$tmp/base.json"
    git show "origin/$BASE_REF:.swiftlint.yml" > "$tmp/base.yml"
    grown=$(jq -r --slurpfile base "$tmp/base.json" --argjson known "$(rule_ids "$tmp/base.yml" | jq -R . | jq -s .)" '
      (group_by(.violation.ruleIdentifier) | map({key: .[0].violation.ruleIdentifier, value: length}) | from_entries) as $now
      | ($base[0] | group_by(.violation.ruleIdentifier) | map({key: .[0].violation.ruleIdentifier, value: length}) | from_entries) as $was
      | $now | to_entries[] | . as $e
      | select(($known | index($e.key)) != null and $e.value > ($was[$e.key] // 0))
      | "\($e.key) \($was[$e.key] // 0)건 → \($e.value)건"' "$baseline")
    if [ -n "$grown" ]; then
      echo "기준 파일이 늘었다(규칙별, base 에 있던 규칙만 센다). 기준 파일은 줄기만 한다:"
      echo "$grown"
      exit 1
    fi
  fi

  echo "SwiftLint 래칫 통과: 기준 ${committed}건"
}

selftest() {
  swiftlint lint --quiet --reporter json "$fixtures/Violations.swift" > "$tmp/violations.json" 2>"$tmp/stderr.txt" || true
  swiftlint lint --quiet --reporter json "$fixtures/Clean.swift" > "$tmp/clean.json" 2>/dev/null || true
  failed=0
  for rule in $(rule_ids .swiftlint.yml); do
    hits=$(jq --arg rule "$rule" '[.[] | select(.rule_id == $rule)] | length' "$tmp/violations.json")
    if [ "$hits" -eq 0 ]; then
      echo "$rule: Violations.swift 에서 잡히지 않는다"
      failed=1
    fi
  done
  clean=$(count "$tmp/clean.json")
  if [ "$clean" -ne 0 ]; then
    echo "Clean.swift 에서 ${clean}건이 잡혔다(오탐):"
    jq -r '.[] | "  \(.rule_id) \(.line)"' "$tmp/clean.json"
    failed=1
  fi
  if [ "$failed" -ne 0 ]; then
    cat "$tmp/stderr.txt"
  else
    echo "SwiftLint 픽스처 통과"
  fi
  return "$failed"
}

case "${1:-check}" in
  check) check ;;
  update) update ;;
  selftest) selftest ;;
  *) echo "usage: $0 [check|update|selftest]" >&2; exit 2 ;;
esac
