#!/bin/bash

set -e

SCRIPT_DIR=$(cd $(dirname $0); pwd)
BUILD_DIR=$(pwd)
PROJ_DIR="$SCRIPT_DIR/"

DEBIAN_VERSION="bookworm"

MIRROR="http://ftp.filearena.net/pub/debian/"
MIRROR="http://ftp.au.debian.org/debian/"


DEBIAN_PACKAGES=" \
  linux-image-amd64 \
  bash \
  kmod \
"
DEBIAN_PACKAGES_BAK=" \
  linux-image-amd64 \
  lsb-release \
  locales \
  sudo \
  iptables \
  iptables-persistent \
  ifenslave \
  net-tools \
  openssl \
  openssh-server \
  curl \
  ntp \
  ntpdate \
  ssh \
  strace \
  vim \
  nginx-light \
  tcpdump \
  rsync \
  "
#  gnome-core \

DEBIAN_COMPONENTS="main,universe"
DEBOOTSTRAP_ARCHIVE="$BUILD_DIR/debootstrap-archive.tar"
BOOTSTRAP_DIR=$BUILD_DIR/debootstrap-build-dir
TARGET_ARCH=
RECREATE_ARCHIVE=0
LOCAL_PACKAGES=
IASL_FILE=

print_usage() {
    echo "Usage: $0 options"
    echo "  -d <debian_version>             : The version number of this release - default: 'bookworm'"
    echo "  -a <target_arch>                : The target architecture - (amd64 / armhf / arm64 )"
    echo "  -r                              : Force re-creation of debootstrap package archive ($DEBOOTSTRAP_ARCHIVE) if already exists"
    echo "  -m <debian_mirror_url>          : The URL of the debian mirror to use. Default: http://ftp.au.debian.org/debian/"
    echo "  -l <local-debian_mirror_url>    : The URL of the local debian mirror to use for any additional local packages provided."
    echo "  -p <local_package>              : Additional local debian package to install into the image. Can be added multiple times"
    echo "  -i <acpi-definition-iasl-file>  : Intel ACPI definition file to be compiled/pre-pended to kernel initramfs"
}

lecho() {
    echo "$(date +"%Y-%m-%d_%H:%M:%S.%N") $*"
}

fatal() {
    lecho "*** ERROR *** : $*"
    exit 1
}

fatal_usage() {
    lecho "*** ERROR *** : $*"
    echo ""
    print_usage
    exit 1
}


while getopts ":d:a:m:l:p:ri:?" opt; do
    case $opt in
        "d") DEBIAN_VERSION=$OPTARG ;;
        "a") TARGET_ARCH=$OPTARG ;;
        "m") MIRROR=$OPTARG ;;
        "l") LOCAL_MIRROR=$OPTARG ;;
        "p") LOCAL_PACKAGES="$OPTARG $LOCAL_PACKAGES" ;;
        "r") RECREATE_ARCHIVE=1 ;;
        "i") IASL_FILE=$OPTARG ;;
        "?") print_usage && exit 1 ;;
        "*") print_usage && exit 1 ;;
    esac
done

[ -z "$TARGET_ARCH" ] && fatal "No target-architecture provided"

IAM=`whoami`
[ $IAM != "root" ] && fatal "Must be run as root"

IS_ARM=0
if [ "$TARGET_ARCH" = "armhf" ] || [ "$TARGET_ARCH" = "arm64" ]; then
    IS_ARM=1
    QEMU_BOOTSTRAP=$(which qemu-arm-static)
    #QEMU_BOOTSTRAP=$(which qemu-aarch64-static)
    [ -z "$QEMU_BOOTSTRAP" ] && fatal "Failed to find 'qemu-arm-static', ensure it has been installed"
fi

PACKAGE_LIST=$(for i in $DEBIAN_PACKAGES ; do echo -n "$i," ; done)
PACKAGE_LIST=$(echo $PACKAGE_LIST | sed 's/,*$//g')

mkdir -p $BOOTSTRAP_DIR

[ $RECREATE_ARCHIVE -eq 1 ] && rm -fv $DEBOOTSTRAP_ARCHIVE

