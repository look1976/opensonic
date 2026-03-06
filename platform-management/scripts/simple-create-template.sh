#!/usr/bin/env bash
set -euo pipefail

IMAGE_URL="https://software-static.download.prss.microsoft.com/sg/download/888969d5-f34g-4e03-ac9d-1f9786c66749/SERVER_EVAL_x64FRE_en-us.iso"
TEMPLATE_NAME="${TEMPLATE_NAME:-windows-2022-eval}"
DISPLAY_TEXT="${DISPLAY_TEXT:-Windows Server 2022 Eval}"
HYPERVISOR="${HYPERVISOR:-KVM}"
FORMAT="${FORMAT:-QCOW2}"
OSTYPE_PATTERN="${OSTYPE_PATTERN:-Windows.*2022}"

usage() {
  echo "Usage: $0 <zone-id>" >&2
  exit 1
}

command -v cmk >/dev/null 2>&1 || { echo "cmk not in PATH" >&2; exit 1; }
command -v jq  >/dev/null 2>&1 || { echo "jq not in PATH" >&2; exit 1; }

[[ $# -eq 1 ]] || usage
ZONE_ID="$1"

OSTYPE_JSON="$(cmk listOsTypes 2>/dev/null)" || { echo "cmk listOsTypes failed" >&2; exit 1; }
OSTYPE_ID="$(echo "$OSTYPE_JSON" | jq -r --arg re "$OSTYPE_PATTERN" '[.ostype[] | select(.description|test($re;"i"))][0].id // empty')"

[[ -n "$OSTYPE_ID" ]] || { echo "No CloudStack OS type matching regex '$OSTYPE_PATTERN'" >&2; exit 1; }

echo "Using OS type ID: $OSTYPE_ID"
cmk registerTemplate \
  name="${TEMPLATE_NAME}" \
  displaytext="${DISPLAY_TEXT}" \
  url="${IMAGE_URL}" \
  zoneid="${ZONE_ID}" \
  hypervisor="${HYPERVISOR}" \
  format="${FORMAT}" \
  ostypeid="${OSTYPE_ID}" \
  ispublic=true \
  passwordenabled=true