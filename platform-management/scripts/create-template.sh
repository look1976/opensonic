#!/usr/bin/env bash
# Build Rocky Linux 9 template qcow2 via remote libvirt (qemu+ssh) + Kickstart,
# then publish the image to Deployer host (cloudstack-images/) via SSH.
#
# Output artifact name follows VMNAME (e.g. VMNAME=rocky9-build => rocky9-build.qcow2)

set -euo pipefail

# -------------------------
# CONFIG
# -------------------------
export DEPLOYER="${DEPLOYER:-deployer}"     # deployer host (serves HTTP repo + will serve qcow2)
export KVM_HOST="${KVM_HOST:-mother.home.lab}"    # KVM host
export KVM_USER="${KVM_USER:-look}"
export LIBVIRT_DEFAULT_URI="${LIBVIRT_DEFAULT_URI:-qemu+ssh://${KVM_USER}@${KVM_HOST}/system}"
export VMNAME="${VMNAME:-rocky9-build}"

#: "${CLOUDSTACK_ZONEID:?Set CLOUDSTACK_ZONEID}"
#: "${CLOUDSTACK_OSTYPEID:?Set CLOUDSTACK_OSTYPEID}"
CLOUDSTACK_OSTYPEID="${CLOUDSTACK_OSTYPEID:-"Rocky Linux 9"}"

command -v cmk >/dev/null 2>&1 || { log "ERROR: cmk (Cloudmonkey binary) not found"; exit 1; }

# --- NEW: build timestamp for versioned artifacts ---
# Format: YYYYMMDD-HHMMSS (safe for filenames + URLs)
BUILD_TS="${BUILD_TS:-$(date +%Y%m%d-%H%M%S)}"

# Remote paths (on KVM host)
DISK_DIR="${DISK_DIR:-/var/lib/libvirt/images}"
DISK_PATH="${DISK_DIR}/${VMNAME}.qcow2"

OUT_DIR="${OUT_DIR:-${DISK_DIR}/golden}"
# --- CHANGED: versioned output image name ---
OUT_IMG="${OUT_IMG:-${OUT_DIR}/${VMNAME}-${BUILD_TS}.qcow2}"

# Publish target (on DEPLOYER host)
DEPLOYER_USER="${DEPLOYER_USER:-${KVM_USER}}"
DEPLOYER_IMG_DIR="${DEPLOYER_IMG_DIR:-/home/www/cloudstack-images}"   # change if your nginx root differs
# --- CHANGED: versioned publish name ---
PUBLISH_NAME="${PUBLISH_NAME:-${VMNAME}-${BUILD_TS}.qcow2}"
PUBLISH_PATH="${DEPLOYER_IMG_DIR}/${PUBLISH_NAME}"

# VM sizing
VM_RAM_MB="${VM_RAM_MB:-4096}"
VM_VCPUS="${VM_VCPUS:-4}"
DISK_SIZE_GB="${DISK_SIZE_GB:-20}"

# Install
REPO_URL="${REPO_URL:-http://${DEPLOYER}/rocky9}"
KS_URL="${KS_URL:-http://${DEPLOYER}/kickstarts/${VMNAME}.cfg}"  # adjust if your ks name differs
# If your KS file name is fixed, override: KS_URL=http://.../kickstarts/rocky9-build.cfg

# Behaviour toggles
DO_SPARSIFY="${DO_SPARSIFY:-yes}"     # yes/no
UNDEFINE_VM="${UNDEFINE_VM:-yes}"     # yes/no

# Timeouts
WAIT_INSTALL_SECONDS="${WAIT_INSTALL_SECONDS:-1800}"  # 30 min
WAIT_SHUTDOWN_SECONDS="${WAIT_SHUTDOWN_SECONDS:-120}" # 2 min

TEMPLATE_NAME="${VMNAME}-${BUILD_TS}"

# -------------------------
# helpers
# -------------------------
log(){ echo "[$(date -Is)] $*"; }

remote_kvm() {
  ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
    "${KVM_USER}@${KVM_HOST}" "$@"
}

remote_deployer() {
  ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
    "${DEPLOYER_USER}@${DEPLOYER}" "$@"
}

dom_exists() { virsh dominfo "${VMNAME}" >/dev/null 2>&1; }
dom_state() { virsh domstate "${VMNAME}" 2>/dev/null | tr -d '\r' || true; }

is_running_state() {
  local s="${1,,}"
  [[ "$s" =~ running|paused|pmsuspended|idle|in\ shutdown ]]
}

is_off_state() {
  local s="${1,,}"
  [[ "$s" =~ shut\ off|shutoff|off|crashed|pmsuspended ]]
}

