#!/bin/bash

# Recompile ucomp
make -C /workspace/ucomp clean && make -C /workspace/ucomp

# Stop all current ucomp compressors and unload module (ignore errors)
pkill -f ucomp || true
rmmod ucomp 2>/dev/null || true

# Insert ucomp module
insmod /workspace/ucomp/ucomp.ko

# Start ucompd and register compressors
ucompd register

# Run benchmark for ucomp-zstd
insmod ./comp_bench.ko alg=ucomp-zstd path=/workspace/linux_compile/vmlinux
rmmod comp_bench.ko || true

# Run benchmark for ucomp-lzo
insmod ./comp_bench.ko alg=ucomp-lzo path=/workspace/linux_compile/vmlinux
rmmod comp_bench.ko || true
