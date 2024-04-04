ROOT:=$(CURDIR)
MBUILDPATH:=$(abspath mbuild)
NUM_CORES?=$(shell nproc)
NUM_KEYS?=63

.NOTPARALLEL:

GENV:=PATH=$(shell readlink -f ../depot_tools):$(PATH) DEPOT_TOOLS_UPDATE=0

# ------------------------------------------------------------------------------
GLIBC_SOURCE_DIR:=$(ROOT)/../c3-glibc
GLIBC_INSTALL_DIR:=$(ROOT)/../glibc_install
GLIBC_BUILD_DIR:=$(ROOT)/../glibc_build
LDFLAGS = -nostdlib -nostartfiles -static -L$(GLIBC_INSTALL_DIR)/lib/
STARTFILES = $(GLIBC_BUILD_DIR)/csu/crt1.o $(GLIBC_BUILD_DIR)/csu/crti.o `gcc --print-file-name=crtbegin.o`
ENDFILES = `gcc --print-file-name=crtend.o` $(GLIBC_BUILD_DIR)/csu/crtn.o
LIBGROUP = -Wl,--start-group $(GLIBC_BUILD_DIR)/libc.a -lgcc -lgcc_eh -Wl,--end-group
LDFLAGS_CUSTOM_GLIBC_DYNAMIC = -Wl,--rpath=$(GLIBC_INSTALL_DIR)/lib -Wl,--dynamic-linker=$(GLIBC_INSTALL_DIR)/lib/ld-linux-x86-64.so.2
# ------------------------------------------------------------------------------
CFLAGS_NOAVX=-mavx -mavx2 -mavx512f -mavx512pf -mavx512er -mavx512cd -mavx512vl -mavx512bw -mavx512dq -mavx512ifma -mavx512vbmi
# ------------------------------------------------------------------------------
default:
	false
# ------------------------------------------------------------------------------
.PHONY: package_dependencies
package_dependencies:
	sudo apt install git fakeroot build-essential xz-utils libssl-dev bc flex libelf-dev bison libkeyutils-dev keyutils dwarves cmake linux-tools-common msr-tools cgroup-tools libelf-dev libdw-dev clang gawk pkg-config patchelf libbsd-dev autoconf python3-pip
# # ------------------------------------------------------------------------------
CFLAGS += -g -O0 -Wall -Wshadow -Wno-unused-function -Wno-discarded-qualifiers -Wno-unused-variable -Wno-unused-parameter -Wno-unused-but-set-variable -Werror=shadow -fPIC

# ------------------------------------------------------------------------------
# PartitionAlloc

PA_SO_FILENAME1:=libbase_allocator_partition_allocator_partition_alloc.so
PA_SO_FILENAME2:=libc++.so
PA_SO_PATH:=$(shell readlink -f ../partition_alloc_builder)/out/Default
PA_SO_PATH_FULL:=$(PA_SO_PATH)/$(PA_SO_FILENAME1)

$(PA_SO_PATH_FULL): partition

partition_dependencies=
ifeq ($(wildcard ../partition_alloc_builder/.*),)
partition_dependencies+=../partition_alloc_builder
else
partition_dependencies+=../partition_alloc_builder/out/Default
endif

.PHONY: partition
# partition: $(partition_dependencies) preallocate_keys_if_necessary
partition: $(partition_dependencies) install_glibc
	touch /tmp/.tmp; if [ "../partition_alloc_builder/base/allocator/partition_allocator/BUILD.gn" -nt "/tmp/.tmp" ] ; then touch ../partition_alloc_builder/base/allocator/partition_allocator/BUILD.gn; fi
	cd ../partition_alloc_builder && $(GENV) autoninja -C out/Default
../depot_tools:
	cd .. && git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git
#	echo 'export PATH=$(shell readlink -f ../depot_tools):$$PATH' >> ~/.zshrc
#	echo 'export PATH=$(shell readlink -f ../depot_tools):$$PATH' >> ~/.bashrc
../llvm-project:
	cd .. && git clone -b release/16.x --single-branch https://github.com/llvm/llvm-project.git
