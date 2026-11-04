#!/bin/bash
# navvla (NavVLA) launch 用の環境スクリプト。
#
# navvla は apt 版 ROS 2 Humble (system Python 3.10) で動かす。torch / clip などは
# システムや ~/.local には入れず、専用 venv ~/navvla_venv (--system-site-packages) に入れてある。
# smolvla 用の env_humble.sh (conda 版 ROS 2, Python 3.12) とは干渉しない。
#
# Usage:
#   source ~/ornebox_ws/env_navvla.sh
#   ros2 launch navvla navigation.launch.py

source /opt/ros/humble/setup.bash
source ${HOME}/ornebox_ws/install/setup.bash

NAVVLA_ROOT=${HOME}/ornebox_ws/NavVLA
NAVVLA_VENV_SITE=${HOME}/navvla_venv/lib/python3.10/site-packages

# venv の site-packages を先頭に置く。ノードは /usr/bin/python3 で起動するので PYTHONPATH で渡す。
# OmniVLA と model_omnivla_edge は手順書 (EXPERIMENT_TSUKUBA.md) のとおり PYTHONPATH で解決する。
export PYTHONPATH="${NAVVLA_VENV_SITE}:${NAVVLA_ROOT}:${NAVVLA_ROOT}/OmniVLA/inference:${PYTHONPATH}"
