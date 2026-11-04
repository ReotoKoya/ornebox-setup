#!/bin/bash
# orne-box の開発環境を Ubuntu 22.04 に一括で用意する。
#
# Usage:
#   ./setup.sh            # 全ステップを順に実行
#   ./setup.sh navvla     # 指定したステップだけ実行(複数可)
#
# ステップ: apt udev livox repos ypspur rosdep build navvla env models
# どのステップも再実行して問題ないように書いてある。途中で落ちたら直してから同じステップを再実行する。
set -eo pipefail

SETUP_DIR="$(cd "$(dirname "$0")" && pwd)"
WS="${HOME}/ornebox_ws"
NAVVLA_VENV="${HOME}/navvla_venv"

log() { echo -e "\n\033[1;32m==> $*\033[0m"; }

step_apt() {
    log "apt: ROS 2 Humble とビルド依存"
    if [ ! -f /etc/apt/sources.list.d/ros2.list ] && [ ! -d /opt/ros/humble ]; then
        sudo apt update && sudo apt install -y software-properties-common curl
        sudo add-apt-repository -y universe
        sudo curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo "$UBUNTU_CODENAME") main" \
            | sudo tee /etc/apt/sources.list.d/ros2.list > /dev/null
    fi
    sudo apt update
    sudo apt install -y \
        ros-humble-desktop-full ros-humble-joy ros-humble-v4l2-camera \
        python3-colcon-common-extensions python3-rosdep python3-vcstool python3-venv python3-pip \
        git build-essential cmake curl \
        libpcl-dev libeigen3-dev libapr1-dev libreadline-dev pcl-tools \
        espeak-ng alsa-utils libasound2-plugins pulseaudio-utils
}

step_udev() {
    log "udev: icart-mini を /dev/sensors/icart-mini に固定"
    sudo cp "${SETUP_DIR}/udev/"*.rules /etc/udev/rules.d/
    sudo udevadm control --reload-rules && sudo udevadm trigger
    if ! id -nG "$USER" | grep -qw dialout; then
        sudo usermod -aG dialout "$USER"
        echo "dialout グループに追加した。反映には再ログインが必要。"
    fi
}

step_livox() {
    log "Livox-SDK2 (livox_ros_driver2 が /usr/local/lib のものを使う)"
    if [ -f /usr/local/lib/liblivox_lidar_sdk_shared.so ]; then
        echo "インストール済みなのでスキップ"
        return
    fi
    local tmp
    tmp="$(mktemp -d)"
    git clone --depth 1 https://github.com/Livox-SDK/Livox-SDK2.git "${tmp}/Livox-SDK2"
    cmake -S "${tmp}/Livox-SDK2" -B "${tmp}/Livox-SDK2/build"
    make -C "${tmp}/Livox-SDK2/build" -j"$(nproc)"
    sudo make -C "${tmp}/Livox-SDK2/build" install
    sudo ldconfig
    rm -rf "${tmp}"
}

step_repos() {
    log "リポジトリを ${WS} に展開"
    mkdir -p "${WS}/src"
    vcs import --skip-existing "${WS}" < "${SETUP_DIR}/ornebox.repos"
    # livox_ros_driver2 は ROS1/ROS2 両対応で package.xml を git に入れていない。
    # 付属の build.sh と同じく ROS2 用をコピーする(無いと rosdep にもビルドにも見えない)
    local livox="${WS}/src/livox_ros_driver2"
    [ -f "${livox}/package.xml" ] || cp "${livox}/package_ROS2.xml" "${livox}/package.xml"
}

step_ypspur() {
    log "yp-spur を /usr/local にインストール (ypspur-coordinator を PATH から呼ぶため)"
    if command -v ypspur-coordinator > /dev/null; then
        echo "インストール済みなのでスキップ"
        return
    fi
    local build="${WS}/src/yp-spur/build_system"
    cmake -S "${WS}/src/yp-spur" -B "${build}"
    make -C "${build}" -j"$(nproc)"
    sudo make -C "${build}" install
    sudo ldconfig
    rm -rf "${build}"
}

step_rosdep() {
    log "rosdep で package.xml の依存を入れる"
    [ -f /etc/ros/rosdep/sources.list.d/20-default.list ] || sudo rosdep init
    rosdep update
    source /opt/ros/humble/setup.bash
    # ワークスペース内で解決するもの・上の apt で入れたもの・rosdep に定義のないキーは飛ばす
    rosdep install -y -r --from-paths "${WS}/src" "${WS}/NavVLA" --ignore-src --rosdistro humble \
        --skip-keys "ypspur libreadline catkin libpcl-all-dev apr git ament_python"
}

step_build() {
    log "colcon build (apt 版 ROS 2)"
    source /opt/ros/humble/setup.bash
    # ROS_EDITION / HUMBLE_ROS は livox_ros_driver2 の CMakeLists.txt が見る (build.sh と同じ値)
    (cd "${WS}" && colcon build --cmake-args -DROS_EDITION=ROS2 -DHUMBLE_ROS=humble)
}

step_navvla() {
    log "NavVLA 用 venv: ${NAVVLA_VENV}"
    [ -d "${NAVVLA_VENV}" ] || python3 -m venv --system-site-packages "${NAVVLA_VENV}"
    "${NAVVLA_VENV}/bin/pip" install -r "${SETUP_DIR}/requirements-navvla.txt"
}

step_env() {
    log "環境スクリプト env_navvla.sh を ${WS} に配置"
    cp "${SETUP_DIR}/env/env_navvla.sh" "${WS}/"
}

step_models() {
    log "CLIP の重みを事前にダウンロード (現地はオフライン前提)"
    # NavVLA: CLIP ViT-B/32 -> ~/.cache/clip/ViT-B-32.pt
    PYTHONPATH="${NAVVLA_VENV}/lib/python3.10/site-packages" \
        /usr/bin/python3 -c "import clip; clip.load('ViT-B/32', device='cpu')"
}

ALL_STEPS=(apt udev livox repos ypspur rosdep build navvla env models)
steps=("$@")
[ ${#steps[@]} -eq 0 ] && steps=("${ALL_STEPS[@]}")
for s in "${steps[@]}"; do
    if ! declare -F "step_${s}" > /dev/null; then
        echo "不明なステップ: ${s} (使えるもの: ${ALL_STEPS[*]})" >&2
        exit 1
    fi
    "step_${s}"
done

log "完了"
echo "学習済みの重みは自動では入らない。README の「重みの配置」を見て手で置くこと。"