../partition_alloc_builder: ../depot_tools ../llvm-project
	if [ ! -d "../partition_alloc_builder" ] ; then cd .. && git clone https://github.com/yuki3/partition_alloc_builder.git ; fi
	git -C ../partition_alloc_builder checkout f2196fb
	cd .. && $(GENV) gclient config https://github.com/yuki3/partition_alloc_builder.git
	cd ../partition_alloc_builder/ && $(GENV) gclient sync
	make partition_alloc_builder_patch
.PHONY: partition_alloc_builder_patch
partition_alloc_builder_patch:
	git -C ../partition_alloc_builder checkout f2196fb416a53d7660573f74c90e6dab643db48b
	git -C ../partition_alloc_builder/buildtools checkout 0cf6a99585d596aca9cb4fb70175fe7307ef183e
	git -C ../partition_alloc_builder/buildtools/clang_format/script checkout e5337933f2951cacd3aeacd238ce4578163ca0b9
	rm -rf ../partition_alloc_builder/buildtools/third_party/libc++/trunk/* ../partition_alloc_builder/buildtools/third_party/libc++abi/trunk/*
	cp -r ../llvm-project/libcxx/*    ../partition_alloc_builder/buildtools/third_party/libc++/trunk
	cp -r ../llvm-project/libcxxabi/* ../partition_alloc_builder/buildtools/third_party/libc++abi/trunk
	true || git -C ../partition_alloc_builder/buildtools/third_party/libc++/trunk checkout 8df190fe9cdd29546a6f4ef7721db45b808c221f
	true || git -C ../partition_alloc_builder/buildtools/third_party/libc++abi/trunk checkout 8d21803b9076b16d46c32e2f10da191ee758520c
	git -C ../partition_alloc_builder/testing checkout f99dbeb6aff754c3409802f6860551d834641a7f
	git -C ../partition_alloc_builder/third_party/googletest/src checkout 9b12f749fa972d08703d8459e9bf3239617491ca
	git -C ../partition_alloc_builder/third_party/lss checkout 9719c1e1e676814c456b55f5f070eabad6709d31
	git -C ../partition_alloc_builder/build_overrides stash
	git -C ../partition_alloc_builder/build_overrides checkout 9de4031586f84ecc31cc512834b18f322cb7a34b
	git -C ../partition_alloc_builder/build checkout 7ff5783a50d3f77446c494d0bf3a809ca8d0c0a5
	git -C ../partition_alloc_builder/base/allocator/partition_allocator stash
	git -C ../partition_alloc_builder/base/allocator/partition_allocator checkout 8ef7102f9e16d0fd974cd3309f70d6150d16aa57
	git -C ../partition_alloc_builder/tools/clang stash
	git -C ../partition_alloc_builder/tools/clang checkout 86501dda633aaea3f8b4c133be4752e9e70069be
	sed -i '/--verify-version/d' ../partition_alloc_builder/build/config/compiler/BUILD.gn
	make llvmfixup
	if [ ! -f "../partition_alloc_builder/base/base_export.h" ] ; then cd ../partition_alloc_builder/base && wget https://raw.githubusercontent.com/chromium/chromium/72a4cb693b057d4e98edc15d9ffb950215e4a029/base/base_export.h ; fi
	git -C ../partition_alloc_builder/base/allocator/partition_allocator apply $(ROOT)/patches/partitionalloc_8ef7102.patch
	touch ../partition_alloc_builder/build/config/cast.gni
	touch ../partition_alloc_builder/build/config/unwind.gni
	echo "put_ref_count_in_previous_slot_default = true" >> ../partition_alloc_builder/build_overrides/partition_alloc.gni
	sed -i 's/^use_cxx17 = false/#use_cxx17 = false/' ../partition_alloc_builder/build_overrides/build.gni
	make ../partition_alloc_builder/out/Default
.PHONY: llvmfixup
llvmfixup:
	python3 ../partition_alloc_builder/tools/clang/scripts/update.py --print-revision || true
	sed -i "s/RELEASE_VERSION = '.*'/RELEASE_VERSION = '17'/" ../partition_alloc_builder/tools/clang/scripts/update.py
	sed -i "s/CLANG_SUB_REVISION = .*/CLANG_SUB_REVISION = 1/" ../partition_alloc_builder/tools/clang/scripts/update.py
	sed -i "s/llvmorg-[0-9]*-init-[0-9]*-[0-9a-zA-Z-]*/llvmorg-17-init-4759-g547e3456/" ../partition_alloc_builder/tools/clang/scripts/update.py
	sed -i "s/llvmorg-[0-9]*-init-[0-9]*-[0-9a-zA-Z-]*/llvmorg-17-init-4759-g547e3456-1/" ../partition_alloc_builder/tools/clang/scripts/build.py
	python3 ../partition_alloc_builder/tools/clang/scripts/update.py --print-revision || true
	python3 ../partition_alloc_builder/tools/clang/scripts/update.py

