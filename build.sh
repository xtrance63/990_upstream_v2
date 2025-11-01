#!/bin/bash
# Enhanced ExtremeKRNL build script with SUSFS auto-version and summary info

abort() {
    echo "-----------------------------------------------"
    echo "Kernel compilation failed! Exiting..."
    echo "-----------------------------------------------"
    exit 1
}

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]
Options:
    -m, --model [value]    Specify the model code of the phone
    -k, --ksu [y/N]        Include KernelSU
    -r, --recovery [y/N]   Compile kernel for Android Recovery
    -d, --dtbs [y/N]       Compile only DTBs
EOF
}

# -------- Argument parsing --------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --model|-m) MODEL="$2"; shift 2 ;;
        --ksu|-k) KSU_OPTION="$2"; shift 2 ;;
        --recovery|-r) RECOVERY_OPTION="$2"; shift 2 ;;
        --dtbs|-d) DTB_OPTION="$2"; shift 2 ;;
        *) usage; exit 1 ;;
    esac
done

echo "Preparing the build environment..."
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR" || abort
CORES=$(grep -c processor /proc/cpuinfo)

# -------- Toolchain setup --------
CLANG_DIR=$SCRIPT_DIR/toolchain/clang_14
PATH=$CLANG_DIR/bin:$PATH

if [ ! -f "$CLANG_DIR/bin/clang-14" ]; then
    echo "-----------------------------------------------"
    echo "Toolchain not found! Downloading..."
    echo "-----------------------------------------------"
    rm -rf $CLANG_DIR
    mkdir -p $CLANG_DIR
    pushd $CLANG_DIR > /dev/null
    curl -LJOk https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/tags/android-13.0.0_r13/clang-r450784d.tar.gz
    tar xf android-13.0.0_r13-clang-r450784d.tar.gz
    rm android-13.0.0_r13-clang-r450784d.tar.gz
    popd > /dev/null
fi

MAKE_ARGS="LLVM=1 LLVM_IAS=1 ARCH=arm64 O=out"

# -------- Model to board map --------
case $MODEL in
x1slte) BOARD=SRPSJ28B018KU ;;
x1s) BOARD=SRPSI19A018KU ;;
y2slte) BOARD=SRPSJ28A018KU ;;
y2s) BOARD=SRPSG12A018KU ;;
z3s) BOARD=SRPSI19B018KU ;;
c1slte) BOARD=SRPTC30B009KU ;;
c1s) BOARD=SRPTB27D009KU ;;
c2slte) BOARD=SRPTC30A009KU ;;
c2s) BOARD=SRPTB27C009KU ;;
r8s) BOARD=SRPTF26B014KU ;;
*) usage; exit 1 ;;
esac

if [[ "$RECOVERY_OPTION" == "y" ]]; then
    RECOVERY=recovery.config
    KSU_OPTION=n
fi

if [ -z "$KSU_OPTION" ]; then
    read -p "Include KernelSU (y/N): " KSU_OPTION
fi

if [[ "$KSU_OPTION" == "y" ]]; then
    KSU=ksu.config
fi

if [[ "$DTB_OPTION" == "y" ]]; then
    DTBS=y
fi

rm -rf build/out/$MODEL
mkdir -p build/out/$MODEL/zip/files
mkdir -p build/out/$MODEL/zip/META-INF/com/google/android

# -------- Build info summary --------
echo "-----------------------------------------------"
echo "Defconfig: extreme_${MODEL}_defconfig"
echo "KSU: ${KSU:-N}"
echo "Recovery: ${RECOVERY:-N}"
echo "-----------------------------------------------"

# -------- Build config --------
echo "Generating configuration file..."
echo "-----------------------------------------------"
make ${MAKE_ARGS} -j$CORES exynos9830_defconfig ${MODEL}.config ${KSU:-} ${RECOVERY:-} || abort

# -------- Build kernel --------
if [ -z "$DTBS" ]; then
    echo "Building kernel..."
else
    MAKE_ARGS="$MAKE_ARGS dtbs"
    echo "Building DTBs only..."
fi

make ${MAKE_ARGS} -j$CORES || abort

