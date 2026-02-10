#!/usr/bin/env bash
# openSONIC
# deploy-deployer.sh
# Prepare "Deployer" host providing: DHCP, TFTP, HTTP (nginx) + PXE menus + Rocky ISO exposure.
# Target: Rocky Linux 9.

set -euo pipefail

LOG_FILE="/var/log/opensonic/deploy-deployer.log"
#CONF_FILE="/etc/opensonic/deploy-deployer.conf"
CONF_FILE="./deploy-deployer.conf"

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
chmod 0600 "$LOG_FILE"

mkdir -p "$(dirname "$CONF_FILE")"
touch "$CONF_FILE"

exec > >(tee -a "$LOG_FILE") 2>&1

ts() { date -Is; }
log() { echo "[$(ts)] $*"; }
die() { log "ERROR: $*"; exit 1; }

[[ ${EUID:-0} -eq 0 ]] || die "Run as root."

# ----------------------------
# Defaults (override in deploy-deployer.conf)
# ----------------------------
: "${DEPLOYER_HOSTNAME:=deployer01}"
: "${DEPLOYER_DOMAIN:=home.lab}"
: "${DEPLOYER_IP:=10.11.12.5}"
: "${DEPLOYER_IFACE:=eno1}"

: "${LAN_SUBNET:=10.11.12.0}"
: "${LAN_NETMASK:=255.255.255.0}"
: "${LAN_PREFIX:=24}"
: "${LAN_GATEWAY:=10.11.12.1}"
: "${LAN_RANGE_START:=10.11.12.100}"
: "${LAN_RANGE_END:=10.11.12.200}"
: "${LAN_DNS1:=10.11.12.1}"
: "${LAN_DNS2:=1.1.1.1}"

# PXE
: "${TFTP_ROOT:=/tftpboot}"
: "${WWW_ROOT:=/home/www}"
: "${KS_ROOT:=${WWW_ROOT}/kickstarts}"
: "${ROCKY_MOUNT_HTTP:=${WWW_ROOT}/rocky9}"
: "${ROCKY_MOUNT_TFTP:=${TFTP_ROOT}/rocky9}"

: "${PXE_FILENAME:=lpxelinux.0}"        # syslinux loader; common for BIOS PXE
: "${PXE_MENU_TITLE:=openSONIC Deployer menu}"

# Rocky ISO
: "${ROCKY_ISO_URL:=https://download.rockylinux.org/pub/rocky/9/isos/x86_64/Rocky-9.7-x86_64-minimal.iso}"
: "${ISO_DIR:=${WWW_ROOT}/iso}"

# kickstarts source (optional)
: "${GITHUB_REPO_URL:=}"                # e.g. https://raw.githubusercontent.com/<org>/<repo>/main/kickstarts
: "${CLOUDSTACK_KS:=cloudstack.cfg}"
: "${KVMNODE_KS:=kvmnode.cfg}"

# What to do
: "${INSTALL_TFTP:=1}"
: "${INSTALL_DHCP:=0}"
: "${INSTALL_NGINX:=1}"
: "${CONFIGURE_SELINUX:=1}"
: "${DOWNLOAD_ROCKY_ISO:=1}"
: "${CREATE_PXE_MENUS:=1}"

# Hostnames passed to kickstarts
: "${CLOUDSTACK_HOSTNAME:=cloudstack}"

if [[ -f "$CONF_FILE" ]]; then
  log "Loading config overrides from $CONF_FILE"
  # shellcheck disable=SC1090
  source "$CONF_FILE"
fi

FQDN="${DEPLOYER_HOSTNAME}.${DEPLOYER_DOMAIN}"

log "=== deploy-deployer starting on $(hostname -f 2>/dev/null || hostname) ==="
log "Deployer: ${FQDN} (${DEPLOYER_IP})"
log "LAN: ${LAN_SUBNET}/${LAN_PREFIX} gw ${LAN_GATEWAY} range ${LAN_RANGE_START}-${LAN_RANGE_END}"

# ----------------------------
# Helpers
# ----------------------------
ensure_pkg() {
  local pkgs=("$@")
  log "Installing packages: ${pkgs[*]}"
  dnf -y install "${pkgs[@]}"
}

ensure_firewalld_service() {
  local svc="$1"
  if command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-service="$svc" || true
  fi
}

ensure_firewalld_port() {
  local port="$1"
  if command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port="$port" || true
  fi
}

firewalld_reload() {
  if command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --reload || true
  fi
}

