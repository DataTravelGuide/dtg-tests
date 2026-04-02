#!/bin/bash

# Recompile ucomp
make -C /workspace/ucomp clean && make -C /workspace/ucomp

# Stop all current ucomp compressors and unload module (ignore errors)
ucomp unregister zstd 2>/dev/null || true
ucomp unregister lzo 2>/dev/null || true
pkill -f ucomp || true
rmmod ucomp 2>/dev/null || true

# Insert ucomp module
insmod /workspace/ucomp/ucomp.ko

# Start ucompd and register compressors
ucompd register

# Run benchmark for ucomp-zstd (insmod may report 'busy' if already loaded)
insmod ./comp_bench.ko alg=ucomp-zstd path=/workspace/linux_compile/vmlinux || true

# Run benchmark for ucomp-lzo (insmod may report 'busy' if already loaded)
insmod ./comp_bench.ko alg=ucomp-lzo path=/workspace/linux_compile/vmlinux || true
