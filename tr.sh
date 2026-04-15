#!/data/data/com.termux/files/usr/bin/bash
# Termux Terraria 一键安装脚本
# 仓库: https://github.com/1878107721/termux-Terraria-installer
# 用法: bash -c "$(curl -fsSL https://raw.githubusercontent.com/1878107721/termux-Terraria-installer/main/install.sh)"

set -e

echo "========================================"
echo "  Termux Terraria 一键安装 (ARM)"
echo "  清华源加速 + Mesa Vulkan + FNA/FAudio"
echo "========================================"

# ---------- 0. 换清华源加速 ----------
echo "[0/9] 更换 Termux 清华源（加速下载）..."
sed -i 's@^\(deb.*stable main\)$@#\1\ndeb https://mirrors.tuna.tsinghua.edu.cn/termux/termux-packages-24 stable main@' $PREFIX/etc/apt/sources.list
apt update && apt upgrade -y

# ---------- 1. 安装基础工具与图形环境 ----------
echo "[1/9] 安装基础工具、XFCE4、Termux:X11..."
pkg install -y x11-repo
pkg install -y xfce4 termux-x11-nightly
pkg install -y dpkg zip unzip wget curl
pkg install -y pulseaudio

# ---------- 2. 安装 Mesa Vulkan 驱动 ( Freedreno ) ----------
echo "[2/9] 安装 mesa-vulkan-icd-freedreno (Vulkan 加速)..."
pkg install -y mesa-vulkan-icd-freedreno

# ---------- 3. 查找 Terraria 自解压脚本（位于 /sdcard/Download/）----------
echo "[3/9] 在 /sdcard/Download/ 中查找 terraria_v1_4_*.sh ..."
TARGET_DIR=~/Desktop/Terraria
mkdir -p "$TARGET_DIR"

SH_FILE=$(ls /sdcard/Download/terraria_v1_4_*.sh 2>/dev/null | head -n1)
if [ -z "$SH_FILE" ]; then
    echo "❌ 未找到 /sdcard/Download/terraria_v1_4_*.sh"
    echo "请将 Terraria 自解压脚本（如 terraria_v1_4_4_9.sh）放入 /sdcard/Download/ 后重新运行。"
    exit 1
fi

echo "✅ 找到脚本: $SH_FILE"

# ---------- 4. 解压 Terraria（完整解压，提取 data/noarch/game）----------
echo "[4/9] 解压 $SH_FILE 到临时目录..."
TEMP_DIR=$(mktemp -d)
# 自解压脚本本质是 zip，用 unzip 解压
unzip -q "$SH_FILE" -d "$TEMP_DIR" 2>/dev/null || true

if [ ! -d "$TEMP_DIR/data/noarch/game" ]; then
    echo "❌ 解压后未找到 data/noarch/game，请检查脚本文件"
    ls -la "$TEMP_DIR"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# 移动游戏文件到目标目录
mv "$TEMP_DIR/data/noarch/game/"* "$TARGET_DIR/" 2>/dev/null || true
mv "$TEMP_DIR/data/noarch/game/".* "$TARGET_DIR/" 2>/dev/null || true
rm -rf "$TEMP_DIR"

chmod -R 777 "$TARGET_DIR"

if [ ! -f "$TARGET_DIR/Terraria.exe" ]; then
    echo "❌ 解压后未找到 Terraria.exe，请确认脚本内容"
    exit 1
fi
echo "✅ 游戏解压到 $TARGET_DIR"

# ---------- 5. 下载并安装 FNA3D / FAudio（从 GitHub 仓库）----------
echo "[5/9] 从 GitHub 下载 FNA3D 和 FAudio 库..."
# 请确保您的仓库中存在这两个文件，路径按实际调整
FNA3D_URL="https://raw.githubusercontent.com/1878107721/termux-Terraria-installer/main/libFNA3D.so.0"
FAUDIO_URL="https://raw.githubusercontent.com/1878107721/termux-Terraria-installer/main/libFAudio.so.0"