# ----------------------------
# TFTP + Syslinux
# ----------------------------
if [[ "$INSTALL_TFTP" == "1" ]]; then
  log "Configuring TFTP"
  ensure_pkg syslinux-tftpboot tftp-server

  mkdir -p "$TFTP_ROOT"

  # Syslinux payloads (BIOS PXE)
  # Location may vary slightly; these are the common Rocky 9 paths.
  for f in pxelinux.0 lpxelinux.0 ldlinux.c32 libutil.c32 menu.c32 vesamenu.c32 chain.c32; do
    if [[ -f "/tftpboot/${f}" ]]; then
      :
    elif [[ -f "/usr/share/syslinux/${f}" ]]; then
      cp -f "/usr/share/syslinux/${f}" "$TFTP_ROOT/" || true
    elif [[ -f "/usr/share/syslinux/${f##*/}" ]]; then
      cp -f "/usr/share/syslinux/${f##*/}" "$TFTP_ROOT/" || true
    fi
  done

  # Configure tftp to serve proper directory
  cat >/etc/sysconfig/tftp <<EOF_TFTP
TFTP_DIRECTORY="${TFTP_ROOT}"
TFTP_OPTIONS="--secure --verbose"
EOF_TFTP

  # Ensure override directory exists
  mkdir -p /etc/systemd/system/tftp.service.d
  cat >/etc/systemd/system/tftp.service.d/override.conf <<EOF_OVERRIDE
[Service]
ExecStart=
ExecStart=/usr/sbin/in.tftpd -s ${TFTP_ROOT}
EOF_OVERRIDE

  # enable/start
  systemctl daemon-reload
  systemctl enable --now tftp.socket
  systemctl restart tftp.socket

  ensure_firewalld_service tftp
  firewalld_reload
fi

# ----------------------------
# DHCP server (isc-dhcp-server)
# ----------------------------
if [[ "$INSTALL_DHCP" == "1" ]]; then
  log "Configuring DHCP"
  ensure_pkg dhcp-server

  # NOTE: PXE uses DHCP option 66 (next-server) + 67 (boot filename).
  # option 42 is NTP; not used for PXE boot.
  cat >/etc/dhcp/dhcpd.conf <<EOF_DHCP
authoritative;

default-lease-time 600;
max-lease-time 7200;

option domain-name "${DEPLOYER_DOMAIN}";
option domain-name-servers ${LAN_DNS1}, ${LAN_DNS2};

subnet ${LAN_SUBNET} netmask ${LAN_NETMASK} {
  range ${LAN_RANGE_START} ${LAN_RANGE_END};
  option routers ${LAN_GATEWAY};

  # PXE boot
  next-server ${DEPLOYER_IP};
  filename "${PXE_FILENAME}";
}
EOF_DHCP

  # Bind dhcpd to interface
  if [[ -f /etc/sysconfig/dhcpd ]]; then
    sed -ri "s/^DHCPDARGS=.*/DHCPDARGS=\"${DEPLOYER_IFACE}\"/" /etc/sysconfig/dhcpd || true
    grep -q '^DHCPDARGS=' /etc/sysconfig/dhcpd || echo "DHCPDARGS=\"${DEPLOYER_IFACE}\"" >> /etc/sysconfig/dhcpd
  else
    echo "DHCPDARGS=\"${DEPLOYER_IFACE}\"" > /etc/sysconfig/dhcpd
  fi

  systemctl enable --now dhcpd
  systemctl restart dhcpd

  ensure_firewalld_service dhcp
  # Some environments require explicit ports; harmless if redundant
  ensure_firewalld_port 67/udp
  ensure_firewalld_port 68/udp
  firewalld_reload
fi

# ----------------------------
# Nginx WWW root
# ----------------------------
if [[ "$INSTALL_NGINX" == "1" ]]; then
  log "Configuring nginx"
  ensure_pkg nginx

  mkdir -p "$WWW_ROOT" "$KS_ROOT" "$ISO_DIR"

  cat >/etc/nginx/conf.d/default.conf <<EOF_NGX
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name ${FQDN} _;

    root ${WWW_ROOT};

    autoindex on;
    autoindex_exact_size off;
    autoindex_localtime on;

    location / {
        try_files \$uri \$uri/ =404;
    }

    types {
        text/plain .treeinfo;
    }
}
EOF_NGX

  systemctl enable --now nginx

  ensure_firewalld_service http
  ensure_firewalld_service https
  ensure_firewalld_port 80/tcp
  ensure_firewalld_port 443/tcp
  firewalld_reload
fi

# ----------------------------
# SELinux contexts for WWW
# ----------------------------
if [[ "$CONFIGURE_SELINUX" == "1" ]]; then
  log "Configuring SELinux contexts for ${WWW_ROOT}"
  ensure_pkg policycoreutils-python-utils
  semanage fcontext -a -t httpd_sys_content_t "${WWW_ROOT}(/.*)?" 2>/dev/null || true
  restorecon -Rv "$WWW_ROOT" || true
fi

