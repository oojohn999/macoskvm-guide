#!/bin/bash
# macOS Sequoia VM Launcher - handles DNS and dynamic WSL IP
set -e

VM_DIR="/mnt/e/macos-kvm"
cd "$VM_DIR"

# 1. Setup KVM
echo "[1/5] Setting up KVM..."
sudo sh -c 'echo 1 > /sys/module/kvm/parameters/ignore_msrs' 2>/dev/null || true

# 2. Fix WSL DNS (ensure WSL itself can resolve)
echo "[2/5] Fixing WSL DNS..."
sudo sh -c 'echo "nameserver 8.8.8.8" > /etc/resolv.conf; echo "nameserver 1.1.1.1" >> /etc/resolv.conf' 2>/dev/null || true

# 3. Start DNS proxy (dnsmasq) with dynamic WSL IP
echo "[3/5] Starting DNS proxy..."
# Kill ALL processes on port 53 (dnsmasq, python, etc)
sudo killall dnsmasq 2>/dev/null || true
sudo fuser -k 53/udp 2>/dev/null || true
sudo fuser -k 53/tcp 2>/dev/null || true
sleep 2
WSL_IP=$(hostname -I | awk '{print $1}')
echo "    WSL IP: $WSL_IP"
sudo dnsmasq --listen-address="$WSL_IP" --port=53 --no-dhcp-interface=* \
  --server=8.8.8.8 --server=1.1.1.1 --bind-interfaces
sleep 1
# Verify dnsmasq is running
if pgrep dnsmasq > /dev/null; then
  echo "    dnsmasq OK"
else
  echo "    WARNING: dnsmasq failed, trying fallback..."
  sudo dnsmasq --listen-address=0.0.0.0 --port=53 --no-dhcp-interface=* \
    --server=8.8.8.8 --server=1.1.1.1 2>/dev/null &
  sleep 1
fi

# 4. Kill any existing VM
echo "[4/5] Starting QEMU..."
tmux kill-session -t qemu 2>/dev/null || true
sleep 1

# Launch VM with dynamic DNS pointing to WSL IP
tmux new-session -d -s qemu "qemu-system-x86_64 \
  -enable-kvm -m 16G \
  -cpu Penryn,kvm=on,vendor=GenuineIntel,+invtsc,vmware-cpuid-freq=on,+ssse3,+sse4.2,+popcnt,+avx,+aes,+xsave,+xsaveopt,+avx2,+bmi1,+bmi2,+fma,+movbe,+smep,check \
  -machine q35 \
  -global kvm-pit.lost_tick_policy=delay \
  -global ICH9-LPC.disable_s3=1 \
  -device qemu-xhci,id=xhci \
  -device usb-kbd,bus=xhci.0 -device usb-tablet,bus=xhci.0 \
  -smp 4,cores=2,sockets=1,threads=2 \
  -device isa-applesmc,osk='ourhardworkbythesewordsguardedpleasedontsteal(c)AppleComputerInc' \
  -smbios type=2 \
  -drive if=pflash,format=raw,readonly=on,file=OVMF_CODE_4M.fd \
  -drive if=pflash,format=raw,file=OVMF_VARS_1080.fd \
  -device ich9-ahci,id=sata \
  -drive id=OpenCoreBoot,if=none,format=qcow2,file=OpenCore_osx_kvm.qcow2 \
  -device ide-hd,bus=sata.0,drive=OpenCoreBoot \
  -drive id=MacHDD,if=none,format=qcow2,file=mac_hdd_ng.img \
  -device ide-hd,bus=sata.2,drive=MacHDD \
  -netdev user,id=net0,dns=${WSL_IP} \
  -device virtio-net-pci,netdev=net0,id=net0,mac=52:54:00:c9:18:27 \
  -device ich9-intel-hda -device hda-duplex \
  -device vmware-svga \
  -serial file:/tmp/macos_serial.log \
  -vnc 127.0.0.1:1,password=off \
  -qmp unix:/tmp/qemu.sock,server,nowait \
  -monitor unix:/tmp/qemu_monitor.sock,server,nowait"

# 5. Wait and auto-select Macintosh HD
echo "[5/5] Waiting for OpenCore menu (15 sec)..."
sleep 15

python3 -c "
import socket, json, time
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect('/tmp/qemu.sock')
time.sleep(0.3); s.recv(4096)
s.sendall(json.dumps({'execute':'qmp_capabilities'}).encode() + b'\n')
time.sleep(0.3); s.recv(4096)
s.sendall(json.dumps({'execute':'send-key','arguments':{'keys':[{'type':'qcode','data':'ret'}]}}).encode() + b'\n')
time.sleep(0.3); s.recv(4096); s.close()
print('Booting Macintosh HD...')
"

echo ""
echo "=========================================="
echo "  macOS VM is starting!"
echo "  VNC: 127.0.0.1:5901"
echo "  DNS: $WSL_IP (dnsmasq)"
echo "=========================================="
