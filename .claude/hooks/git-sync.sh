#!/bin/sh
# Keeps this clone in step with GitHub, since Neil and Nic both push to main.
#   git-sync.sh start  - session start: pull, and tell Claude what came in
#   git-sync.sh push   - before a `git push`: pull first so the push isn't rejected
# Never leaves a half-finished rebase behind: on a conflict it aborts, changes
# nothing, and says so (and in push mode blocks the push so Claude resolves it).
mode="${1:-start}"
# Push mode runs before every Bash command; only act when it actually pushes,
# including chained commands like `cd x && git add -A && git push`.
if [ "$mode" = push ]; then cat | grep -q 'git push' || exit 0; fi
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
branch=$(git symbolic-ref --short -q HEAD) || exit 0          # detached HEAD: leave it alone
git rev-parse -q --verify '@{u}' >/dev/null 2>&1 || exit 0   # branch not on GitHub yet
[ -d "$(git rev-parse --git-dir)/rebase-merge" ] && exit 0   # someone is mid-rebase already

json() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' '; }

if ! git fetch -q 2>/dev/null; then
  [ "$mode" = start ] && echo "Couldn't reach GitHub to check for new commits (offline?). Run git pull before pushing."
  exit 0
fi
behind=$(git rev-list --count 'HEAD..@{u}')
[ "$behind" = 0 ] && exit 0
incoming=$(git log --format='%an: %s' 'HEAD..@{u}' | head -5 | paste -sd ';' -)

if git rebase -q --autostash '@{u}' >/dev/null 2>&1; then
  msg="Pulled $behind new commit(s) on $branch from GitHub ($incoming)."
  if [ "$mode" = start ]; then
    printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s Re-read any file you had in mind before editing it."}}\n' "$(json "$msg")" "$(json "$msg")"
  else
    printf '{"systemMessage":"%s"}\n' "$(json "$msg Then pushed.")"
  fi
  exit 0
fi

git rebase --abort >/dev/null 2>&1
msg="GitHub has $behind new commit(s) on $branch ($incoming) that conflict with local changes. Nothing was changed."
if [ "$mode" = push ]; then
  echo "$msg Push blocked: run git pull --rebase, resolve the conflict keeping both people's work, test, then push." >&2
  exit 2
fi
printf '{"systemMessage":"%s","hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s Resolve with git pull --rebase before editing, keeping both people'"'"'s work."}}\n' "$(json "$msg")" "$(json "$msg")"
exit 0
