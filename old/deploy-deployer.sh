# openSONIC

# How to jumpstart single Cloudstack management host with KVM nodes as hypervisor hosts

# This script prepares "Deployer" machine which will provide services: DHCP, tftp, www, all necessary config files
# Such VM needs 8GB RAM and 4 vCPUs
# PXE server will offer boot menus for deploying both Cloudstack Management VM and KVM hosts
# Web and tftp services expose contents of Rocky Linux ISO and kickstarts used for deployments

# Sequence

# These steps you perform manually or however you want ;)
# - Install clean Rocky 9 OS, let's assume server name 'deployer01' and IP 10.11.12.5
# make sure you have root and log in there

#  - Install syslinux-tftpboot package and tftpserver and allow incoming traffic it on firewall
dnf -y install syslinux-tftpboot tftp-server
systemctl enable --now tftp.socket
firewall-cmd --permanent --add-service=tftp
firewall-cmd --reload

# Configure tftp to serve proper directory and make sure override is also there
cat >/etc/sysconfig/tftp <<EOF
TFTP_DIRECTORY="/tftpboot"
TFTP_OPTIONS="--secure --verbose"
EOF

cat >/etc/systemd/system/tftp.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=/usr/sbin/in.tftpd -s /tftpboot
EOF

# restart tftp server
systemctl daemon-reexec
systemctl restart tftp.socket

# Install and configure DHCP server and point it to execute lpxelinux.0 from 10.11.12.5 (DHCP option 42)
# !!! Scripts missing !!!

# Install nginx and expose /home/www as root;
yum -y install nginx
cat >/etc/nginx/conf.d/default.conf <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    server_name deployer01.home.lab _;

    root /home/www;

    autoindex on;
    autoindex_exact_size off;
    autoindex_localtime on;

    location / {
        try_files $uri $uri/ =404;
    }

    types {
        text/plain .treeinfo;
    }
}
EOF


# enable Nginx and open firewall ports 80 & 443
systemctl enable nginx
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --reload

# install SELinux management binary
dnf install -y policycoreutils-python-utils

# make sure /home/www is treated nicely by selinux
mkdir -p /home/www
sudo semanage fcontext -a -t httpd_sys_content_t "/home/www(/.*)?"
sudo restorecon -Rv /home/www

# Create main PXE menu

mkdir -p /tftpboot/pxelinux.cfg
cat >/tftpboot/pxelinux.cfg/default <<EOF
DEFAULT vesamenu.c32
PROMPT 0
MENU TITLE openSONIC Deployer menu

LABEL Boot from first hard disk
    MENU LABEL Boot from first hard disk
    COM32 chain.c32
    APPEND hd0

LABEL Installs
        MENU LABEL Installs
        KERNEL vesamenu.c32
        APPEND pxelinux.cfg/installs

EOF

# create installs boot menu

cat >/tftpboot/pxelinux.cfg/installs <<EOF
PROMPT 1

LABEL Install Cloudstack Management
        menu label Cloudstack Management
        kernel http://10.11.12.5/rocky9/images/pxeboot/vmlinuz
        INITRD http://10.11.12.5/rocky9/images/pxeboot/initrd.img
        APPEND ip=dhcp inst.repo=http://10.11.12.5/rocky9 inst.ks=http://10.11.12.5/kickstarts/cloudstack.cfg hostname=cloudstack
        SYSAPPEND 3

LABEL Install KVM node
        menu label Install KVM-node (Rocky9)
        kernel http://10.11.12.5/rocky9/images/pxeboot/vmlinuz
        INITRD http://10.11.12.5/rocky9/images/pxeboot/initrd.img
        APPEND ip=dhcp inst.repo=http://10.11.12.5/rocky9 inst.ks=http://10.11.12.5/kickstarts/kvmnode.cfg hostname=
        SYSAPPEND 3
EOF

# Download and expose Rocky ISO contents (it will provide both kernel/initrd over tftp and OS installation files over http)
mkdir -p /home/www/iso
wget -P /home/www/iso https://download.rockylinux.org/pub/rocky/9/isos/x86_64/Rocky-9.7-x86_64-minimal.iso

# Expose via /home/www/rocky9 for OS installation purposes
mkdir /home/www/rocky9
cat >>/etc/fstab <<EOF
/home/www/iso/Rocky-9.7-x86_64-minimal.iso /home/www/rocky9       iso9660  loop,ro,auto  0 0
EOF
mount /home/www/rocky9

# Expose via tftpboot for kernel/initrd purposes
mkdir -p /tftpboot/rocky9
cat >>/etc/fstab <<EOF
/home/www/iso/Rocky-9.7-x86_64-minimal.iso /tftpboot/rocky9       iso9660  loop,ro,auto  0 0
EOF
mount /tftpboot/rocky9

# put kickstart files to /home/www/kickstarts
# !!! Repo missing so i have no place to put kickstart files !!!
mkdir -p /home/www/kickstarts
wget -P /home/www/kickstarts/ "${GITHUB_REPO_URL}/kvmnode.cfg"
wget -P /home/www/kickstarts/ "${GITHUB_REPO_URL}/cloudstack.cfg"

