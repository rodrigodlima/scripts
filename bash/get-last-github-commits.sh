SINCE=$(date -u -v-7d +%Y-%m-%d)        # macOS
# Linux/Actions: SINCE=$(date -u -d '7 days ago' +%Y-%m-%d)

gh search commits --author-email=rodrigodlima@gmail.com \
  --author-date=">=$SINCE" \
  --json repository \
  --jq '[.[] | .repository.fullName] | unique | .[]'