.PHONY: ../partition_alloc_builder/out/Default
../partition_alloc_builder/out/Default: #../partition_alloc_builder
	cd ../partition_alloc_builder/ && EDITOR=true $(GENV) gn args out/Default

.PHONY: partition_clean
partition_clean: $(partition_dependencies)
	rm -rf ../partition_alloc_builder/out/Default

.PHONY: partition_patch_only
partition_patch_only:
	git -C ../partition_alloc_builder/base/allocator/partition_allocator checkout -- .
	rm -f ../partition_alloc_builder/base/allocator/partition_allocator/dot/address-space.dot
	rm -f ../partition_alloc_builder/base/allocator/partition_allocator/dot/address-space.png
	rm -f ../partition_alloc_builder/base/allocator/partition_allocator/pointers/raw_ptr_noop_impl.h
	rm -f ../partition_alloc_builder/base/allocator/partition_allocator/starscan/stack/asm/riscv64/push_registers_asm.cc
	git -C ../partition_alloc_builder/base/allocator/partition_allocator apply $(ROOT)/patches/partitionalloc_8ef7102.patch
	make ../partition_alloc_builder/out/Default

# ------------------------------------------------------------------------------
# PartitionAlloc configuration

PACFG=../partition_alloc_builder/out/Default/args.gn

.PHONY: _partition_prepare_default
_partition_prepare_default: partition_clean
	cd ../partition_alloc_builder/ && EDITOR=true $(GENV) gn args out/Default

.PHONY: _partition_prepare_common
_partition_prepare_common: partition_clean
	cd ../partition_alloc_builder/ && EDITOR=true $(GENV) gn args out/Default
	echo "tmemk_enable_debug             = false" >> $(PACFG)
	echo "tmemk_override_debug           = false" >> $(PACFG)
	echo "tmemk_override_debug_expensive_checks = false" >> $(PACFG)
	echo "tmemk_returnnull               = true"  >> $(PACFG)
	echo "tmemk_align_at_shim            = false" >> $(PACFG)

.PHONY: _partition_prepare_with_encryption_basics
_partition_prepare_with_encryption_basics: _partition_prepare_common
	echo "tmemk_starting_tags_random     = true"  >> $(PACFG)
	echo "tmemk_enable                   = true"  >> $(PACFG)
	echo "tmemk_encryption               = true"  >> $(PACFG)
	echo "tmemk_integrity                = true"  >> $(PACFG)
	echo "tmemk_padding                  = true"  >> $(PACFG)
	echo "tmemk_notagging                = false" >> $(PACFG)
	echo "tmemk_noalias                  = false" >> $(PACFG)

.PHONY: partition_prepare_stock
partition_prepare_stock: _partition_prepare_common
	echo "tmemk_enable                   = false" >> $(PACFG)
	echo "tmemk_encryption               = false" >> $(PACFG)
	echo "tmemk_integrity                = false" >> $(PACFG)
	echo "tmemk_notagging                = true"  >> $(PACFG)
	echo "tmemk_noalias                  = true"  >> $(PACFG)
	echo "tmemk_padding                  = false" >> $(PACFG)

