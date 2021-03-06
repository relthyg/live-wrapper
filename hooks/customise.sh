#!/bin/bash
# customise script for live-wrapper, passed to vmdebootstrap as part
# of the live build

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

for PKG in ${FIRMWARE_PKGS}; do
    echo "$PKG        $PKG/license/accepted       boolean true" | \
	chroot ${rootdir} debconf-set-selections
done

# Needed to make live stuff work
CORE_PACKAGES1="initramfs-tools live-boot live-config"

# Wanted for braille and speech support, #863177
ACC_PACKAGES="brltty espeakup alsa-utils"

# Extra useful packages
CORE_PACKAGES2="task-laptop task-english libnss-myhostname"

PACKAGES_WANTED="$CORE_PACKAGES1 ${ACC_PACKAGES} ${LWR_TASK_PACKAGES} \
                 ${LWR_EXTRA_PACKAGES} ${LWR_FIRMWARE_PACKAGES} \
                 $CORE_PACKAGES2"

chroot ${rootdir} apt-get -q -y install ${PACKAGES_WANTED}  >> vmdebootstrap.log 2>&1

# Work out what extra packages we need for the installer to work. Need
# to run these one at a time, as some of them may conflict if we ask
# apt to install them all together (e.g. grub-efi-$ARCH and grub-pc)
if [ "${LWR_BASE_DEBS}"x != ""x ] ; then
    for PKG in ${LWR_BASE_DEBS}; do
	chroot ${rootdir} apt-get -q -s -u install --reinstall --no-install-recommends $PKG | awk '/^Inst/ {print $2}' >> base_debs.$PKG.list
    done
    sort -u base_debs.*.list > base_debs.list
    rm -f base_debs.*.list
fi

# Temporary fix for #843983
chroot ${rootdir} chmod 755 /

# We told vmdebootstrap to lock the root password, which will have set
# an (encrypted) password field of "!*" in /etc/shadow. That will
# confuse user-setup-udeb later on such that we won't get a root
# password set if we do an installation. Quick hack fix for now is to
# change that. Later on, let's get user-setup-udeb fixed to handle
# this properly too. This is the cause of #866206
sed -i '/root/s,!,,g' ${rootdir}/etc/shadow

# Find all the packages included, including the base_debs
export COLUMNS=500
chroot ${rootdir} dpkg -l | awk '/^ii/ {printf "%s %s\n",$2,$3}' > packages.list

# Grab source URLs for all the packages, including base_debs
if [ -f base_debs.list ]; then
    BASE_DEBS=$(cat base_debs.list)
fi
cat > ${rootdir}//list-sources <<EOF
#!/bin/sh
export COLUMNS=500
for PKG in "${BASE_DEBS}" \$(dpkg -l | awk '/^ii/ {printf "%s ",\$2}'); do
    apt-get source -qq --print-uris \$PKG
done
EOF
chmod +x ${rootdir}/list-sources
chroot ${rootdir} /list-sources > sources.list
rm -f ${rootdir}/list-sources

echo "blacklist bochs-drm" > $rootdir/etc/modprobe.d/qemu-blacklist.conf

remove_daemon_block

replace_apt_source

mv ${rootdir}/etc/resolv.conf ${rootdir}/etc/resolv.conf.bak

