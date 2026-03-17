# macOS Sequoia on QEMU/KVM (WSL2 + AMD Ryzen)

在 Windows WSL2 上用 QEMU/KVM 執行 macOS Sequoia 的完整指南。

## 硬體環境

| 項目 | 規格 |
|------|------|
| CPU | AMD Ryzen 7 8700F (Zen 4) |
| RAM | 64GB DDR5 |
| Host OS | Windows 11 + WSL2 Ubuntu |
| VM 分配 | 16GB RAM, 4 vCPU, 256GB 虛擬硬碟 |

## 快速啟動

1. 雙擊桌面 `macOS_VM.bat`
2. 等待 30 秒
3. VNC 連線 `127.0.0.1:5901`
4. macOS 密碼: `214314`

## 檔案結構

```
E:\macos-kvm\
├── OVMF_CODE_4M.fd          # UEFI 韌體 (唯讀)
├── OVMF_VARS_1080.fd        # UEFI 變數 (1080p 解析度)
├── OpenCore_osx_kvm.qcow2   # OpenCore 引導程式 (含 CryptexFixup)
├── mac_hdd_ng.img            # macOS 系統碟 (256GB qcow2)
├── start_vm.sh               # 主要啟動腳本
├── start_macos.sh            # 簡化啟動腳本
├── start_install.sh          # 安裝用腳本 (含 Recovery)
├── fetch-macOS-v2.py         # macOS 下載工具
└── sonoma-recovery/
    └── BaseSystem.img        # macOS Recovery 映像
```

## 關鍵技術細節

### CPU 設定 (最重要!)

```
-cpu Penryn,kvm=on,vendor=GenuineIntel,+invtsc,vmware-cpuid-freq=on,
     +ssse3,+sse4.2,+popcnt,+avx,+aes,+xsave,+xsaveopt,
     +avx2,+bmi1,+bmi2,+fma,+movbe,+smep,check
```

**為什麼用 Penryn + AVX2：**
- `Haswell-noTSX`: 指令集正確但 AMD KVM 上 timer spinloop 卡死
- `Penryn` 原版: 能開機但 macOS Sequoia 需要 AVX2 dyld cache
- `Penryn + AVX2 features`: ✅ 唯一在 AMD KVM 上穩定運行的組合

### CryptexFixup Kext (必須!)

macOS Sequoia 的 dyld shared cache 只有 x86_64h (Haswell+) 版本。
Penryn CPU 無法使用，會導致:
```
initproc failed to start -- Library not loaded: /usr/lib/libSystem.B.dylib
(no such file, no dyld cache)
```

**CryptexFixup** 強制安裝相容的 Rosetta Cryptex，提供通用 dyld cache。

⚠️ **必須在安裝 macOS 時就啟用**，安裝後才加無效（需重裝）。

### OpenCore 設定

- `config.plist` 中 Kernel → Add 包含:
  - Lilu.kext
  - CryptexFixup.kext (1.0.5)
- boot-args: `keepsyms=1 -v debug=0x100 serial=3`
- PickerMode: Builtin (文字模式選單)
- Timeout: 0 (不自動選擇)
- ShowPicker: True

### 網路 (WSL2 DNS 問題修復)

QEMU SLIRP user-mode 網路在 WSL2 下 DNS 解析不穩定。

**解決方案: dnsmasq DNS 代理**

```bash
# 在 WSL 中啟動 dnsmasq
WSL_IP=$(hostname -I | awk '{print $1}')
sudo dnsmasq --listen-address=0.0.0.0 --port=53 \
  --no-dhcp-interface=* --server=8.8.8.8 --server=1.1.1.1 \
  --bind-interfaces &

# QEMU 使用 WSL 的 dnsmasq 作為 DNS
-netdev user,id=net0,dns=${WSL_IP}
```

macOS 內部永久設定:
```bash
sudo networksetup -setdnsservers Ethernet 10.0.2.3
```

### KVM 設定

```bash
# AMD CPU 必須設定 ignore_msrs
sudo sh -c 'echo 1 > /sys/module/kvm/parameters/ignore_msrs'
```

