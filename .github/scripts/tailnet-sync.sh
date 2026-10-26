#!/usr/bin/env bash
set -euo pipefail
test "$GITHUB_REPOSITORY" = chinghoi/immich
repo=$GITHUB_REPOSITORY
git config user.name 'github-actions[bot]'
git config user.email '41898282+github-actions[bot]@users.noreply.github.com'
git remote add upstream https://github.com/immich-app/immich.git
git fetch upstream main --tags
# The mirror is discovery only. Never force through an upstream history rewrite.
git push origin refs/remotes/upstream/main:refs/heads/upstream/main
base=ios/stable
if ! git show "origin/$base:custom/ios-tailnet/dependencies.json" > /tmp/tailnet-baseline.json 2>/dev/null; then
  base=ios/tailscale
  git show "origin/$base:custom/ios-tailnet/dependencies.json" > /tmp/tailnet-baseline.json
  echo 'Initial implementation is still under review; checking the development baseline.' >> "$GITHUB_STEP_SUMMARY"
fi
current=$(python3 -c 'import json;print(json.load(open("/tmp/tailnet-baseline.json"))["immichTag"])')
tag=$(gh api repos/immich-app/immich/releases/latest --jq '.tag_name')
[[ $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]
printf 'Stable baseline: `%s`. Latest upstream stable: `%s`.\n' "$current" "$tag" >> "$GITHUB_STEP_SUMMARY"
[[ $tag != "$current" ]] || exit 0
branch="sync/tailnet-$tag"
if git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
  echo "Existing candidate $branch left intact; resolve or rerun its PR. No forced overwrite." >> "$GITHUB_STEP_SUMMARY"
  exit 0
fi
git switch --create "$branch" "origin/$base"
blocked=false
if ! git merge --no-edit "$tag"; then
  git diff --name-only --diff-filter=U > /tmp/tailnet-conflicts.txt
  git merge --abort
  blocked=true
  python3 - "$tag" <<'PY'
import json,pathlib,sys
p=pathlib.Path('custom/ios-tailnet/update-blocked.json')
p.write_text(json.dumps({'target':sys.argv[1],'reason':'merge conflict',
  'paths':pathlib.Path('/tmp/tailnet-conflicts.txt').read_text().splitlines()},indent=2)+'\n')
PY
else
  upstream_sha=$(git rev-parse "$tag^{commit}")
  python3 - "$tag" "$upstream_sha" <<'PY'
import json,pathlib,sys
p=pathlib.Path('custom/ios-tailnet/dependencies.json'); data=json.loads(p.read_text())
data.update(immichTag=sys.argv[1],immichCommit=sys.argv[2]);p.write_text(json.dumps(data,indent=2)+'\n')
PY
fi
git add custom/ios-tailnet
git commit -m "chore(ios): track upstream $tag" || true
git push origin "$branch"
cat > /tmp/tailnet-update-body.md <<EOF
Update the iOS custom branch from upstream stable $current to $tag.

All existing Tailscale patches are retained by a normal merge; no force push is used.
The server is never upgraded by this workflow. Before installing this app, check the
matching Immich server version and upstream release notes.

Cloud validation must pass analysis, Dart regression tests, a disposable-tailnet iOS
simulator integration suite, simulator build and unsigned device build. A failure
leaves this PR open and preserves the previous stable branch and release assets.

Conflict recovery: custom/ios-tailnet/README.md. Conflict: $blocked.
EOF
if [[ $blocked == true ]]; then
  gh pr create --repo "$repo" --base "$base" --head "$branch" --draft \
    --title "[blocked] chore(ios): upstream $tag conflicts" --body-file /tmp/tailnet-update-body.md
  echo 'Merge conflict: draft PR created; update paused.' >> "$GITHUB_STEP_SUMMARY"
  exit 0
fi
gh pr create --repo "$repo" --base "$base" --head "$branch" \
  --title "chore(ios): merge upstream stable $tag" --body-file /tmp/tailnet-update-body.md
# GITHUB_TOKEN pushes/PRs do not recursively trigger builds. Explicit dispatch is required.
gh workflow run tailnet-ios.yml --repo "$repo" --ref "$branch"
echo "Validation dispatched for $branch; promotion waits for successful CI." >> "$GITHUB_STEP_SUMMARY"
