#!/bin/bash
# Prepare template qcow2 for Rocky Linux 9, to be used as a "golden build" for VM cloning.
# run this script on the "Deployer" host after running deploy-deployer.sh and creating the kickstart file (e.g. rocky9-template.cfg).
#
# Before creating the VM, remove any existing VM and its disk to avoid conflicts.

export DEPLOYER=mother.home.lab
export KVM_HOST=mother.home.lab
export KVM_USER=look
export LIBVIRT_DEFAULT_URI=qemu+ssh://$KVM_USER@$KVM_HOST/system
export VMNAME=rocky9-build

# Path to disk image used by the VM
DISK_PATH=/var/lib/libvirt/images/${VMNAME}.qcow2

# If a domain with this name exists, try to stop and undefine it.
if virsh dominfo "$VMNAME" >/dev/null 2>&1; then
  echo "Found existing VM '$VMNAME' — removing..."
  state=$(virsh domstate "$VMNAME" 2>/dev/null || true)
  if echo "$state" | grep -qiE "running|paused|pmsuspended"; then
    echo "VM is running/paused — destroying instance..."
    virsh destroy "$VMNAME" || true
  fi
  echo "Undefining VM..."
  # Try to remove storage via libvirt; fall back to simple undefine if unsupported
  virsh undefine "$VMNAME" --remove-all-storage 2>/dev/null || virsh undefine "$VMNAME" || true
fi

# Remove leftover disk image if present
if [ -f "$DISK_PATH" ]; then
  echo "Removing existing disk image: $DISK_PATH"
  rm -f "$DISK_PATH"
fi

virt-install \
  --name $VMNAME \
  --memory 4096 \
  --vcpus 4 \
  --cpu host-passthrough \
  --disk path=$DISK_PATH,size=8,format=qcow2,bus=virtio \
  --os-variant rocky9 \
  --network bridge=cloudbr0,model=virtio \
  --location http://$DEPLOYER/rocky9 \
  --boot network,hd \
  --graphics none \
  --console pty,target_type=serial \
  --extra-args "inst.ks=http://$DEPLOYER/kickstarts/rocky9-build.cfg console=ttyS0"