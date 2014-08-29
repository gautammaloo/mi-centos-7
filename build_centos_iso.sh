#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

CUR_TIME=`date +%FT%TZ`
CUSTOM_RPMS=./RPMS
DVD_LAYOUT=/data/centos-7-iso-layout
DVD_TITLE='CentOS-7-Joyent'
ISO=CentOS-7.0-1406-x86_64-Minimal.iso
#ISO=CentOS-7.0-1406-x86_64-DVD.iso
ISO_DIR=/data/fetched-iso
ISO_FILENAME=./centos-7-joyent.iso
KS_CFG=./ks.cfg
MIRROR=http://yum.tamu.edu/centos/7.0.1406/isos/x86_64
MOUNT_POINT=/mnt

function fetch_iso() {
    echo "Finding $ISO in $ISO_DIR"
    if [ ! -d $ISO_DIR ]; then
        mkdir -p $ISO_DIR
    fi

    if [ -e $ISO_DIR/$ISO ]; then
        echo "Using $ISO_DIR/$ISO"
    else
        echo "$ISO_DIR/$ISO Not Found...Fetching $ISO from $MIRROR"
        wget -O $ISO_DIR/$ISO $MIRROR/$ISO
    fi
}

function create_layout() {
    echo "Creating ISO Layout"
    if [ -d $DVD_LAYOUT ]; then
        echo "Layout $DVD_LAYOUT exists...nuking"
        rm -rf $DVD_LAYOUT
    fi
    echo "Creating $DVD_LAYOUT"
    mkdir -p $DVD_LAYOUT

    echo "Mounting $ISO to $MOUNT_POINT"
    mount $ISO_DIR/$ISO $MOUNT_POINT -o loop
    pushd $MOUNT_POINT > /dev/null 2>&1
    echo "Populating Layout"
    tar cf - . | tar xpf - -C $DVD_LAYOUT
    popd > /dev/null 2>&1
    umount $MOUNT_POINT
    echo "Copying custom RPMS"
    find $CUSTOM_RPMS -type f -exec cp {} $DVD_LAYOUT/Packages \;
    echo "Finished Populating Layout"
}

function copy_ks_cfg() {
    echo "Copying Kickstart file"
    cp $KS_CFG $DVD_LAYOUT/
}

function copy_guest_tools() {
    echo "Copying sdc-vmtools"
    cp -R ./sdc-vmtools/ $DVD_LAYOUT/ 
}


function modify_boot_menu() {
    echo "Modifying grub boot menu"
    cp ./isolinux.cfg $DVD_LAYOUT/isolinux/
}

function cleanup_layout() {
    echo "Cleaning up $DVD_LAYOUT"
    find $DVD_LAYOUT -name TRANS.TBL -exec rm '{}' +
    COMPS_XML=`find $DVD_LAYOUT/repodata -name '*.xml' ! -name 'repomd.xml' -exec basename {} \;`
    mv $DVD_LAYOUT/repodata/$COMPS_XML $DVD_LAYOUT/repodata/comps.xml 
    find $DVD_LAYOUT/repodata -type f ! -name 'comps.xml' -exec rm '{}' +
}

function create_newiso() {
    copy_guest_tools
    cleanup_layout
    copy_ks_cfg
    modify_boot_menu
    echo "Preparing NEW ISO"
    pushd $DVD_LAYOUT > /dev/null 2>&1
    discinfo=`head -1 .discinfo`
    createrepo -g repodata/comps.xml $DVD_LAYOUT
    echo "Creating NEW ISO"
    mkisofs -r -R -J -T -v \
     -no-emul-boot -boot-load-size 4 -boot-info-table \
     -V "$DVD_TITLE" -p "Joyent" \
     -A "$DVD_TITLE - $CUR_TIME" \
     -b isolinux/isolinux.bin -c isolinux/boot.cat \
     -x "lost+found" -o $ISO_FILENAME $DVD_LAYOUT
    echo "Fixing up NEW ISO"
    echo implantisomd5 $ISO_FILENAME
    implantisomd5 $ISO_FILENAME
    popd > /dev/null 2>&1
    echo "NEW ISO $ISO_FILENAME is ready"
}

# main line

usage()
{
    cat <<EOF
Usage:
        $0 [options] command [command]
option:
        -h                    - this usage

Commands:
        fetch                 - fetch ISO
        layout                - create layout for new ISO
        finish                - create the new ISO

EOF
    exit 1
}

args=`getopt -o h -n 'build_centos_iso.sh' -- "$@"`

if [[ $# == 0 ]]; then
    usage;
fi

eval set -- $args

while true ; do
   case "$1" in
       -h)
            usage;
            break;;
       --)
           shift; break;;
   esac
done

for arg ; do
    if [ $arg = 'fetch' ] ; then
        fetch_iso
    fi
    if [ $arg = 'layout' ] ; then
        create_layout
    fi
    if [ $arg = 'finish' ] ; then
        create_newiso
    fi
done