# ----------------------------
# PXE menus
# ----------------------------
if [[ "$CREATE_PXE_MENUS" == "1" ]]; then
  log "Creating PXE menus"
  mkdir -p "${TFTP_ROOT}/pxelinux.cfg"

  cat >"${TFTP_ROOT}/pxelinux.cfg/default" <<EOF_PXE
DEFAULT vesamenu.c32
PROMPT 0
MENU TITLE ${PXE_MENU_TITLE}

LABEL Boot from first hard disk
    MENU LABEL Boot from first hard disk
    COM32 chain.c32
    APPEND hd0

LABEL Installs
    MENU LABEL Installs
    KERNEL vesamenu.c32
    APPEND pxelinux.cfg/installs
EOF_PXE

  # Installs submenu
  cat >"${TFTP_ROOT}/pxelinux.cfg/installs" <<EOF_INST
PROMPT 1

LABEL Install Cloudstack Management
    menu label Cloudstack Management
    kernel http://${DEPLOYER_IP}/rocky9/images/pxeboot/vmlinuz
    INITRD http://${DEPLOYER_IP}/rocky9/images/pxeboot/initrd.img
    APPEND ip=dhcp inst.repo=http://${DEPLOYER_IP}/rocky9 inst.ks=http://${DEPLOYER_IP}/kickstarts/${CLOUDSTACK_KS} hostname=${CLOUDSTACK_HOSTNAME}
    SYSAPPEND 3

LABEL Install KVM node
    menu label Install KVM-node (Rocky9)
    kernel http://${DEPLOYER_IP}/rocky9/images/pxeboot/vmlinuz
    INITRD http://${DEPLOYER_IP}/rocky9/images/pxeboot/initrd.img
    APPEND ip=dhcp inst.repo=http://${DEPLOYER_IP}/rocky9 inst.ks=http://${DEPLOYER_IP}/kickstarts/${KVMNODE_KS} hostname=
    SYSAPPEND 3
EOF_INST
fi

# ----------------------------
# Rocky ISO download + mounts (HTTP + TFTP)
# ----------------------------
if [[ "$DOWNLOAD_ROCKY_ISO" == "1" ]]; then
  log "Ensuring Rocky ISO available"
  ensure_pkg wget
  mkdir -p "$ISO_DIR"

  ISO_NAME="$(basename "$ROCKY_ISO_URL")"
  ISO_PATH="${ISO_DIR}/${ISO_NAME}"

  if [[ ! -f "$ISO_PATH" ]]; then
    log "Downloading ISO: $ROCKY_ISO_URL"
    wget -O "$ISO_PATH" "$ROCKY_ISO_URL"
  else
    log "ISO already present: $ISO_PATH"
  fi

  mkdir -p "$ROCKY_MOUNT_HTTP" "$ROCKY_MOUNT_TFTP"

  # Add fstab entries idempotently
  if ! grep -Fq "$ISO_PATH $ROCKY_MOUNT_HTTP" /etc/fstab; then
    echo "$ISO_PATH $ROCKY_MOUNT_HTTP iso9660 loop,ro,auto 0 0" >> /etc/fstab
  fi
  if ! grep -Fq "$ISO_PATH $ROCKY_MOUNT_TFTP" /etc/fstab; then
    echo "$ISO_PATH $ROCKY_MOUNT_TFTP iso9660 loop,ro,auto 0 0" >> /etc/fstab
  fi

  # Mount now
  mount "$ROCKY_MOUNT_HTTP" || true
  mount "$ROCKY_MOUNT_TFTP" || true
fi

# ----------------------------
# Optional: fetch kickstarts from GitHub raw URL
# ----------------------------
if [[ -n "${GITHUB_REPO_URL}" ]]; then
  log "Fetching kickstarts from ${GITHUB_REPO_URL}"
  ensure_pkg curl
  mkdir -p "$KS_ROOT"

  curl -fsSL "${GITHUB_REPO_URL}/${KVMNODE_KS}" -o "${KS_ROOT}/${KVMNODE_KS}"
  curl -fsSL "${GITHUB_REPO_URL}/${CLOUDSTACK_KS}" -o "${KS_ROOT}/${CLOUDSTACK_KS}"

  log "Kickstarts written to ${KS_ROOT}"
else
  log "GITHUB_REPO_URL is empty: skipping kickstart download (place files in ${KS_ROOT} manually)"
fi

log "=== deploy-deployer completed successfully ==="
log "Useful checks:"
log "  - systemctl status dhcpd tftp.socket nginx"
log "  - firewall-cmd --list-all"
log "  - ls -l ${TFTP_ROOT}/pxelinux.cfg"
log "  - ls -l ${KS_ROOT}"
log "  - curl -I http://${DEPLOYER_IP}/rocky9/.treeinfo"

exit 0
