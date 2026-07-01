SINCE=$(date -u -v-7d +%Y-%m-%d)        # macOS
# Linux/Actions: SINCE=$(date -u -d '7 days ago' +%Y-%m-%d)

# 1) Find repo + sha for my recent commits
gh search commits --author-email=rodrigodlima@gmail.com \
  --author-date=">=$SINCE" \
  --json repository,sha \
  --jq '.[] | "\(.repository.fullName) \(.sha)"' |
while read -r REPO SHA; do
  # 2) For each commit, list changed files and keep the top-level folder
  gh api "repos/$REPO/commits/$SHA" \
    --jq '.files[].filename' 2>/dev/null |
  while read -r FILE; do
    # folder up to 2 levels deep; "(root)" if file at repo root
    DIR=$(dirname "$FILE")
    case "$DIR" in
      .)  echo "$REPO/(root)" ;;
      *)  echo "$REPO/$(echo "$DIR" | cut -d/ -f1-2)" ;;
    esac
  done
done | sort -u
