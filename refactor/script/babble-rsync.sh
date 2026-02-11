# Usage: `. ./refactor/script/babble-rsync.sh`
typeset -a RSYNC_OPTIONS=("$@")
rsync \
  "${RSYNC_OPTIONS[@]}" \
  --delete --delete-excluded \
  --archive \
  --checksum \
  --whole-file \
  --human-readable --human-readable \
  --partial \
  --progress \
  --exclude '.Trashes' \
  --exclude '.Spotlight-V100' \
  --exclude '.fseventsd' \
  --exclude '.TemporaryItems' \
  --exclude '.DS_Store' \
  -- \
  ~/devel/github/babble/refactor/ \
  ~/icloud/Computing/babble/ruby/refactor

# Unused options:
#  --verbose --verbose \
#  --stats \
