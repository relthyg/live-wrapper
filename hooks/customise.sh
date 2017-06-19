#!/bin/bash

set -e

rootdir=$1

# common needs rootdir to already be defined.
. /usr/share/vmdebootstrap/common/customise.lib

trap cleanup 0

mount_support
disable_daemons

mv ${rootdir}/etc/resolv.conf ${rootdir}/etc/resolv.conf.bak
cat /etc/resolv.conf > ${rootdir}/etc/resolv.conf

prepare_apt_source "${LWR_MIRROR}" "${LWR_DISTRIBUTION}"

${LWR_EXTRA_PACKAGES} task-laptop task-english libnss-myhostname
for PKG in ${FIRMWARE_PKGS}; do
    echo "$PKG        $PKG/license/accepted       boolean true" | \
       chroot ${rootdir} debconf-set-selections
done

chroot ${rootdir} apt-get -q -y install initramfs-tools live-boot live-config ${LWR_TASK_PACKAGES} ${LWR_EXTRA_PACKAGES} ${LWR_FIRMWARE_PACKAGES} task-laptop task-english libnss-myhostname >> vmdebootstrap.log 2>&1

# Temporary fix for #843983
chroot ${rootdir} chmod 755 /

# Find all the packages included
export COLUMNS=500
chroot ${rootdir} dpkg -l | awk '/^ii/ {printf "%s %s\n",$2,$3}' > packages.list

# Grab source URLs for all the packages
cat > ${rootdir}//list-sources <<EOF
#!/bin/sh
export COLUMNS=500
for PKG in \$(dpkg -l | awk '/^ii/ {printf "%s ",\$2}'); do
    apt-get source -qq --print-uris \$PKG
done
EOF
chmod +x ${rootdir}/list-sources
chroot ${rootdir} /list-sources > sources.list
rm -f ${rootdir}/list-sources

echo "blacklist bochs-drm" > $rootdir/etc/modprobe.d/qemu-blacklist.conf

replace_apt_source

mv ${rootdir}/etc/resolv.conf ${rootdir}/etc/resolv.conf.bak

