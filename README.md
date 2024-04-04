# TME-MK-i for Memory Safety

## Overview

Code consists of 3 parts: glibc, Linux, and PartitionAlloc

* glibc: 

Minor tweaks to the publicly available c3 glibc patch https://github.com/IntelLabs/c3-glibc.git based on commit 86192d9.
The patch on top of that can be found in `patches/glibc-v2.30-c3-86192d9.patch`.
Note though that no direct interaction with the patch file is required as the Makefile downloads and builds everything from scratch.

* Linux:

The Linux patch is based on the "Intel MKTME enabling" patchset: https://patchwork.kernel.org/project/kvm/cover/20190731150813.26289-1-kirill.shutemov@linux.intel.com/

Additional changes:
* Port to Linux v5.15
* Allow for memory aliasing.
* Add support for integrity keys
* Handle ECC/integrity exceptions.

* PartitionAlloc:

Based on existing PartitionAlloc, we extend it as described in the IntegriTag paper ("Memory Tagging using Cryptographic Integrity on Commodity x86 CPUs").
Currently, PartitionAlloc is not meant to be built standalone outside of Chrome.
Thus, depending on changes in the dependencies or the system configuration, the Makefile target `partition` needs to be updated accordingly.

## Requirements

This code has been tested with Ubuntu 18.04 and 20.04 using a Sapphire Rapids CPU.
As a prerequisite, the BIOS/UEFI needs to have TME-MK integrity keys enabled.

## Setup

The following guide assumes that we are currently in the directory of this README and that the parent directory is otherwise unused.

```bash
# install required packages
make package_dependencies

# build glibc
make glibc

# download, patch, build, and install linux v5.15
make build_linux_initial

# reboot
# note: make sure to select the correct kernel in the grub boot menu
sudo shutdown -r 0

# after rebooting the newly built kernel, ensure that the BIOS+Kernel have set up the MSRs correctly:
sudo ./msr.sh

# In general, we are expecting the following lines to be printed:
# IA32_TME_CAPABILITY - AES-XTS 128+I           : 1
# IA32_TME_CAPABILITY - MK_TME_MAX_KEYS         : 127 (or higher)
# IA32_TME_ACTIVATE   - TME_ACTIVATE_LOCKED     : 1
# IA32_TME_ACTIVATE   - TME_ACTIVATE_ENABLED    : 2
# IA32_TME_ACTIVATE   - MK_TME_KEYID_BITS       : 6 (or higher)
# IA32_TME_ACTIVATE   - MK_TME_CRYPTO_ALGS      : 3
# 
# For a more detailed description we recommend to refer to the 
# "Intel® Architecture Memory Encryption Technologies" Specification.

# download, patch, and build (the default configuration of) PartitionAlloc
make partition

# run simple test program (test.c) using our custom glibc and PartitionAlloc
make run_test
```

### Known Issues

Support for forking and swapping is currently not implemented.