## 已知問題與解決方案

### 1. Kernel Panic: no dyld cache
**原因**: macOS Sequoia 只有 x86_64h dyld cache，Penryn 不支援
**解法**: 安裝時啟用 CryptexFixup kext

### 2. Haswell CPU timer spinloop
**原因**: AMD KVM 的 timer 模擬與 Haswell CPU model 不相容
**解法**: 改用 Penryn base + AVX2 features

### 3. WSL2 DNS 不通
**原因**: QEMU SLIRP 的 UDP DNS 在 WSL2 NAT 下不穩定
**解法**: 在 WSL 跑 dnsmasq，QEMU 指定 dns= 參數

### 4. 電腦重啟後 VM 設定遺失
**原因**: WSL IP 動態變化、ignore_msrs 重置
**解法**: start_vm.sh 動態取得 WSL IP，自動設定所有參數

### 5. vmware-svga 滑鼠 X 軸 2 倍偏移
**原因**: vmware-svga 的解析度回報問題
**暫解**: 滑鼠移到目標左邊一半的位置

### 6. QMP screendump 在 macOS kernel 接管後凍結
**原因**: macOS 切換顯示模式後 vmware-svga framebuffer 卡住
**解法**: 用 VNC 直接連線觀看，或重啟 VM

## 重新安裝指南

如果需要從零開始:

### 1. 準備環境
```bash
sudo apt install qemu-system-x86 qemu-utils tmux python3 dnsmasq
```

### 2. 下載 macOS Recovery
```bash
python3 fetch-macOS-v2.py  # 選擇 Sequoia
dmg2img -i BaseSystem.dmg BaseSystem.img
```

### 3. 建立虛擬硬碟
```bash
qemu-img create -f qcow2 mac_hdd_ng.img 256G
```

### 4. 準備 OpenCore
- 下載 [OSX-KVM](https://github.com/kholia/OSX-KVM) 的 OpenCore image
- 加入 CryptexFixup.kext 到 EFI/OC/Kexts/
- 在 config.plist 的 Kernel → Add 加入 CryptexFixup 項目
- 設定 boot-args: `keepsyms=1 -v debug=0x100 serial=3`

### 5. 安裝 macOS
```bash
bash start_install.sh  # 包含 Recovery 映像
# 在 Recovery 中:
# 1. 磁碟工具程式 → 格式化 Macintosh HD (APFS)
# 2. 安裝 macOS Sequoia
# 或用 Terminal:
# /Install\ macOS\ Sequoia.app/Contents/Resources/startosinstall \
#   --agreetolicense --volume /Volumes/Macintosh\ HD
```

### 6. 修改 OpenCore EFI 分區
```bash
# 轉換 qcow2 → raw
qemu-img convert -O raw OpenCore_osx_kvm.qcow2 /tmp/oc_raw.img
# 取出 EFI 分區
dd if=/tmp/oc_raw.img of=/tmp/oc_efi.img bs=512 skip=2048 count=297953
# 用 mtools 修改
mcopy -i /tmp/oc_efi.img ::/EFI/OC/config.plist /tmp/oc_config.plist
# ... 編輯 config.plist ...
mdel -i /tmp/oc_efi.img ::/EFI/OC/config.plist
mcopy -i /tmp/oc_efi.img /tmp/oc_config.plist ::/EFI/OC/config.plist
# 寫回
dd if=/tmp/oc_efi.img of=/tmp/oc_raw.img bs=512 seek=2048 conv=notrunc
qemu-img convert -O qcow2 /tmp/oc_raw.img OpenCore_osx_kvm.qcow2
```

## 參考資源

- [OSX-KVM](https://github.com/kholia/OSX-KVM)
- [CryptexFixup](https://github.com/acidanthera/CryptexFixup)
- [OpenCore](https://github.com/acidanthera/OpenCorePkg)
- [Nicholas Sherlock - macOS on Proxmox](https://www.nicksherlock.com/2022/10/installing-macos-13-ventura-on-proxmox/)
