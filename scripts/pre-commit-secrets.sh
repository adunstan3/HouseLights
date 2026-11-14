#!/bin/bash
# Blocks commits that add a Google-style API key or a Secrets.plist.
# The same file lives in each watch app's scripts/ folder; keep the copies identical.
# Install: ln -sf ../../scripts/pre-commit-secrets.sh .git/hooks/pre-commit
set -u
fail=0
if git diff --cached --name-only --diff-filter=ACMR | grep -qE '(^|/)Secrets\.plist$'; then
  echo "pre-commit: Secrets.plist is staged; it must never be committed." >&2
  fail=1
fi
if git diff --cached -U0 --diff-filter=ACMR | grep -E '^\+' | grep -vE '^\+\+\+' | grep -qE 'AIza[0-9A-Za-z_-]{35}'; then
  echo "pre-commit: a staged change adds what looks like a Google API key." >&2
  fail=1
fi
exit $fail
