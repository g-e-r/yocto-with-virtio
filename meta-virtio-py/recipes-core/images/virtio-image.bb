SUMMARY = "VirtIO image with Python app and serial console"
LICENSE = "MIT"

IMAGE_FEATURES = "\
  package-management \
  ssh-server-dropbear \
  allow-empty-password \
  allow-root-login \
  empty-root-password \
  serial-autologin-root \
  "

inherit core-image

IMAGE_INSTALL:append = "\
    packagegroup-core-boot \
    packagegroup-core-full-cmdline \
    "

IMAGE_INSTALL:append = " \
    python3 \
    python-app \
    kernel-modules \
"
IMAGE_INSTALL:append = " nano pciutils i2c-tools socat"
IMAGE_FSTYPES = "ext4 wic"

# Install eth0 DHCP network config
ROOTFS_POSTPROCESS_COMMAND:append = " install_network_config;"

install_network_config() {
    cat > ${IMAGE_ROOTFS}${sysconfdir}/network/interfaces <<EOF
# /etc/network/interfaces
auto lo
iface lo inet loopback
auto eth0
iface eth0 inet dhcp
EOF
}
