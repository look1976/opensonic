#!/usr/bin/env bash
# firstboot-kvm.sh
# Bootstrap for Rocky Linux 9 KVM node (run once via systemd runner).
# Safe-by-default: does NOT overwrite your network config unless you explicitly enable it.

set -euo pipefail

LOG_FILE="/var/log/firstboot-kvm.log"
WORKDIR="/var/lib/firstboot-kvm"
CONF_FILE="/etc/firstboot-kvm.conf"

mkdir -p "$WORKDIR"
touch "$LOG_FILE"
chmod 0600 "$LOG_FILE"

exec > >(tee -a "$LOG_FILE") 2>&1

ts() { date -Is; }
log() { echo "[$(ts)] $*"; }
die() { log "ERROR: $*"; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root."

log "=== firstboot-kvm starting on $(hostname -f 2>/dev/null || hostname) ==="

# ---- Defaults (override via /etc/firstboot-kvm.conf) ----
: "${DO_DNF_UPDATE:=0}"                 # 1 = dnf -y update (can take time)
: "${INSTALL_COCKPIT:=0}"               # 1 = install cockpit + cockpit-machines
: "${DISABLE_FIREWALLD:=0}"             # 1 = disable firewalld
: "${DISABLE_SELINUX:=0}"               # 1 = set SELinux to permissive now + disable on next reboot
: "${CONFIGURE_BRIDGE:=1}"              # 1 = attempt to create a bridge using NetworkManager
: "${BRIDGE_NAME:=cloudbr0}"            # bridge name if CONFIGURE_BRIDGE=1
: "${BRIDGE_SLAVE_IF:=}"                # e.g. eno1 (required if CONFIGURE_BRIDGE=1)
: "${BRIDGE_IP_METHOD:=auto}"           # auto|manual (manual requires BRIDGE_IP_CIDR + BRIDGE_GW)
: "${BRIDGE_IP_CIDR:=}"                 # e.g. 10.11.12.162/24
: "${BRIDGE_GW:=}"                      # e.g. 10.11.12.1
: "${NTP_ENABLE:=1}"                    # 1 = enable chrony
: "${TIMEZONE:=Europe/Warsaw}"          # set system timezone
: "${REBOOT_AFTER:=0}"                  # 1 = reboot at end (usually let orchestration decide)
: "${INSTALL_CLOUDSTACK_AGENT:=1}"	# 1 = install agent
: "${CLOUDSTACK_VERSION:=4.22}"
: "${DEPLOYER:=10.11.12.2}"          # IP or hostname of the deployer (used for fetching scripts, keys, repos)
: "${CLOUDSTACK_REPO_URL:=https://download.cloudstack.org/el/8/${CLOUDSTACK_VERSION}/}"
: "${CLOUDSTACK_USER:=cloudstack}"
: "${CLOUDSTACK_AUTH_KEYS_URL:=http://$DEPLOYER/kickstarts/authorized_keys}"

: "${INSTALL_FLUENTBIT:=1}"            # 1 = install Fluent Bit (OpenSearch output) using embedded config
: "${FLUENTBIT_OPENSEARCH_HOST:=mother}"
: "${FLUENTBIT_OPENSEARCH_PORT:=9200}"
: "${FLUENTBIT_LOGSTASH_PREFIX:=kvm-journal}"
: "${FLUENTBIT_ENV:=lab}"

if [[ -f "$CONF_FILE" ]]; then
  log "Loading config overrides from $CONF_FILE"
  # shellcheck disable=SC1090
  source "$CONF_FILE"
fi

log "Settings: DO_DNF_UPDATE=$DO_DNF_UPDATE INSTALL_COCKPIT=$INSTALL_COCKPIT DISABLE_FIREWALLD=$DISABLE_FIREWALLD DISABLE_SELINUX=$DISABLE_SELINUX CONFIGURE_BRIDGE=$CONFIGURE_BRIDGE"

# ---- Basic tooling ----
log "Ensuring base tools are present"
dnf -y install \
  curl wget jq \
  ca-certificates \
  chrony \
  policycoreutils-python-utils \
  >/dev/null

# ---- Timezone + time sync ----
if [[ -n "${TIMEZONE:-}" ]]; then
  log "Setting timezone to $TIMEZONE"
  timedatectl set-timezone "$TIMEZONE" || true
fi

if [[ "$NTP_ENABLE" == "1" ]]; then
  log "Enabling chronyd"
  systemctl enable --now chronyd || true
fi

# ---- Optional update ----
if [[ "$DO_DNF_UPDATE" == "1" ]]; then
  log "Running dnf update (this may take a while)"
  dnf -y update
fi

# ---- KVM / libvirt packages ----
log "Installing KVM/libvirt packages"
dnf -y install \
  qemu-kvm \
  libvirt \
  libvirt-client \
  virt-install \
  virt-top \
  NetworkManager \
  libguestfs-tools \
  >/dev/null

# ---- CloudStack KVM Agent ----

if [[ "$INSTALL_CLOUDSTACK_AGENT" == "1" ]]; then
  log "Configuring CloudStack repo: $CLOUDSTACK_REPO_URL"
  cat >/etc/yum.repos.d/cloudstack.repo <<EOF
[cloudstack]
name=Apache CloudStack
baseurl=${CLOUDSTACK_REPO_URL}
enabled=1
gpgcheck=0
EOF

  log "Installing cloudstack-agent"
  dnf -y install cloudstack-agent

  log "Enabling cloudstack-agent service"
  systemctl enable --now cloudstack-agent || true

  log "CloudStack agent status:"
  systemctl --no-pager -l status cloudstack-agent || true
fi

# ---- Configure cloudstack user ----

log "Configuring CloudStack SSH access for user '$CLOUDSTACK_USER'"

# 1) Create user if missing
if ! id "$CLOUDSTACK_USER" &>/dev/null; then
  useradd -m -s /bin/bash "$CLOUDSTACK_USER"
fi

# 2) Prepare .ssh
SSH_DIR="/home/$CLOUDSTACK_USER/.ssh"
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
chown "$CLOUDSTACK_USER:$CLOUDSTACK_USER" "$SSH_DIR"

# 3) Fetch authorized_keys from Management
curl -fsSL "$CLOUDSTACK_AUTH_KEYS_URL" -o "$SSH_DIR/authorized_keys"

chmod 600 "$SSH_DIR/authorized_keys"
chown "$CLOUDSTACK_USER:$CLOUDSTACK_USER" "$SSH_DIR/authorized_keys"

# 4) Allow cloudstack user to sudo without password (CloudStack expects this)
cat >/etc/sudoers.d/cloudstack <<EOF
cloudstack ALL=(ALL) NOPASSWD:ALL
EOF
chmod 440 /etc/sudoers.d/cloudstack

log "CloudStack SSH access configured successfully"


# ---- Fluent Bit (optional) ----
if [[ "$INSTALL_FLUENTBIT" == "1" ]]; then
  log "Installing and configuring Fluent Bit"

  # Install repo + package (based on fluent-bit-install.sh, without sudo)
  curl -fsSL https://packages.fluentbit.io/fluentbit.key | tee /etc/pki/rpm-gpg/fluentbit.key >/dev/null
  cat >/etc/yum.repos.d/fluent-bit.repo <<'EOF'
[fluent-bit]
name=Fluent Bit
baseurl = https://packages.fluentbit.io/rockylinux/$releasever/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/fluentbit.key
enabled=1
EOF

  dnf -y install fluent-bit

  mkdir -p /var/lib/fluent-bit
  chown -R fluent-bit:fluent-bit /var/lib/fluent-bit 2>/dev/null || true

  # Write config (based on fluent-bit-kvm.conf) with a few overridable knobs
  FB_HOSTNAME="$(hostname -f 2>/dev/null || hostname)"
  mkdir -p /etc/fluent-bit
  cat >/etc/fluent-bit/fluent-bit.conf <<EOF
[SERVICE]
    Flush        2
    Daemon       Off
    Log_Level    info

[INPUT]
    Name              systemd
    Tag               kvm.journal
    Read_From_Tail    true
    Strip_Underscores On
    Systemd_Filter    _SYSTEMD_UNIT=libvirtd.service
    Systemd_Filter    _SYSTEMD_UNIT=virtqemud.service
    Systemd_Filter    _SYSTEMD_UNIT=virtlogd.service
    Systemd_Filter    _TRANSPORT=kernel

[FILTER]
    Name    modify
    Match   kvm.journal
    Add     role kvm-host
    Add     env  ${FLUENTBIT_ENV}
    Add     host ${FB_HOSTNAME}
    Add     system kvm

[OUTPUT]
    Name                opensearch
    Match               kvm.journal
    Host                ${FLUENTBIT_OPENSEARCH_HOST}
    Port                ${FLUENTBIT_OPENSEARCH_PORT}
    Logstash_Format     On
    Logstash_Prefix     ${FLUENTBIT_LOGSTASH_PREFIX}
    Replace_Dots        On
    Suppress_Type_Name  On
EOF

  systemctl enable --now fluent-bit
  systemctl restart fluent-bit || true

  log "Fluent Bit status:"
  systemctl --no-pager -l status fluent-bit || true
  journalctl -u fluent-bit -n 50 --no-pager || true
fi

# Helpful extras (safe)
dnf -y install \
  libguestfs-tools \
  lsof \
  tcpdump \
  >/dev/null || true

# Optional cockpit
if [[ "$INSTALL_COCKPIT" == "1" ]]; then
  log "Installing cockpit"
  dnf -y install cockpit cockpit-machines >/dev/null
  systemctl enable --now cockpit.socket || true
fi

# ---- Enable services ----
log "Enabling libvirtd"
systemctl enable --now libvirtd || true

# Ensure default libvirt network doesn't interfere (many KVM node setups prefer pure bridge)
if virsh net-info default &>/dev/null; then
  log "Disabling libvirt 'default' NAT network (common for bridge-based nodes)"
  virsh net-autostart default --disable || true
  virsh net-destroy default || true
fi

# ---- Kernel / sysctl tuning for bridges ----
log "Applying sysctl bridge sanity settings"
cat >/etc/sysctl.d/99-kvm-bridge.conf <<'EOF'
# Avoid iptables/nft filtering on Linux bridges unless you explicitly want it
net.bridge.bridge-nf-call-iptables = 0
net.bridge.bridge-nf-call-ip6tables = 0
net.bridge.bridge-nf-call-arptables = 0
EOF

# Load br_netfilter if present; ignore if module absent
modprobe br_netfilter 2>/dev/null || true
sysctl --system >/dev/null || true

# ---- SELinux / firewall (optional) ----
if [[ "$DISABLE_SELINUX" == "1" ]]; then
  log "Setting SELinux to permissive now and disabling on next reboot"
  setenforce 0 || true
  if [[ -f /etc/selinux/config ]]; then
    sed -ri 's/^\s*SELINUX\s*=.*/SELINUX=disabled/' /etc/selinux/config || true
  fi
fi

if [[ "$DISABLE_FIREWALLD" == "1" ]]; then
  log "Disabling firewalld"
  systemctl disable --now firewalld || true
fi

# ---- Configure correct KVM bridge using NetworkManager ----
if [[ "$CONFIGURE_BRIDGE" == "1" ]]; then
  log "Configuring KVM bridge cloudbr0 with eno1 (canonical NM method)"

  BRIDGE="cloudbr0"
  IFACE="eno1"

  # 1) Kill libvirt default NAT if present
  virsh net-destroy default 2>/dev/null || true
  virsh net-undefine default 2>/dev/null || true

  # 2) Remove virbr0 NM profile if it exists
  nmcli connection delete virbr0 2>/dev/null || true

  # 3) Create bridge profile if missing
  if ! nmcli -t -f NAME connection show | grep -qx "$BRIDGE"; then
    nmcli connection add type bridge ifname "$BRIDGE" con-name "$BRIDGE"
  fi

  # 4) Bridge gets IP (DHCP)
  nmcli connection modify "$BRIDGE" ipv4.method auto ipv6.method ignore

  # 5) Remove existing eno1 profile (CRITICAL STEP)
  nmcli connection delete "$IFACE" 2>/dev/null || true

  # 6) Recreate eno1 as bridge slave
  nmcli connection add \
    type ethernet \
    ifname "$IFACE" \
    con-name "$IFACE" \
    master "$BRIDGE"

  # 7) Bring up bridge first, then slave
  nmcli connection up "$BRIDGE"
  nmcli connection up "$IFACE"

  log "Bridge $BRIDGE successfully configured with slave $IFACE"
fi

# ---- Quick validation ----
log "Validating virtualization support"
if command -v virt-host-validate &>/dev/null; then
  virt-host-validate qemu || true
else
  log "virt-host-validate not found (ok)."
fi

log "KVM module status:"
lsmod | egrep -i 'kvm|kvm_intel|kvm_amd' || true

log "Libvirt status:"
systemctl --no-pager -l status libvirtd || true

log "=== firstboot-kvm completed successfully ==="

if [[ "$REBOOT_AFTER" == "1" ]]; then
  log "Reboot requested (REBOOT_AFTER=1). Rebooting now."
  reboot
fi

exit 0