curl -L -o "$PREFIX/lib/libFNA3D.so.0" "$FNA3D_URL"
curl -L -o "$PREFIX/lib/libFAudio.so.0" "$FAUDIO_URL"
# 创建符号链接（不带版本号）
ln -sf libFNA3D.so.0 "$PREFIX/lib/libFNA3D.so"
ln -sf libFAudio.so.0 "$PREFIX/lib/libFAudio.so"
echo "✅ FNA/FAudio 库安装完成"

# ---------- 6. 安装 Mono 及运行时依赖 ----------
echo "[6/9] 安装 Mono, SDL3, OpenAL..."
pkg install -y mono sdl3 openal-soft libglvnd

# ---------- 7. 创建启动脚本（普通版 + Vulkan 版 + 服务端）----------
echo "[7/9] 生成启动脚本..."
# 普通客户端 (OpenGL ES 兼容模式)
cat > "$TARGET_DIR/start-terraria.sh" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
cd ~/Desktop/Terraria
export FNA3D_DRIVER=OpenGL
export SDL_AUDIODRIVER=pulseaudio
SDL_GPU_DRIVER=opengles SDL_HINT_OPENGL_ES_DRIVER=1 mono Terraria.exe
EOF

# Vulkan 客户端 (直接使用 Vulkan 后端，可能不稳定)
cat > "$TARGET_DIR/start-terraria-vulkan.sh" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
cd ~/Desktop/Terraria
export FNA3D_DRIVER=Vulkan
export SDL_AUDIODRIVER=pulseaudio
mono Terraria.exe
EOF

# 服务端
cat > "$TARGET_DIR/start-server.sh" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
cd ~/Desktop/Terraria
echo "启动 Terraria 服务端 (Mono)..."
mono TerrariaServer.exe
EOF

chmod +x "$TARGET_DIR"/start-*.sh
echo "✅ 启动脚本已创建"

# ---------- 8. 创建全局命令 ----------
echo "[8/9] 安装全局命令: start-desktop, start-terraria, start-terraria-vulkan, start-server"
# start-desktop: 启动 Termux:X11 和 XFCE4
cat > $PREFIX/bin/start-desktop <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
termux-x11 &
echo "⏳ 等待 X11 服务启动..."
sleep 5
export DISPLAY=:0
startxfce4 &
echo "✅ 桌面环境已启动（后台运行）"
EOF

# start-terraria: 启动普通客户端
cat > $PREFIX/bin/start-terraria <<EOF
#!/data/data/com.termux/files/usr/bin/bash
$TARGET_DIR/start-terraria.sh
EOF

# start-terraria-vulkan: 启动 Vulkan 客户端
cat > $PREFIX/bin/start-terraria-vulkan <<EOF
#!/data/data/com.termux/files/usr/bin/bash
$TARGET_DIR/start-terraria-vulkan.sh
EOF

# start-server: 启动服务端
cat > $PREFIX/bin/start-server <<EOF
#!/data/data/com.termux/files/usr/bin/bash
$TARGET_DIR/start-server.sh
EOF

chmod +x $PREFIX/bin/start-{desktop,terraria,terraria-vulkan,server}

# ---------- 9. 完成提示 ----------
echo "[9/9] 安装完成！"
echo "========================================"
echo "  🎉 环境配置成功！"
echo ""
echo "  🖥️  启动桌面环境："
echo "     1. 执行命令: start-desktop"
echo "     2. 打开 Termux:X11 App 即可看到 XFCE4 桌面"
echo ""
echo "  🎮 启动游戏："
echo "     普通模式: start-terraria"
echo "     Vulkan模式: start-terraria-vulkan  (可能不稳定)"
echo "     服务端模式: start-server"
echo ""
echo "  📁 游戏文件位置: ~/Desktop/Terraria"
echo "  📦 如需更新 FNA/FAudio，请重新运行本脚本"
echo "========================================"
