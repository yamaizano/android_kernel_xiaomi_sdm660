#!/bin/bash

yellow='\033[0;33m'
white='\033[0m'
red='\033[0;31m'
gre='\e[0;32m'
ZIMG=./out/arch/arm64/boot/Image.gz-dtb

disable_mkclean=false
no_ebpf_flag=false
mkdtbs=false
oc_flag=false
campatch_flag=false

for arg in $@; do
	case $arg in
		"--noclean") disable_mkclean=true;;
		"--noebpf") no_ebpf_flag=true;;
		"--dtbs") mkdtbs=true;;
		"-oc") oc_flag=true;;
		"-campatch") campatch_flag=true;;
		*) {
			cat <<EOF
Usage: $0 <operate>
operate:
    --noclean   : build without run "make mrproper"
    --noebpf    : build without eBPF
    --dtbs      : build dtbs only
    -oc         : build with apply Overclock patch
    -campatch   : build with apply camera fix patch
EOF
			exit 1
		};;
	esac
done

local_version="v12.3"

# Add two lines of comment text
# to avoid code conflicts when "git cherry-pick" or "git merge".

export LOCALVERSION="-${local_version}-hmp"
$no_ebpf_flag || export LOCALVERSION="${LOCALVERSION}-a12"

rm -f $ZIMG

export ARCH=arm64
export SUBARCH=arm64
export HEADER_ARCH=arm64
export CLANG_PATH=/home/pzqqt/build_toolchain/clang-r458507-15.0.1

export KBUILD_BUILD_HOST="wsl2"
export KBUILD_BUILD_USER="pzqqt"

ccache_=`which ccache`

$oc_flag && { git apply ./oc.patch || exit 1; }
$campatch_flag && { git apply ./campatch.patch || exit 1; }

$disable_mkclean || make mrproper O=out || exit 1
make whyred-perf_defconfig O=out || exit 1

$no_ebpf_flag && {
	for config_item in CGROUP_BPF BPF_SYSCALL NETFILTER_XT_MATCH_BPF NETFILTER_XT_MATCH_OWNER NET_CLS_BPF NET_ACT_BPF BPF_JIT; do
		./scripts/config --file out/.config -d $config_item
	done
	./scripts/config --file out/.config -e NETFILTER_XT_MATCH_QTAGUID
	./scripts/config --file out/.config -e BPF_NETFILTER_XT_MATCH_QTAGUID
}

Start=$(date +"%s")

$mkdtbs && make_flag="dtbs" || make_flag=""

yes | make $make_flag -j$(nproc --all) \
	O=out \
	CC="${ccache_} ${CLANG_PATH}/bin/clang" \
	OBJDUMP=${CLANG_PATH}/bin/llvm-objdump \
	CROSS_COMPILE="/home/pzqqt/build_toolchain/gcc-arm-11.2-2022.02-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-" \
	CROSS_COMPILE_ARM32="/home/pzqqt/build_toolchain/gcc-arm-11.2-2022.02-x86_64-arm-none-linux-gnueabihf/bin/arm-none-linux-gnueabihf-"

exit_code=$?
End=$(date +"%s")
Diff=$(($End - $Start))

$oc_flag && { git apply -R ./oc.patch || exit 1; }
$campatch_flag && { git apply -R ./campatch.patch || exit 1; }

if $mkdtbs; then
	if [ $exit_code -eq 0 ]; then
		echo -e "$gre << Build completed >> \n $white"
	else
		echo -e "$red << Failed to compile dtbs, fix the errors first >>$white"
		exit $exit_code
	fi
else
	if [ -f $ZIMG ]; then
		echo -e "$gre << Build completed in $(($Diff / 60)) minutes and $(($Diff % 60)) seconds >> \n $white"
	else
		echo -e "$red << Failed to compile Image.gz-dtb, fix the errors first >>$white"
		exit $exit_code
	fi
fi
