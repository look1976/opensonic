curl -fsSL https://packages.fluentbit.io/fluentbit.key | sudo tee /etc/pki/rpm-gpg/fluentbit.key >/dev/null
sudo tee /etc/yum.repos.d/fluent-bit.repo >/dev/null <<'EOF'
[fluent-bit]
name=Fluent Bit
baseurl = https://packages.fluentbit.io/rockylinux/$releasever/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/fluentbit.key
enabled=1
EOF

sudo dnf -y install fluent-bit
sudo mkdir -p /var/lib/fluent-bit
sudo chown -R fluent-bit:fluent-bit /var/lib/fluent-bit 2>/dev/null || true

sudo systemctl enable --now fluent-bit
sudo systemctl status fluent-bit --no-pager
sudo journalctl -u fluent-bit -n 100 --no-pager

