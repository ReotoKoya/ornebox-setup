#!/bin/bash
# smolvla_nav launch 専用の環境切り替えスクリプト。
#
# .bashrc は apt 版 ROS 2 Humble (system Python 3.10, ~/ornebox_ws/install) を常時 source しているが、
# smolvla_nav は lerobot(Python>=3.12 必須)と同一プロセスで ROS 2 を import するため、
# RoboStack の conda 版 ROS 2 Humble (Python 3.12, env名: ros_humble) に一時的に切り替える。
#
# smolvla_nav 自体は ~/ornebox_ws とは別の専用ワークスペース ~/smolvla_ws でビルドしている
# (~/ornebox_ws/install/setup.sh は underlay として /opt/ros/humble を焼き込んでいるため、
#  同じ install ツリーを conda 環境で source すると apt 版 ROS 2 が再度混入してしまう)。
#
# Usage:
#   source ~/ornebox_ws/env_humble.sh
#   ros2 launch smolvla_nav smolvla_nav.launch.py

unset AMENT_PREFIX_PATH
# AMENT_CURRENT_PREFIX は ament の setup.sh 系スクリプトが処理中の一時変数として
# 使うが、シェルスコープに残ったままになる。apt版ROS2(/opt/ros/humble)の
# setup.bash を .bashrc で先に source していると、ここに /opt/ros/humble が
# 残留し、後段の conda 版 setup.sh の `: ${AMENT_CURRENT_PREFIX:=...}` が
# 「既に設定済み」と誤認して apt 版のパスを使い続けてしまう
# (結果、python3.12 なのに apt 版 rclpy(python3.10 用so) を import しようとして
#  ModuleNotFoundError: No module named 'rclpy._rclpy_pybind11' で落ちる)。
# 必ずここで一緒に unset すること。
unset AMENT_CURRENT_PREFIX
unset CMAKE_PREFIX_PATH
unset COLCON_PREFIX_PATH
unset ROS_DISTRO
unset ROS_VERSION
unset ROS_PYTHON_VERSION
unset PYTHONPATH
# apt版ROS2(/opt/ros/humble)と system CUDA(/usr/local/cuda-*)由来のパスが残っていると、
# torch がGPUを正しく掴めず無言でCPUにフォールバックすることがあるため、ここで完全にリセットする。
unset LD_LIBRARY_PATH
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games"

source ${HOME}/miniforge3/etc/profile.d/conda.sh
conda activate ros_humble

# SmolVLA(ベースVLMは HuggingFaceTB/SmolVLM2-500M-Video-Instruct)はローカルの
# pretrained_model から重みを読むが、huggingface_hub がキャッシュの有効性を毎回HTTPで
# 確認しに行くため、ネット不調時にそこで固まる/リトライする。キャッシュは揃っているので
# オフラインモードに固定してネット依存を切る。
export HF_HUB_OFFLINE=1
export TRANSFORMERS_OFFLINE=1

# navigation.py / create_data.py は colcon install 後の __file__ からリポジトリルートを
# 逆算しているが、install先はソースツリーと階層が異なるため相対パスが崩れる。
# ここで正しいルートを明示的に渡す。
export SMOLVLA_REPO_ROOT="${HOME}/ornebox_ws/src/SmolVLA"

# place_prompt_node.py も同様に、colcon install 後は __file__ から config/, weights/ を
# 含む smolvla_nav パッケージルート(ソースツリー側)に届かない。ここで明示的に渡す。
export SMOLVLA_NAV_PKG_ROOT="${HOME}/smolvla_ws/src/smolvla_nav"

source ${HOME}/smolvla_ws/install/setup.bash
