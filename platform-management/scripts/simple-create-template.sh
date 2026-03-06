#!/usr/bin/env bash
set -euo pipefail

IMAGE_URL="${IMAGE_URL:-https://csimages.hybrid.kmd.dk/windows-2022-eval.qcow2}"
VHDX_SOURCE_URL="${VHDX_SOURCE_URL:-https://software-download.microsoft.com/download/pr/20348.169.amd64fre.fe_release_svc_refresh.210806-2348_server_serverdatacentereval_en-us.vhdx}"
WORKDIR="${WORKDIR:-/tmp/windows2022-template}"
PUBLISH_DIR="${PUBLISH_DIR:-/home/www/csimages}"
VHDX_BASENAME="$(basename "${VHDX_SOURCE_URL}")"
QCOW2_BASENAME="${QCOW2_BASENAME:-windows-2022-eval.qcow2}"
DOWNLOAD_PATH="${WORKDIR}/${VHDX_BASENAME}"
QCOW2_LOCAL_PATH="${WORKDIR}/${QCOW2_BASENAME}"
PUBLISH_PATH="${PUBLISH_DIR}/${QCOW2_BASENAME}"
TEMPLATE_NAME="${TEMPLATE_NAME:-windows-2022-eval}"
DISPLAY_TEXT="${DISPLAY_TEXT:-Windows Server 2022 Eval}"
HYPERVISOR="${HYPERVISOR:-KVM}"
FORMAT="${FORMAT:-QCOW2}"
OSTYPE_PATTERN="${OSTYPE_PATTERN:-Windows.*2022}"

usage() {
  echo "Usage: $0 <zone-id>" >&2
  exit 1
}

for cmd in cmk jq curl qemu-img; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "$cmd not in PATH" >&2; exit 1; }
done

[[ $# -eq 1 ]] || usage
ZONE_ID="$1"

mkdir -p "${WORKDIR}"
mkdir -p "${PUBLISH_DIR}"

if [[ ! -f "${DOWNLOAD_PATH}" ]]; then
  echo "Downloading VHDX..."
  curl -L --fail -o "${DOWNLOAD_PATH}.tmp" "${VHDX_SOURCE_URL}"
  mv "${DOWNLOAD_PATH}.tmp" "${DOWNLOAD_PATH}"
fi

echo "Converting VHDX to QCOW2..."
qemu-img convert -p -O qcow2 "${DOWNLOAD_PATH}" "${QCOW2_LOCAL_PATH}"

echo "Publishing QCOW2 to ${PUBLISH_PATH}..."
cp -f "${QCOW2_LOCAL_PATH}" "${PUBLISH_PATH}"

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