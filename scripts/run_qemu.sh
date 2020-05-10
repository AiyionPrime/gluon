#!/bin/sh

qemu-system-x86_64 \
    -d 'cpu_reset' \
    -enable-kvm \
    -s \
    -nographic \
    -netdev user,id=wan,hostfwd=tcp::2223-10.0.2.15:22 \
    -device virtio-net-pci,netdev=wan,addr=0x06,id=nic1 \
    -netdev user,id=lan,hostfwd=tcp::6080-192.168.1.1:80,hostfwd=tcp::2222-192.168.1.1:22,net=192.168.1.100/24 \
    -device virtio-net-pci,netdev=lan,addr=0x05,id=nic2 \
    "$@"