.PHONY: partition_prepare_just_padding
partition_prepare_just_padding: _partition_prepare_common
	echo "tmemk_enable                   = false" >> $(PACFG)
	echo "tmemk_padding                  = true"  >> $(PACFG)

.PHONY: partition_prepare_twostartingtags
partition_prepare_twostartingtags: _partition_prepare_with_encryption_basics
	echo "tmemk_starting_tags            = true"  >> $(PACFG)
	echo "tmemk_starting_tags_same       = false" >> $(PACFG)
	echo "tmemk_thread_isolation         = false" >> $(PACFG)
	echo "tmemk_never_increment          = false" >> $(PACFG)
	echo "tmemk_skip_memset_when_never_increment = false" >> $(PACFG)

.PHONY: partition_prepare_twostartingtags_no_uaf
partition_prepare_twostartingtags_no_uaf: _partition_prepare_with_encryption_basics
	echo "tmemk_starting_tags            = true"  >> $(PACFG)
	echo "tmemk_starting_tags_same       = false" >> $(PACFG)
	echo "tmemk_thread_isolation         = false" >> $(PACFG)
	echo "tmemk_never_increment          = true"  >> $(PACFG)
	echo "tmemk_skip_memset_when_never_increment = true" >> $(PACFG)

.PHONY: partition_prepare_nostartingtags
partition_prepare_nostartingtags: _partition_prepare_with_encryption_basics
	echo "tmemk_starting_tags            = false" >> $(PACFG)
	echo "tmemk_starting_tags_same       = false" >> $(PACFG)
	echo "tmemk_thread_isolation         = false" >> $(PACFG)
	echo "tmemk_never_increment          = false" >> $(PACFG)
	echo "tmemk_skip_memset_when_never_increment = false" >> $(PACFG)

.PHONY: partition_prepare_samestartingtags
partition_prepare_samestartingtags: _partition_prepare_with_encryption_basics
	echo "tmemk_starting_tags            = true"  >> $(PACFG)
	echo "tmemk_starting_tags_same       = true"  >> $(PACFG)
	echo "tmemk_thread_isolation         = false" >> $(PACFG)
	echo "tmemk_never_increment          = false" >> $(PACFG)
	echo "tmemk_skip_memset_when_never_increment = false" >> $(PACFG)

.PHONY: partition_prepare_uaf_and_tripwires
partition_prepare_uaf_and_tripwires: partition_prepare_samestartingtags
	echo "tmemk_tripwires                = true"  >> $(PACFG)

.PHONY: partition_prepare_tripwires
partition_prepare_tripwires: _partition_prepare_with_encryption_basics
	echo "tmemk_starting_tags            = true"  >> $(PACFG)
	echo "tmemk_starting_tags_same       = true"  >> $(PACFG)
	echo "tmemk_thread_isolation         = false" >> $(PACFG)
	echo "tmemk_skip_memset_when_never_increment = false" >> $(PACFG)
	echo "tmemk_tripwires                = true"  >> $(PACFG)
	echo "tmemk_never_increment          = true" >> $(PACFG)

.PHONY: partition_prepare_only_quarantine
partition_prepare_only_quarantine:
	echo "tmemk_quarantining             = true"  >> $(PACFG)

.PHONY: partition_prepare_size
partition_prepare_size:
	echo "tmemk_maxtagsize               = 1048576" >> $(PACFG)


.PHONY: partition_prepare_only_keybits_1
partition_prepare_only_keybits_1:
	echo "tmemk_keybits                  = 1"     >> $(PACFG)
.PHONY: partition_prepare_only_keybits_2
partition_prepare_only_keybits_2:
	echo "tmemk_keybits                  = 2"     >> $(PACFG)
