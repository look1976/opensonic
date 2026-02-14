# Prepare template qcow2 for Rocky Linux 9, to be used as a "golden build" for VM cloning.
# run this script on the "Deployer" host after running deploy-deployer.sh and creating the kickstart file (e.g. rocky9-template.cfg).
#
# Once the VM is created, install Rocky Linux 9 using the kickstart file, then shut down the VM and convert the qcow2 to a template:

export DEPLOYER=mother.home.lab
export KVM_HOST=mother.home.lab
export KVM_USER=look
export LIBVIRT_DEFAULT_URI=qemu+ssh://$KVM_USER@$KVM_HOST/system

virt-install \
  --name rocky9-build \
  --memory 4096 \
  --vcpus 4 \
  --cpu host-passthrough \
  --disk path=/var/lib/libvirt/images/rocky9-build.qcow2,size=8,format=qcow2,bus=virtio \
  --os-variant rocky9 \
  --network bridge=cloudbr0,model=virtio \
  --location http://$DEPLOYER/rocky9 \
  --boot network,hd \
  --graphics none \
  --console pty,target_type=serial \
  #--noautoconsole \
  --extra-args "inst.ks=http://$DEPLOYER/kickstarts/rocky9-build.cfg console=ttyS0"