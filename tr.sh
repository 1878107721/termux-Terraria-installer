#!/data/data/com.termux/files/usr/bin/bash
# Termux Terraria 一键安装脚本 (Vulkan + Openbox + PulseAudio)
# 仓库: https://github.com/1878107721/termux-Terraria-installer
set -e

echo "========================================"
echo "  Termux Terraria 一键安装 (Vulkan)"
echo "  清华源加速 + Openbox + Vulkan + 音频"
echo "========================================"

# ---------- 0. 换清华源加速 ----------
echo "[0/10] 更换 Termux 清华源（加速下载）..."
sed -i 's@^\(deb.*stable main\)$@#\1\ndeb https://mirrors.tuna.tsinghua.edu.cn/termux/termux-packages-24 stable main@' $PREFIX/etc/apt/sources.list
apt update && apt upgrade -y

# ---------- 1. 安装基础工具与图形环境 ----------
echo "[1/10] 安装基础工具、Termux:X11、Openbox..."
pkg install -y x11-repo
pkg install -y termux-x11-nightly openbox
pkg install -y dpkg zip unzip wget curl
pkg install -y pulseaudio

# ---------- 2. 配置 PulseAudio 音频转发 ----------
echo "[2/10] 配置 PulseAudio 音频转发..."
mkdir -p $PREFIX/etc/pulse/default.pa.d/
cat > $PREFIX/etc/pulse/default.pa.d/termux.pa <<'EOF'
load-module module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1
load-module module-simple-protocol-tcp rate=48000 format=s16le channels=2
EOF
echo "✅ PulseAudio 已配置为 TCP 转发"

# ---------- 3. 安装 Mesa Vulkan 驱动 (Freedreno) ----------
echo "[3/10] 安装 mesa-vulkan-icd-freedreno (Vulkan 加速)..."
pkg install -y mesa-vulkan-icd-freedreno

# ---------- 4. 查找 Terraria 自解压脚本 ----------
echo "[4/10] 在 /sdcard/Download/ 中查找 terraria_v1_4_*.sh ..."
TARGET_DIR=~/Terraria
mkdir -p "$TARGET_DIR"

SH_FILE=$(ls /sdcard/Download/terraria_v1_4_*.sh 2>/dev/null | head -n1)
if [ -z "$SH_FILE" ]; then
    echo "❌ 未找到 /sdcard/Download/terraria_v1_4_*.sh"
    echo "请将 Terraria 自解压脚本（如 terraria_v1_4_4_9.sh）放入 /sdcard/Download/ 后重新运行。"
    exit 1
fi
echo "✅ 找到脚本: $SH_FILE"

# ---------- 5. 解压 Terraria ----------
echo "[5/10] 解压 $SH_FILE 到临时目录..."
TEMP_DIR=$(mktemp -d)
unzip -q "$SH_FILE" -d "$TEMP_DIR" 2>/dev/null || true

if [ ! -d "$TEMP_DIR/data/noarch/game" ]; then
    echo "❌ 解压后未找到 data/noarch/game，请检查脚本文件"
    ls -la "$TEMP_DIR"
    rm -rf "$TEMP_DIR"
    exit 1
fi

mv "$TEMP_DIR/data/noarch/game/"* "$TARGET_DIR/" 2>/dev/null || true
mv "$TEMP_DIR/data/noarch/game/".* "$TARGET_DIR/" 2>/dev/null || true
rm -rf "$TEMP_DIR"
chmod -R 777 "$TARGET_DIR"

if [ ! -f "$TARGET_DIR/Terraria.exe" ]; then
    echo "❌ 解压后未找到 Terraria.exe，请确认脚本内容"
    exit 1
fi
echo "✅ 游戏解压到 $TARGET_DIR"

# ---------- 6. 下载并安装 FNA3D / FAudio ----------
echo "[6/10] 从 GitHub 下载 FNA3D 和 FAudio 库..."
FNA3D_URL="https://raw.githubusercontent.com/1878107721/termux-Terraria-installer/main/libFNA3D.so.0"
FAUDIO_URL="https://raw.githubusercontent.com/1878107721/termux-Terraria-installer/main/libFAudio.so.0"

