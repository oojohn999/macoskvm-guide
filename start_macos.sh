#!/bin/bash
# macOS Sequoia 日常使用啟動腳本
# 檔案位置：E:\macos-kvm （WSL 中為 /mnt/e/macos-kvm）
cd /mnt/e/macos-kvm

# AMD CPU 需要 ignore_msrs
echo 1 | sudo tee /sys/module/kvm/parameters/ignore_msrs > /dev/null

exec qemu-system-x86_64 \
  -enable-kvm -m 16G \
  -cpu Penryn,kvm=on,vendor=GenuineIntel,+invtsc,vmware-cpuid-freq=on,+ssse3,+sse4.2,+popcnt,+avx,+aes,+xsave,+xsaveopt,+avx2,+bmi1,+bmi2,+fma,+movbe,+smep,check \
  -machine q35 \
  -global kvm-pit.lost_tick_policy=delay \
  -global ICH9-LPC.disable_s3=1 \
  -device qemu-xhci,id=xhci \
  -device usb-kbd,bus=xhci.0 -device usb-tablet,bus=xhci.0 \
  -smp 4,cores=2,sockets=1,threads=2 \
  -device isa-applesmc,osk="ourhardworkbythesewordsguardedpleasedontsteal(c)AppleComputerInc" \
  -smbios type=2 \
  -drive if=pflash,format=raw,readonly=on,file=OVMF_CODE_4M.fd \
  -drive if=pflash,format=raw,file=OVMF_VARS_1080.fd \
  -device ich9-ahci,id=sata \
  -drive id=OpenCoreBoot,if=none,format=qcow2,file=OpenCore_osx_kvm.qcow2 \
  -device ide-hd,bus=sata.0,drive=OpenCoreBoot \
  -drive id=MacHDD,if=none,format=qcow2,file=mac_hdd_ng.img \
  -device ide-hd,bus=sata.2,drive=MacHDD \
  -netdev user,id=net0 \
  -device virtio-net-pci,netdev=net0,id=net0,mac=52:54:00:c9:18:27 \
  -device ich9-intel-hda -device hda-duplex \
  -device vmware-svga \
  -vnc 127.0.0.1:1,password=off \
  -qmp unix:/tmp/qemu.sock,server,nowait \
  -monitor unix:/tmp/qemu_monitor.sock,server,nowait
