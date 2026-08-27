#!/bin/zsh
set -euo pipefail

COUNT="${1:-4}"
TOAST="$HOME/Applications/NameDrop.app/Contents/Resources/bin/namedrop-toast"
ICON="$HOME/Applications/NameDrop.app/Contents/Resources/NameDrop.icns"

if [[ ! "$COUNT" =~ '^[1-4]$' ]]; then
  echo "Usage: ./test-notifications.sh [1-4]" >&2
  exit 1
fi
if [[ ! -x "$TOAST" || ! -f "$ICON" ]]; then
  echo "Install NameDrop first with ./install-macos.sh" >&2
  exit 1
fi

originals=(
  "download-847291.pdf"
  "document (12).docx"
  "attachment-003.csv"
  "scan_9284.pdf"
)
renamed=(
  "Acme Insurance Proposal.pdf"
  "Q3 Product Planning Notes.docx"
  "August Expense Report.csv"
  "Signed Vendor Agreement.pdf"
)

echo "Showing $COUNT compact notification(s). They fade automatically."
for (( index = 1; index <= COUNT; index++ )); do
  NAMEDROP_ICON="$ICON" "$TOAST" "${originals[$index]}" "${renamed[$index]}" "$((index - 1))" &
  sleep 0.12
done
wait