# -------- Detect SUSFS version & variant --------
detect_susfs_version() {
    grep -RsohE '#define[[:space:]]+SUSFS_VERSION[[:space:]]+"v[0-9]+(\.[0-9]+)*"?' include/linux drivers 2>/dev/null |
    head -n1 | grep -oE 'v[0-9]+(\.[0-9]+)*' || echo "unknown"
}

detect_susfs_variant() {
    if grep -q 'SUSFS_VARIANT' include/linux/susfs.h 2>/dev/null; then
        grep -RsohE '#define[[:space:]]+SUSFS_VARIANT[[:space:]]+"[A-Z\-]*"?' include/linux/susfs.h |
        head -n1 | grep -oE '(GKI|NON-GKI)' || echo "unknown"
    else
        echo "unknown"
    fi
}

SUSFS_VERSION=$(detect_susfs_version)
SUSFS_VARIANT=$(detect_susfs_variant)
KERNELSU_NEXT=$(git -C KernelSU-Next describe --tags --always 2>/dev/null || echo "unknown")

# -------- Create boot image --------
DTB_PATH=build/out/$MODEL/dtb.img
KERNEL_PATH=build/out/$MODEL/Image
RAMDISK=build/out/$MODEL/ramdisk.cpio.gz
BOOT_IMG=build/out/$MODEL/boot.img

cp out/arch/arm64/boot/Image $KERNEL_PATH

echo "Building common exynos9830 DTB..."
${SCRIPT_DIR}/toolchain/mkdtimg cfg_create $DTB_PATH build/dtconfigs/exynos9830.cfg -d out/arch/arm64/boot/dts/exynos

echo "Building device DTBO..."
${SCRIPT_DIR}/toolchain/mkdtimg cfg_create build/out/$MODEL/dtbo.img build/dtconfigs/$MODEL.cfg -d out/arch/arm64/boot/dts/samsung

echo "Building RAMDisk..."
pushd build/ramdisk > /dev/null
find . ! -name . | LC_ALL=C sort | cpio -o -H newc -R root:root | gzip > ../out/$MODEL/ramdisk.cpio.gz
popd > /dev/null

echo "Creating boot image..."
${SCRIPT_DIR}/toolchain/mkbootimg \
    --base 0x10000000 --board $BOARD \
    --cmdline "androidboot.hardware=exynos990 loop.max_part=7" \
    --dtb $DTB_PATH --dtb_offset 0x00000000 --hashtype sha1 \
    --header_version 2 --kernel $KERNEL_PATH --kernel_offset 0x00008000 \
    --os_patch_level 2025-08 --os_version 15.0.0 --pagesize 2048 \
    --ramdisk $RAMDISK --ramdisk_offset 0x01000000 \
    --second_offset 0xF0000000 --tags_offset 0x00000100 \
    -o $BOOT_IMG || abort

# -------- Build flashable zip --------
cp $BOOT_IMG build/out/$MODEL/zip/files/boot.img
cp build/out/$MODEL/dtbo.img build/out/$MODEL/zip/files/dtbo.img
cp build/update-binary build/out/$MODEL/zip/META-INF/com/google/android/update-binary
cp build/updater-script build/out/$MODEL/zip/META-INF/com/google/android/updater-script

DATE=$(date +"%d-%m-%Y_%H-%M-%S")
if [[ "$KSU_OPTION" == "y" ]]; then
    ZIP_NAME="ExtremeKRNL-${MODEL}_susfs-${SUSFS_VERSION}_${SUSFS_VARIANT}_UNOFFICIAL_KSU_${DATE}.zip"
else
    ZIP_NAME="ExtremeKRNL-${MODEL}_susfs-${SUSFS_VERSION}_${SUSFS_VARIANT}_UNOFFICIAL_${DATE}.zip"
fi

pushd build/out/$MODEL/zip > /dev/null
zip -r -qq ../"${ZIP_NAME}" .
popd > /dev/null

# -------- Summary --------
echo "-----------------------------------------------"
echo "Build finished successfully!"
echo "Output: build/out/${MODEL}/${ZIP_NAME}"
echo "SUSFS version: ${SUSFS_VERSION}"
echo "SUSFS variant: ${SUSFS_VARIANT}"
echo "KernelSU-Next version: ${KERNELSU_NEXT}"
echo "Toolchain: ${CLANG_DIR}"
echo "-----------------------------------------------"
exit 0