.PHONY: partition_prepare_only_keybits_3
partition_prepare_only_keybits_3:
	echo "tmemk_keybits                  = 3"     >> $(PACFG)
.PHONY: partition_prepare_only_keybits_4
partition_prepare_only_keybits_4:
	echo "tmemk_keybits                  = 4"     >> $(PACFG)
.PHONY: partition_prepare_only_keybits_5
partition_prepare_only_keybits_5:
	echo "tmemk_keybits                  = 5"     >> $(PACFG)
.PHONY: partition_prepare_only_keybits_6
partition_prepare_only_keybits_6:
	echo "tmemk_keybits                  = 6"     >> $(PACFG)
# ------------------------------------------------------------------------------
.PHONY: glibc
glibc: $(GLIBC_BUILD_DIR)/libc.so

$(GLIBC_BUILD_DIR)/Makefile: $(GLIBC_SOURCE_DIR)
	mkdir -p $(GLIBC_BUILD_DIR)
	cd $(GLIBC_BUILD_DIR); $(GLIBC_SOURCE_DIR)/configure CFLAGS="-O2 -g -fcf-protection=none" --prefix=$(GLIBC_INSTALL_DIR) --disable-nls --enable-memory-tagging --enable-tunables=yes --enable-multi-arch=no
$(GLIBC_BUILD_DIR)/libc.so: $(GLIBC_BUILD_DIR)/Makefile
	make -C $(GLIBC_BUILD_DIR) -j$(shell nproc)

$(GLIBC_INSTALL_DIR)/lib/libc.so: $(GLIBC_BUILD_DIR)/libc.so
	mkdir -p $(GLIBC_INSTALL_DIR)/etc
	touch $(GLIBC_INSTALL_DIR)/etc/ld.so.conf
	make -C $(GLIBC_BUILD_DIR) install

.PHONY: install_glibc
install_glibc: $(GLIBC_INSTALL_DIR)/lib/libc.so

$(ROOT)/../c3-glibc: 
	cd $(ROOT)/.. && git clone https://github.com/IntelLabs/c3-glibc.git
	cd $(ROOT)/../c3-glibc && git checkout 86192d9
	cd $(ROOT)/../c3-glibc && git apply $(ROOT)/patches/glibc-v2.30-c3-86192d9.patch
	sed -i 's/#include "cc_globals.h"//' $(ROOT)/../c3-glibc/include/cc.h
	sed -i 's/#include "cc_globals.h"//' $(ROOT)/../c3-glibc/malloc/malloc.c
	sed -i 's/#include "cc_globals.h"//' $(ROOT)/../c3-glibc/malloc/cc_hook.c
# ------------------------------------------------------------------------------
.PHONY: clean
clean:
	rm -rf build $(GLIBC_BUILD_DIR) $(GLIBC_INSTALL_DIR)
# ------------------------------------------------------------------------------
# Linux
../linux_5_15:
	git clone git://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git ../linux_5_15
	cd ../linux_5_15 && git checkout v5.15
	cd ../linux_5_15 && git apply $(ROOT)/patches/linux_v5-15_integrity.patch

.PHONY: build_linux_initial
build_linux_initial: ../linux_5_15
	cd ../linux_5_15 && yes '' | make clean distclean
	cd ../linux_5_15 && yes '' | make oldconfig && make prepare
	cd ../linux_5_15 && scripts/config --disable SYSTEM_TRUSTED_KEYS && scripts/config --disable SYSTEM_REVOCATION_KEYS && scripts/config --disable CONFIG_NET_VENDOR_NETRONOME && scripts/config --enable CONFIG_X86_INTEL_MKTME && scripts/config --enable CONFIG_X86_MKTME && scripts/config --enable CONFIG_X86_MCE_INJECT && scripts/config --enable CONFIG_ACPI_APEI_EINJ && scripts/config --enable X86_5LEVEL && scripts/config --set-val CONFIG_PGTABLE_LEVELS 5
	sudo sed -i -e 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=menu/' -e 's/GRUB_TIMEOUT=.*/GRUB_TIMEOUT=10/' /etc/default/grub
	sudo sed -i '/GRUB_SAVEDEFAULT=/d' /etc/default/grub
	sudo sed -i -e 's/^GRUB_DEFAULT=.*/GRUB_DEFAULT=saved\nGRUB_SAVEDEFAULT=true/' /etc/default/grub
	sudo sed -i 's/^MODULES=most$$/MODULES=dep/' /etc/initramfs-tools/initramfs.conf
	make build_linux NUM_CORES=$(NUM_CORES)
	make -C ../linux_5_15/tools/perf