wait_until_off() {
  local deadline=$(( $(date +%s) + WAIT_INSTALL_SECONDS ))
  while true; do
    local s
    s="$(dom_state)"
    if is_off_state "$s"; then
      log "VM state is OFF (state='$s')."
      return 0
    fi
    if (( $(date +%s) > deadline )); then
      log "Timeout waiting for install completion (last state='$s')."
      return 1
    fi
    sleep 5
  done
}

select_cloudstack_zone() {

  # if set don't ask and just use it
  if [[ -n "${CLOUDSTACK_ZONEID:-}" ]]; then
    log "CloudStack: using CLOUDSTACK_ZONEID=${CLOUDSTACK_ZONEID}"
    return 0
  fi

  command -v cmk >/dev/null 2>&1 || { log "ERROR: cmk not found"; exit 1; }
  command -v jq  >/dev/null 2>&1 || { log "ERROR: jq not found (dnf install jq)"; exit 1; }

  log "CloudStack: fetching available zones..."

  ZONES_JSON="$(cmk listZones 2>/dev/null)" || {
    log "ERROR: cannot list zones"
    exit 1
  }

  mapfile -t ZONE_IDS   < <(echo "$ZONES_JSON" | jq -r '.zone[]?.id')
  mapfile -t ZONE_NAMES < <(echo "$ZONES_JSON" | jq -r '.zone[]?.name')

  if [[ "${#ZONE_IDS[@]}" -eq 0 ]]; then
    log "ERROR: no zones returned by CloudStack"
    exit 1
  fi

  echo
  echo "Available CloudStack Zones:"
  for i in "${!ZONE_IDS[@]}"; do
    printf "  [%d] %s (id=%s)\n" "$((i+1))" "${ZONE_NAMES[$i]}" "${ZONE_IDS[$i]}"
  done
  echo

  while true; do
    read -rp "Select zone number: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#ZONE_IDS[@]} )); then
      CLOUDSTACK_ZONEID="${ZONE_IDS[$((choice-1))]}"
      export CLOUDSTACK_ZONEID
      log "CloudStack: selected zone ${ZONE_NAMES[$((choice-1))]} (id=${CLOUDSTACK_ZONEID})"
      break
    else
      echo "Invalid selection."
    fi
  done
}

# -------------------------
# sanity checks
# -------------------------
log "LIBVIRT_DEFAULT_URI=${LIBVIRT_DEFAULT_URI}"
log "DEPLOYER=${DEPLOYER}  REPO_URL=${REPO_URL}"
log "KS_URL=${KS_URL}"
log "Remote build disk: ${KVM_HOST}:${DISK_PATH}"
log "Remote output img: ${KVM_HOST}:${OUT_IMG}"
log "Publish target:    ${DEPLOYER}:${PUBLISH_PATH}"

select_cloudstack_zone

virsh list --all >/dev/null
remote_kvm "sudo mkdir -p '${OUT_DIR}'"

# -------------------------
# cleanup old VM/disk on KVM
# -------------------------
if dom_exists; then
  log "Found existing VM '${VMNAME}' — removing..."
  s="$(dom_state)"
  if is_running_state "$s"; then
    log "Destroying running VM (state='$s')..."
    virsh destroy "${VMNAME}" || true
  fi
  log "Undefining VM..."
  virsh undefine "${VMNAME}" --nvram 2>/dev/null || virsh undefine "${VMNAME}" || true
fi

log "Removing existing remote disk (if any): ${DISK_PATH}"
remote_kvm "sudo rm -f '${DISK_PATH}'"

# -------------------------
# create VM and start install
# -------------------------
log "Creating VM and starting installation..."
virt-install \
  --name "${VMNAME}" \
  --memory "${VM_RAM_MB}" \
  --vcpus "${VM_VCPUS}" \
  --cpu host-passthrough \
  --disk "path=${DISK_PATH},size=${DISK_SIZE_GB},format=qcow2,bus=virtio" \
  --os-variant rocky9 \
  --network bridge=cloudbr0,model=virtio \
  --location "${REPO_URL}" \
  --graphics none \
  --console pty,target_type=serial \
  --noautoconsole \
  --extra-args "inst.ks=${KS_URL} inst.text ip=dhcp console=ttyS0"

log "VM started. Watch: virsh console ${VMNAME}  (exit: Ctrl+])"

# -------------------------
# wait for installation to finish
# -------------------------
log "Waiting up to ${WAIT_INSTALL_SECONDS}s for installation to finish (VM powers off)..."
if ! wait_until_off; then
  s="$(dom_state)"
  if is_running_state "$s"; then
    log "Trying graceful shutdown..."
    virsh shutdown "${VMNAME}" || true

    deadline=$(( $(date +%s) + WAIT_SHUTDOWN_SECONDS ))
    while true; do
      s="$(dom_state)"
      if is_off_state "$s"; then
        log "VM is OFF after shutdown (state='$s')."
        break
      fi
      if (( $(date +%s) > deadline )); then
        log "Shutdown timeout; forcing power off..."
        virsh destroy "${VMNAME}" || true
        break
      fi
      sleep 5
    done
  fi