curl -L -o "$PREFIX/lib/libFNA3D.so.0" "$FNA3D_URL"
curl -L -o "$PREFIX/lib/libFAudio.so.0" "$FAUDIO_URL"
ln -sf libFNA3D.so.0 "$PREFIX/lib/libFNA3D.so"
ln -sf libFAudio.so.0 "$PREFIX/lib/libFAudio.so"
echo "✅ FNA/FAudio 库安装完成"

# ---------- 7. 安装 Mono 及运行时依赖 ----------
echo "[7/10] 安装 Mono, SDL3, OpenAL..."
pkg install -y mono sdl3 openal-soft libglvnd

# ---------- 8. 创建游戏启动脚本 ----------
echo "[8/10] 生成启动脚本..."

cat > "$TARGET_DIR/start-terraria.sh" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -e
GAME_DIR="${GAME_DIR:-$HOME/Terraria}"

[ -f "$GAME_DIR/Terraria.exe" ] || { echo "❌ 未找到 Terraria.exe"; exit 1; }

# 清理旧进程
pkill -f "termux-x11 :0" 2>/dev/null || true
pkill -f "openbox" 2>/dev/null || true
pkill -f "pulseaudio" 2>/dev/null || true
rm -f /data/user/0/com.termux/files/usr/tmp/.X0-lock 2>/dev/null || true

# 启动 PulseAudio（音频转发）
pulseaudio --start --exit-idle-time=-1
sleep 1

# 启动 termux-x11
termux-x11 :0 &
sleep 3

# 启动 openbox
if ! command -v openbox &>/dev/null; then
    pkg install openbox -y
fi
openbox --display :0 &
sleep 2

echo "✅ termux-x11 + openbox + PulseAudio 已启动"
echo "📱 请在 Android 上打开 Termux:X11 app"

# 运行 Terraria
cd "$GAME_DIR"
bash -c "
    export DISPLAY=:0
    export XDG_RUNTIME_DIR=/data/user/0/com.termux/files/usr/tmp
    export SDL_VIDEODRIVER=x11
    export PULSE_SERVER=127.0.0.1
    export MONO_GC_PARAMS=max-heap-size=1024m
    export MONO_ENV_OPTIONS='--gc=sgen --optimize=all'
    export FNA3D_FORCE_DRIVER=Vulkan
    exec mono Terraria.exe -fullscreen -skipselect
"

trap 'pkill -f "termux-x11 :0"; pkill -f openbox; pkill -f pulseaudio' EXIT
EOF

chmod +x "$TARGET_DIR/start-terraria.sh"
echo "✅ 启动脚本已创建"

# ---------- 9. 创建全局命令 ----------
echo "[9/10] 安装全局命令: game"

cat > $PREFIX/bin/game <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
~/Terraria/start-terraria.sh
EOF

chmod +x $PREFIX/bin/game
echo "✅ 全局命令 'game' 已安装"

# ---------- 10. 完成提示 ----------
echo "[10/10] 安装完成！"
echo "========================================"
echo "  🎉 环境配置成功！"
echo ""
echo "  🖥️  启动游戏："
echo "     1. 执行命令: game"
echo "     2. 打开 Termux:X11 App 即可看到游戏画面"
echo "     3. 音频将通过 PulseAudio 转发"
echo ""
echo "  📁 游戏文件位置: ~/Terraria"
echo "  📦 如需更新 FNA/FAudio，请重新运行本脚本"
echo "========================================"    exit 1
fi
echo "✅ 找到脚本: $SH_FILE"

# ---------- 4. 解压 Terraria ----------
echo "[4/9] 解压 $SH_FILE 到临时目录..."
TEMP_DIR=$(mktemp -d)
unzip -q "$SH_FILE" -d "$TEMP_DIR" 2>/dev/null || true

if [ ! -d "$TEMP_DIR/data/noarch/game" ]; then
    echo "❌ 解压后未找到 data/noarch/game，请检查脚本文件"
    ls -la "$TEMP_DIR"
    rm -rf "$TEMP_DIR"
    exit 1
fi