if [ ! -e $DEBOOTSTRAP_ARCHIVE ]; then
    
    lecho "Creating the debian package archive $DEBOOTSTRAP_ARCHIVE"
    
    mkdir -p $BOOTSTRAP_DIR || fatal "Failed to create bootstrap dir: $BOOTSTRAP_DIR"

    debootstrap \
            --components=$DEBIAN_COMPONENTS \
            --make-tarball=$DEBOOTSTRAP_ARCHIVE \
            --include=$PACKAGE_LIST \
            --variant=fakechroot \
            --arch $TARGET_ARCH \
            $DEBIAN_VERSION $BOOTSTRAP_DIR/ \
            $MIRROR \
      || fatal "Failed to create debootstrap package archive"

fi

if [ true ]; then
    lecho "Bootstrapping first-stage"

    # Create the rootfs - first-stage
    mkdir -p $BOOTSTRAP_DIR || fatal "Failed to create bootstrap dir: $BOOTSTRAP_DIR"

    debootstrap \
        --verbose \
        --unpack-tarball=$DEBOOTSTRAP_ARCHIVE \
        --components=$DEBIAN_COMPONENTS \
        --include=$PACKAGE_LIST \
        --variant=fakechroot \
        --arch $TARGET_ARCH \
        --foreign \
        $DEBIAN_VERSION \
        $BOOTSTRAP_DIR \
        $MIRROR \
        || fatal "Failed to install first-stage bootstrap"


    if [ $IS_ARM -eq 1 ]; then
        lecho "Deploying qemu-arm-static into bootstrap dir"
        cp -v $QEMU_BOOTSTRAP $BOOTSTRAP_DIR/usr/bin/
    fi

    lecho "Setting debootstrap mirror to: $MIRROR"
    echo "$MIRROR" > $BOOTSTRAP_DIR/debootstrap/mirror

    # Now chroot in to complete the boot strap
    lecho "Bootstrapping second-stage"
    chroot $BOOTSTRAP_DIR /debootstrap/debootstrap --second-stage \
        || fatal "Failed to run second-stage bootstrap"
    
else
    lecho "DE-Bootstrapping"

    # Create the rootfs - first-stage
    mkdir -p $BOOTSTRAP_DIR || fatal "Failed to create bootstrap dir: $BOOTSTRAP_DIR"

    # Not ARM, ie not 'foreign'
    debootstrap \
        --verbose \
        --unpack-tarball=$DEBOOTSTRAP_ARCHIVE \
        --components=$DEBIAN_COMPONENTS \
        --include=$PACKAGE_LIST \
        --variant=fakechroot \
        --arch $TARGET_ARCH \
        $DEBIAN_VERSION \
        $BOOTSTRAP_DIR \
        $MIRROR \
    || fatal "Failed to install first-stage bootstrap"
fi

if [ -n "$IASL_FILE" ]; then
    lecho "Compiling ACPI IASL file"
    # Compile ACPI file
    AML_FILE=$(iasl $IASL_FILE | tee /iasl-compile.log | tr -s ' ' | grep "^AML Output" | cut -d ':' -f 2 | cut -d ' ' -f 2)
    
    lecho "ACPI compiled file:$AML_FILE"

    lecho "Copying ACPI file to /etc/initramfs-tools/DSDT.aml so will be included with mkinitramfs"
    mkdir -p "${BOOTSTRAP_DIR}/etc/initramfs-tools/"
    cp "$AML_FILE" "${BOOTSTRAP_DIR}/etc/initramfs-tools/DSDT.aml"
    #lecho "Creating ACPI prefixed initrd"
    # Pre-concatenate with initrd - ACPI must be uncompressed layer before normal initramfs.
    #cat $AML_FILE $BOOTSTRAP_DIR/initrd.img > $BOOTSTRAP_DIR/boot/initrd-acpi.img
fi

if [ -n "$LOCAL_PACKAGES" ]; then
    for package in $LOCAL_PACKAGES; do
        
        [ ! -e $package ] && echo "ERROR: $package not found" && exit 1

        package_name=$(basename $package)

        lecho "Installing $package_name ($package)"
        cp $package $BOOTSTRAP_DIR/
        fakechroot $BOOTSTRAP_DIR dpkg -i /$package_name \
            || fatal "Failed to run second-stage bootstrap"
    done
fi

lecho "Bootstrap complete, archiving $BOOTSTRAP_DIR"
( cd "$BOOTSTRAP_DIR" && tar c * | gzip -4 -c > "../debian_${DEBIAN_VERSION}_rootfs.tar.gz" )

lecho "Complete, archive debian_${DEBIAN_VERSION}_rootfs.tar.gz created from $BOOTSTRAP_DIR"