fi

s="$(dom_state)"
if ! is_off_state "$s"; then
  log "VM still not OFF (state='$s') — forcing destroy..."
  virsh destroy "${VMNAME}" || true
fi

# -------------------------
# sysprep + optional sparsify on KVM disk
# -------------------------
log "virt-sysprep on remote disk..."
remote_kvm "sudo virt-sysprep -a '${DISK_PATH}'"

if [[ "${DO_SPARSIFY}" == "yes" ]]; then
  log "virt-sparsify --in-place (optional)..."
  remote_kvm "sudo virt-sparsify --in-place '${DISK_PATH}'"
fi

# -------------------------
# convert to output + checksum on KVM
# -------------------------
log "Converting to output image on KVM: ${OUT_IMG}"
remote_kvm "sudo qemu-img convert -O qcow2 '${DISK_PATH}' '${OUT_IMG}'"
remote_kvm "sudo qemu-img info '${OUT_IMG}'"

log "Computing SHA256..."
remote_kvm "sudo sha256sum '${OUT_IMG}' | sudo tee '${OUT_IMG}.sha256' >/dev/null"

# -------------------------
# publish to deployer (cloudstack-images/)
# -------------------------
# -------------------------
# publish to deployer (cloudstack-images/)
# -------------------------
log "Ensuring target directory exists on deployer: ${DEPLOYER_IMG_DIR}"
remote_deployer "sudo mkdir -p '${DEPLOYER_IMG_DIR}'"

log "Publishing qcow2 + sha256 to deployer via rsync (KVM -> local tmp -> deployer)..."
TMPDIR="$(mktemp -d)"
cleanup(){ rm -rf "${TMPDIR}"; }
trap cleanup EXIT

# 1. Pull from KVM to local tmp
rsync -avP -e "ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new" \
  "${KVM_USER}@${KVM_HOST}:${OUT_IMG}" \
  "${TMPDIR}/"

rsync -avP -e "ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new" \
  "${KVM_USER}@${KVM_HOST}:${OUT_IMG}.sha256" \
  "${TMPDIR}/"

# 2. Push to deployer user home (no sudo needed)
DEPLOYER_TMP_DIR="/home/${DEPLOYER_USER}/.upload-tmp-${BUILD_TS}"
remote_deployer "mkdir -p '${DEPLOYER_TMP_DIR}'"

rsync -avP -e "ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new" \
  "${TMPDIR}/$(basename "${OUT_IMG}")" \
  "${DEPLOYER_USER}@${DEPLOYER}:${DEPLOYER_TMP_DIR}/"

rsync -avP -e "ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new" \
  "${TMPDIR}/$(basename "${OUT_IMG}").sha256" \
  "${DEPLOYER_USER}@${DEPLOYER}:${DEPLOYER_TMP_DIR}/"

# 3. Move into nginx directory using sudo on deployer
remote_deployer "
  sudo mv '${DEPLOYER_TMP_DIR}/$(basename "${OUT_IMG}")' '${PUBLISH_PATH}' &&
  sudo mv '${DEPLOYER_TMP_DIR}/$(basename "${OUT_IMG}").sha256' '${PUBLISH_PATH}.sha256' &&
  sudo chmod 0644 '${PUBLISH_PATH}' '${PUBLISH_PATH}.sha256' &&
  sudo rm -rf '${DEPLOYER_TMP_DIR}'
"

remote_deployer "command -v restorecon >/dev/null 2>&1 && sudo restorecon -RF '${DEPLOYER_IMG_DIR}' || true"
# -------------------------
# cleanup VM definition
# -------------------------
if [[ "${UNDEFINE_VM}" == "yes" ]]; then
  log "Undefining build VM '${VMNAME}' (definition only)..."
  virsh undefine "${VMNAME}" --nvram 2>/dev/null || virsh undefine "${VMNAME}" || true
fi

log "DONE."
log "Published on deployer:"
log "  ${PUBLISH_PATH}"
log "  ${PUBLISH_PATH}.sha256"
log "CloudStack URL:"
log "  http://${DEPLOYER}/cloudstack-images/${PUBLISH_NAME}"


cmk register template \
  name="${TEMPLATE_NAME}" \
  displaytext="Rocky 9 build ${BUILD_TS}" \
  url="http://${DEPLOYER}/cloudstack-images/${PUBLISH_NAME}" \
  hypervisor=KVM \
  format=QCOW2 \
  ostypeid="${CLOUDSTACK_OSTYPEID}" \
  zoneid="${CLOUDSTACK_ZONEID}" \
  ispublic=true \
  isfeatured=true \
  passwordenabled=false
