#!/usr/bin/env bash
set -euo pipefail
test "$GITHUB_REPOSITORY" = chinghoi/immich
repo=$GITHUB_REPOSITORY
branch="ops/tailnet-permission-check-$GITHUB_RUN_ID"
gh api --method POST "repos/$repo/git/refs" -f ref="refs/heads/$branch" -f sha="$GITHUB_SHA" >/dev/null
# A dispatch-only workflow on a disposable branch verifies the actual workflow
# write scope; it never runs during this check and is never merged into main.
content=$(printf 'name: Tailnet permission probe\non: workflow_dispatch\njobs:\n  probe:\n    runs-on: ubuntu-24.04\n    steps:\n      - run: echo permission-scope-probe\n' | base64 -w0)
gh api --method PUT "repos/$repo/contents/.github/workflows/tailnet-permission-probe.yml" \
  -f branch="$branch" -f message='ci: verify workflow write permission on isolated probe branch' -f content="$content" >/dev/null
cat > /tmp/tailnet-permission-check.md <<EOF
Disposable automation permission check in the user's fork only.
This PR is automatically closed without merging. It verifies workflow writes
and the repository's permission for GitHub Actions to create pull requests.
No App source, stable branch, upstream repository, or credentials are changed.
EOF
url=$(gh pr create --repo "$repo" --base main --head "$branch" --draft \
  --title 'ci: verify fork automation permissions (temporary)' --body-file /tmp/tailnet-permission-check.md)
gh pr close "$url" --repo "$repo"
printf 'Workflow-write and PR-create permission check passed: %s (closed, not merged).\n' "$url" >> "$GITHUB_STEP_SUMMARY"