mv "$TEMP_DIR/data/noarch/game/"* "$TARGET_DIR/" 2>/dev/null || true
mv "$TEMP_DIR/data/noarch/game/".* "$TARGET_DIR/" 2>/dev/null || true
rm -rf "$TEMP_DIR"
chmod -R 777 "$TARGET_DIR"

if [ ! -f "$TARGET_DIR/Terraria.exe" ]; then
    echo "❌ 解压后未找到 Terraria.exe，请确认脚本内容"
    exit 1
fi
echo "✅ 游戏解压到 $TARGET_DIR"

# ---------- 5. 下载并安装 FNA3D / FAudio ----------
echo "[5/9] 从 GitHub 下载 FNA3D 和 FAudio 库..."
FNA3D_URL="https://raw.githubusercontent.com/1878107721/termux-Terraria-installer/main/libFNA3D.so.0"
FAUDIO_URL="https://raw.githubusercontent.com/1878107721/termux-Terraria-installer/main/libFAudio.so.0"

curl -L -o "$PREFIX/lib/libFNA3D.so.0" "$FNA3D_URL"
curl -L -o "$PREFIX/lib/libFAudio.so.0" "$FAUDIO_URL"
ln -sf libFNA3D.so.0 "$PREFIX/lib/libFNA3D.so"
ln -sf libFAudio.so.0 "$PREFIX/lib/libFAudio.so"
echo "✅ FNA/FAudio 库安装完成"

# ---------- 6. 安装 Mono 及运行时依赖 ----------
echo "[6/9] 安装 Mono, SDL3, OpenAL..."
pkg install -y mono sdl3 openal-soft libglvnd

# ---------- 7. 创建游戏启动脚本 ----------
echo "[7/9] 生成启动脚本..."

# 主启动脚本 (Vulkan + Openbox)
cat > "$TARGET_DIR/start-terraria.sh" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
set -e
GAME_DIR="${GAME_DIR:-$HOME/Terraria}"

[ -f "$GAME_DIR/Terraria.exe" ] || { echo "❌ 未找到 Terraria.exe"; exit 1; }

# 清理旧进程
pkill -f "termux-x11 :0" 2>/dev/null || true
pkill -f "openbox" 2>/dev/null || true
rm -f /data/user/0/com.termux/files/usr/tmp/.X0-lock 2>/dev/null || true

# 启动 termux-x11
termux-x11 :0 &
sleep 3

# 启动 openbox
if ! command -v openbox &>/dev/null; then
    pkg install openbox -y
fi
openbox --display :0 &
sleep 2

echo "✅ termux-x11 + openbox 已启动"
echo "📱 请在 Android 上打开 Termux:X11 app"

# 运行 Terraria
cd "$GAME_DIR"
bash -c "
    export DISPLAY=:0
    export XDG_RUNTIME_DIR=/data/user/0/com.termux/files/usr/tmp
    export SDL_VIDEODRIVER=x11
    export MONO_GC_PARAMS=max-heap-size=1024m
    export MONO_ENV_OPTIONS='--gc=sgen --optimize=all'
    export FNA3D_FORCE_DRIVER=Vulkan
    exec mono Terraria.exe -fullscreen -skipselect
"

trap 'pkill -f "termux-x11 :0"; pkill -f openbox' EXIT
EOF

chmod +x "$TARGET_DIR/start-terraria.sh"
echo "✅ 启动脚本已创建"

# ---------- 8. 创建全局命令 ----------
echo "[8/9] 安装全局命令: game"

cat > $PREFIX/bin/game <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
~/Terraria/start-terraria.sh
EOF

chmod +x $PREFIX/bin/game
echo "✅ 全局命令 'game' 已安装"

# ---------- 9. 完成提示 ----------
echo "[9/9] 安装完成！"
echo "========================================"
echo "  🎉 环境配置成功！"
echo ""
echo "  🖥️  启动游戏："
echo "     1. 执行命令: game"
echo "     2. 打开 Termux:X11 App 即可看到游戏画面"
echo ""
echo "  📁 游戏文件位置: ~/Terraria"
echo "  📦 如需更新 FNA/FAudio，请重新运行本脚本"
echo "========================================"
