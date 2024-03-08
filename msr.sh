#!/usr/bin/env bash

modprobe msr

IA32_TME_CAPABILITY=$(rdmsr -p 0 -c 0x981)
IA32_TME_ACTIVATE=$(rdmsr -p 0 -c 0x982)
IA32_TME_EXCLUDE_MASK=$(rdmsr -p 0 -c 0x983)
IA32_TME_EXCLUDE_BASE=$(rdmsr -p 0 -c 0x984)
MK_TME_KEYID_BITS=$(( ( IA32_TME_ACTIVATE >> 32 ) & 0xF ))

echo "IA32_TME_CAPABILITY - AES-XTS 128             : "$(( ( IA32_TME_CAPABILITY & (1<< 0) ) != 0))
echo "IA32_TME_CAPABILITY - AES-XTS 128+I           : "$(( ( IA32_TME_CAPABILITY & (1<< 1) ) != 0))
echo "IA32_TME_CAPABILITY - AES-XTS 256             : "$(( ( IA32_TME_CAPABILITY & (1<< 2) ) != 0))
echo "IA32_TME_CAPABILITY - bypass                  : "$(( ( IA32_TME_CAPABILITY >> 31 ) & 1 ))
echo "IA32_TME_CAPABILITY - MK_TME_MAX_KEYS         : "$(( ( IA32_TME_CAPABILITY >> 36 ) & 0x7FFF))
echo ""
echo "IA32_TME_ACTIVATE   - bypass                  : "$(( ( IA32_TME_ACTIVATE >> 31 ) & 1 ))
echo "IA32_TME_ACTIVATE   - TME_ACTIVATE_LOCKED     : "$(( ( IA32_TME_ACTIVATE       ) & 1 ))
echo "IA32_TME_ACTIVATE   - TME_ACTIVATE_ENABLED    : "$(( ( IA32_TME_ACTIVATE       ) & 2 ))
echo "IA32_TME_ACTIVATE   - TME Policy              : "$(( ( IA32_TME_ACTIVATE >>  4 ) & 0xF ))" (0=AES, 1=AES-I, 2=AES-256)"
echo "IA32_TME_ACTIVATE   - MK_TME_KEYID_BITS       : ${MK_TME_KEYID_BITS}. 2^${MK_TME_KEYID_BITS} = "$((1<<MK_TME_KEYID_BITS))
echo "IA32_TME_ACTIVATE   - MK_TME_CRYPTO_ALGS      : "$(( ( IA32_TME_ACTIVATE >> 48 ) & 0xFFFF ))" (bit 0 = AES, etc)"
echo "                          --        AES-128   : "$(( ( IA32_TME_ACTIVATE >> 48 ) & 1 ))
echo "                          --        AES-128+I : "$(( ( IA32_TME_ACTIVATE >> 48 ) & 2 ))
echo "                          --        AES-256   : "$(( ( IA32_TME_ACTIVATE >> 48 ) & 4 ))
echo ""
echo "IA32_TME_EXCLUDE_MASK - enable                : "$(( ( IA32_TME_EXCLUDE_MASK & (1<<11) ) != 0))
echo "IA32_TME_EXCLUDE_MASK - TMEEMASK              : "$(( ( IA32_TME_EXCLUDE_MASK >> 12 ) ))
echo "IA32_TME_EXCLUDE_BASE - TMEEBASE              : "$(( ( IA32_TME_EXCLUDE_BASE >> 12 ) ))
echo ""
