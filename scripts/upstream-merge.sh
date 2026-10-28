#!/usr/bin/env bash
# Merges upstream into the current branch with both sides formatted alike.
#
#   scripts/upstream-merge.sh [upstream/main]
#
# This fork formats its Swift with swift-format (.swift-format: tabs, 100 columns); upstream
# uses four spaces. A plain merge conflicts wherever upstream touched code near anything
# reformatted, even when nothing really clashes. So the merge base and the upstream tip are
# formatted the same way first, in throwaway worktrees, and the three-way merge runs on
# those: only real changes are compared, and upstream's code arrives in the fork's style.
# The merge is recorded against the real upstream commit, so the next run starts from it.
#
# A clean merge is committed. Otherwise the conflicts are left in the working tree as usual:
# resolve them, then `git commit`.
set -euo pipefail

up="${1:-upstream/main}"
root="$(git rev-parse --show-toplevel)"
cd "$root"

if [ -n "$(git status --porcelain)" ]; then
  echo "✗ Commit or stash your changes first." >&2
  exit 1
fi
git fetch upstream
if git merge-base --is-ancestor "$up" HEAD; then
  echo "Already up to date with $up."
  exit 0
fi

upstream="$(git rev-parse "$up^{commit}")"
base="$(git merge-base HEAD "$upstream")"
swift_format="$(xcrun --find swift-format)"
config="$root/.swift-format"
tmp="$(mktemp -d)"
cleanup() {
  for w in "$tmp/base" "$tmp/upstream"; do
    [ -d "$w" ] && git worktree remove --force "$w"
  done
  rm -rf "$tmp"
}
trap cleanup EXIT

# A commit holding `rev` with its Swift formatted the fork's way; prints its hash.
formatted() {
  local rev="$1" dir="$2"
  git worktree add --quiet --detach "$dir" "$rev"
  (
    cd "$dir"
    find Sources -name '*.swift' -print0 \
      | xargs -0 "$swift_format" format --configuration "$config" --in-place
    git add -A
    git -c user.name=upstream-merge -c user.email=upstream-merge@localhost \
      commit --quiet --allow-empty -m "Formatted $rev"
    git rev-parse HEAD
  )
}

echo "Formatting the merge base ($(git rev-parse --short "$base")) and $up ($(git rev-parse --short "$upstream"))…"
fbase="$(formatted "$base" "$tmp/base")"
fup="$(formatted "$upstream" "$tmp/upstream")"

# Three-way merge into the index and working tree with the formatted base, then let
# git-merge-one-file merge each changed file, leaving conflict markers where it can't.
git read-tree -m -u "$fbase" HEAD "$fup"
git merge-index -o -q git-merge-one-file -a || true

git rev-parse "$upstream" > "$(git rev-parse --git-path MERGE_HEAD)"
printf "Merge %s (%s)\n" "$up" "$(git rev-parse --short "$upstream")" \
  > "$(git rev-parse --git-path MERGE_MSG)"

conflicts="$(git diff --name-only --diff-filter=U)"
if [ -z "$conflicts" ]; then
  git commit --quiet --no-edit
  echo "✓ Merged $up cleanly."
else
  echo "✗ Conflicts to resolve, then \`git commit\`:"
  echo "$conflicts" | sed 's/^/  /'
  exit 1
fi