.PHONY: build_linux
build_linux: ../linux_5_15
	cd ../linux_5_15 && yes '' | make -j$(NUM_CORES) && sudo make INSTALL_MOD_STRIP=1 -j$(NUM_CORES) modules_install && sudo make install
	make grub
.PHONY: grub
grub:
	sudo grub-set-default "Ubuntu, with Linux 5.15.0+"
	sudo update-grub && sudo grub-mkconfig -o /boot/efi/EFI/ubuntu/grub.cfg
	sudo cp /boot/grub/grubenv /boot/efi/EFI/ubuntu/grubenv
# ------------------------------------------------------------------------------
# Key allocation
.PHONY: preallocate_keys_if_necessary
preallocate_keys_if_necessary: 
	keyctl list @u | grep '$(NUM_KEYS) keys in keyring' || make preallocate_keys
	-wc -l /tmp/tmemk_keys | grep $(NUM_KEYS) || make preallocate_keys
.PHONY: preallocate_keys
preallocate_keys: deallocate_keys
	echo -n "" > /tmp/tmemk_keys
	-for i in $$(seq 1 $(NUM_KEYS)) ; do keyctl add mktme key$${i} "algorithm=aes-xts-128-i type=cpu" @u 2>/dev/null >> /tmp/tmemk_keys ; done
	-keyctl list @u | grep '$(NUM_KEYS) keys in keyring'
	-wc -l /tmp/tmemk_keys | grep $(NUM_KEYS)
.PHONY: deallocate_keys
deallocate_keys:
	@keyctl clear @u
	@keyctl purge mktme >/dev/null
	@sudo keyctl purge mktme >/dev/null
# ------------------------------------------------------------------------------
# program to test our PartitionAlloc
.PHONY: prepare_pa_for_testing
prepare_pa_for_testing: ../partition_alloc_builder/out/Default/current_config_is_test
#.PHONY: ../partition_alloc_builder/out/Default/current_config_is_test
../partition_alloc_builder/out/Default/current_config_is_test:
	make partition_prepare_nostartingtags partition_prepare_only_keybits_4 partition_prepare_size
	touch ../partition_alloc_builder/out/Default/current_config_is_test
	make partition
.PHONY: test
test: test.c prepare_pa_for_testing
	make preallocate_keys_if_necessary NUM_KEYS=15
	gcc \
		$(CFLAGS_NOAVX) \
		-L$(shell readlink -f ../partition_alloc_builder/out/Default/) \
		-o $@ \
		test.c 
	patchelf --set-interpreter $$(readlink -f $(GLIBC_INSTALL_DIR)/lib/ld-linux-x86-64.so.2) --set-rpath $$(readlink -f $(GLIBC_INSTALL_DIR)/lib)/:/usr/lib/x86_64-linux-gnu/:/lib/x86_64-linux-gnu/:/usr/lib/:/lib/x86_64-linux-gnu $@
	patchelf --add-needed $(PA_SO_PATH_FULL) --add-needed /lib/x86_64-linux-gnu/libgcc_s.so.1 ./$@
.PHONY: run_test
run_test: test
	@GLIBC_TUNABLES=glibc.cpu.hwcaps=-AVX2_Usable,-AVX_Fast_Unaligned_Load,-AVX,-SSE2 ./test \
	&& echo "[FAIL] unexpectedly, the test program did not crash" || echo "[OK] as expected, the program crashed"
# ------------------------------------------------------------------------------
