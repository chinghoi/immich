#!/usr/bin/env bash
set -euo pipefail
test "$GITHUB_REPOSITORY" = chinghoi/immich
repo=$GITHUB_REPOSITORY
gh api "repos/$repo/actions/runs/$RUN_ID" > /tmp/tailnet-run.json
python3 - <<'PY'
import json,os,re
r=json.load(open('/tmp/tailnet-run.json'))
assert r['conclusion']=='success' and r['status']=='completed'
assert r['head_repository']['full_name']==os.environ['GITHUB_REPOSITORY']
assert r['path']=='.github/workflows/tailnet-ios.yml'
assert re.fullmatch(r'sync/tailnet-v\d+\.\d+\.\d+',r['head_branch'])
assert re.fullmatch(r'[0-9a-f]{40}',r['head_sha'])
PY
sha=$(jq -r .head_sha /tmp/tailnet-run.json)
branch=$(jq -r .head_branch /tmp/tailnet-run.json)
gh api "repos/$repo/actions/runs/$RUN_ID/jobs" > /tmp/tailnet-jobs.json
python3 - <<'PY'
import json
jobs=json.load(open('/tmp/tailnet-jobs.json'))['jobs']
j=next(j for j in jobs if j['name']=='ios'); assert j['conclusion']=='success'
required={'Analyze transport and run regression tests','Protocol integration on iOS simulator (disposable tailnet)',
 'Build simulator app (no signing)','Build device app (unsigned, cannot install directly)'}
passed={s['name'] for s in j['steps'] if s['conclusion']=='success'}
assert required<=passed
PY
number=$(gh api "repos/$repo/pulls?state=open&head=${repo%/*}:$branch" --jq '.[0].number // empty')
[[ -n $number ]] || exit 0
gh api "repos/$repo/pulls/$number" > /tmp/tailnet-pr.json
base=$(jq -r .base.ref /tmp/tailnet-pr.json)
[[ $base == ios/stable || $base == ios/tailscale ]]
test "$(jq -r .head.sha /tmp/tailnet-pr.json)" = "$sha"
test "$(jq -r .head.repo.full_name /tmp/tailnet-pr.json)" = "$repo"
test "$(jq -r .draft /tmp/tailnet-pr.json)" = false
# Fast-forward ONLY to the exact tested commit. If the base has advanced with
# other work, GitHub rejects the non-fast-forward update. Never merge an untested
# combination, never force over local patches, never run candidate code here.
gh api --method PATCH "repos/$repo/git/refs/heads/$base" -f sha="$sha" -F force=false >/dev/null
printf 'Promoted exact tested commit `%s` to `%s` via PR #%s.\n' "$sha" "$base" "$number" >> "$GITHUB_STEP_SUMMARY"
[[ $base == ios/stable ]] || exit 0
directory=$(mktemp -d)
gh run download "$RUN_ID" --repo "$repo" --name "tailnet-ios-unsigned-$sha" --dir "$directory"
tag="tailnet-${branch#sync/tailnet-}-${sha:0:8}"
cat > /tmp/tailnet-release.md <<EOF
Cloud-validated Immich iOS userspace Tailscale build from $sha.
CI: https://github.com/$repo/actions/runs/$RUN_ID

UNSIGNED: the IPA requires re-signing with your own Apple Account before installation.
It cannot be installed directly. No TestFlight or public App Store upload was made.
Read custom/ios-tailnet/README.md for 7-day free-account limits and compatible server versions.
Real-device behavior and the user's home tailnet require separate acceptance.
EOF
gh release create "$tag" "$directory"/* --repo "$repo" --target "$sha" \
  --title "Immich ${branch#sync/tailnet-} Tailscale (unsigned)" --notes-file /tmp/tailnet-release.md
# Releases are durable recovery points. Actions logs expire after 7 days and
# transient app artifacts after 14; failed updates never delete a good release.
