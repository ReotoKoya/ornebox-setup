#!/bin/bash
# orne-box の開発環境を Ubuntu 22.04 に一括で用意する。
#
# Usage:
#   ./setup.sh            # 全ステップを順に実行
#   ./setup.sh navvla     # 指定したステップだけ実行(複数可)
#
# ステップ: apt udev livox ypspur repos rosdep build navvla smolvla env models
# どのステップも再実行して問題ないように書いてある。途中で落ちたら直してから同じステップを再実行する。
set -eo pipefail

SETUP_DIR="$(cd "$(dirname "$0")" && pwd)"
WS="${HOME}/ornebox_ws"
SMOLVLA_WS="${HOME}/smolvla_ws"
NAVVLA_VENV="${HOME}/navvla_venv"
CONDA_ROOT="${HOME}/miniforge3"

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
        libpcl-dev libeigen3-dev libapr1-dev libreadline-dev \
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
    # lerobot サブモジュールの URL は SSH なので、鍵なしでも取れるよう https に差し替える
    git -C "${WS}/src/SmolVLA" config submodule.lerobot.url https://github.com/open-rdc/lerobot.git
    git -C "${WS}/src/SmolVLA" submodule update --init
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
    # smolvla_nav は conda 版 ROS 2 で ${SMOLVLA_WS} に別ビルドする
    (cd "${WS}" && colcon build --packages-skip smolvla_nav)
}

step_navvla() {
    log "NavVLA 用 venv: ${NAVVLA_VENV}"
    [ -d "${NAVVLA_VENV}" ] || python3 -m venv --system-site-packages "${NAVVLA_VENV}"
    "${NAVVLA_VENV}/bin/pip" install -r "${SETUP_DIR}/requirements-navvla.txt"
}

step_smolvla() {
    log "SmolVLA 用 conda 環境 ros_humble"
    if [ ! -d "${CONDA_ROOT}" ]; then
        local installer
        installer="$(mktemp --suffix=.sh)"
        curl -fsSL -o "${installer}" "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh"
        bash "${installer}" -b -p "${CONDA_ROOT}"
        rm -f "${installer}"
    fi
    source "${CONDA_ROOT}/etc/profile.d/conda.sh"
    if conda env list | grep -qE '^ros_humble\s'; then
        mamba env update -n ros_humble -f "${SETUP_DIR}/environment-smolvla.yml"
    else
        mamba env create -f "${SETUP_DIR}/environment-smolvla.yml"
    fi
    conda activate ros_humble
    pip install -e "${WS}/src/SmolVLA/lerobot[smolvla]"

    # apt 版 ROS 2 の install ツリーを混ぜないよう、smolvla_nav は専用ワークスペースでビルドする
    mkdir -p "${SMOLVLA_WS}/src"
    ln -sfn "${WS}/src/SmolVLA/deployment" "${SMOLVLA_WS}/src/smolvla_nav"
    (cd "${SMOLVLA_WS}" && colcon build --packages-select smolvla_nav --symlink-install)
    conda deactivate
}

step_env() {
    log "環境切り替えスクリプトを ${WS} に配置"
    cp "${SETUP_DIR}/env/env_navvla.sh" "${SETUP_DIR}/env/env_humble.sh" "${WS}/"
}

step_models() {
    log "公開モデルを事前にダウンロード (現地はオフライン前提)"
    # NavVLA: CLIP ViT-B/32 -> ~/.cache/clip/ViT-B-32.pt
    PYTHONPATH="${NAVVLA_VENV}/lib/python3.10/site-packages" \
        /usr/bin/python3 -c "import clip; clip.load('ViT-B/32', device='cpu')"
    # SmolVLA: ベース VLM -> ~/.cache/huggingface/hub
    "${CONDA_ROOT}/envs/ros_humble/bin/python" -c \
        "from huggingface_hub import snapshot_download; snapshot_download('HuggingFaceTB/SmolVLM2-500M-Video-Instruct')"
}

ALL_STEPS=(apt udev livox repos ypspur rosdep build navvla smolvla env models)
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
