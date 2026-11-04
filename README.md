# ornebox_setup

orne-box を動かす PC の環境を一括で用意するためのリポジトリ。

## 前提

- Ubuntu 22.04 (x86_64)
- NVIDIA GPU とドライバ (`nvidia-smi` が通ること)。CUDA Toolkit は不要 (torch の wheel に同梱されている)
- open-rdc の GitHub メンバーであること

## 使い方

```bash
git clone https://github.com/Kasaiatsuki/ornebox_setup.git ~/ornebox_setup
cd ~/ornebox_setup
./setup.sh
```

途中で失敗したら、原因を直してからそのステップだけ再実行する (例: `./setup.sh rosdep build`)。

| ステップ | 内容 |
|---|---|
| `apt` | ROS 2 Humble (desktop-full)、joy、v4l2_camera、colcon、vcstool、PCL/Eigen などのビルド依存、pcl-tools、音声案内用の espeak-ng / alsa |
| `udev` | icart-mini を `/dev/sensors/icart-mini` に固定し、ユーザーを `dialout` に追加 |
| `livox` | Livox-SDK2 をビルドして `/usr/local` にインストール |
| `repos` | `ornebox.repos` のリポジトリを `~/ornebox_ws` に clone (SmolVLA の lerobot サブモジュールも) |
| `ypspur` | yp-spur を `/usr/local` にインストール (`ypspur-coordinator` を使うため) |
| `rosdep` | 各 `package.xml` の依存を apt で入れる |
| `build` | `~/ornebox_ws` を colcon build (apt 版 ROS 2) |
| `navvla` | NavVLA 用 venv `~/navvla_venv` (torch 2.6 + CLIP) |
| `smolvla` | miniforge と conda 環境 `ros_humble` (RoboStack 版 ROS 2, Python 3.12, lerobot)、`~/smolvla_ws` のビルド |
| `env` | `env_navvla.sh` / `env_humble.sh` を `~/ornebox_ws` に配置 |
| `models` | CLIP ViT-B/32 と SmolVLM2-500M を事前ダウンロード (現地はオフライン前提) |

`udev` のあとは一度ログアウトして入り直すこと (`dialout` の反映のため)。

## 構成

ROS 2 が 2 系統ある。混ぜると壊れるので、ターミナルごとにどちらか一方だけ source する。

| | 用途 | ROS 2 / Python | 読み込み |
|---|---|---|---|
| apt 版 | 車体・センサ・FAST-LIO・NavVLA | `/opt/ros/humble`, 3.10 | `source ~/ornebox_ws/env_navvla.sh` |
| conda 版 | SmolVLA | `~/miniforge3/envs/ros_humble`, 3.12 | `source ~/ornebox_ws/env_humble.sh` |

SmolVLA だけ分かれているのは、lerobot が Python 3.12 以上を要求し、apt 版 ROS 2 (3.10) と同じプロセスに載らないため。

```
~/ornebox_ws/
├── src/  FAST_LIO_ROS2, livox_ros_driver2, icart_driver, ros2-controller, yp-spur, SmolVLA
├── NavVLA/            # src/ の外。env_navvla.sh の PYTHONPATH がこの位置を前提にしている
├── env_navvla.sh
└── env_humble.sh
~/smolvla_ws/src/smolvla_nav -> ~/ornebox_ws/src/SmolVLA/deployment
~/navvla_venv/
```

## 重みの配置

学習済みの重みは git に入っていないので、手で置く。

| ファイル | 置き場所 |
|---|---|
| `omnivla-edge_fisheye_tsudanuma_v2_e22.pth` | `~/ornebox_ws/NavVLA/deployment/weights/` |
| `placenet.pt` | `~/ornebox_ws/NavVLA/deployment/weights/` と `~/ornebox_ws/src/SmolVLA/deployment/weights/` |
| SmolVLA のチェックポイント (`*_ckpt/pretrained_model`) | `~/ornebox_ws/src/SmolVLA/training/data/weight/` |

NavVLA の重みを置いたら `navvla` を再ビルドする (重みは install 先にコピーされる)。

```bash
source /opt/ros/humble/setup.bash
cd ~/ornebox_ws && colcon build --packages-select navvla
```

## 起動

```bash
# 車体 (icart-mini + カメラ + ジョイスティック)
source ~/ornebox_ws/env_navvla.sh
ros2 launch icart_driver icart_drive.launch.py

# NavVLA (別ターミナル)
source ~/ornebox_ws/env_navvla.sh
ros2 launch navvla navigation.launch.py

# SmolVLA (別ターミナル)
source ~/ornebox_ws/env_humble.sh
ros2 launch smolvla_nav smolvla_nav.launch.py
```

## FAST-LIO (LiDAR オドメトリ)

Livox MID-360 の点群と内蔵 IMU から自己位置 `/Odometry` を出す。データ収集 (`create_data.py`) と rosbag の記録で使う。

### 初回だけ: 有線 LAN の設定

MID-360 は PC と有線 LAN で直結し、IP は次のように固定する。

| | IP |
|---|---|
| MID-360 | `192.168.0.100` |
| PC の有線 LAN | `192.168.0.5/24` (ゲートウェイなし) |

```bash
# 有線 LAN の接続名を確認して (例: "有線接続 1")、IP を固定する
nmcli con show
nmcli con mod "有線接続 1" ipv4.method manual ipv4.addresses 192.168.0.5/24
nmcli con up "有線接続 1"
ping 192.168.0.100   # 応答があれば OK
```

IP は `~/ornebox_ws/src/livox_ros_driver2/config/MID360_config.json` に書いてある。変えたら `livox_ros_driver2` を再ビルドする。

### 起動

LiDAR ドライバと FAST-LIO を別ターミナルで起動する。

```bash
# 1. LiDAR ドライバ: /livox/lidar と /livox/imu が出る
source ~/ornebox_ws/env_navvla.sh
ros2 launch livox_ros_driver2 msg_MID360_launch.py

# 2. FAST-LIO: /Odometry が出る。RViz も一緒に開く
source ~/ornebox_ws/env_navvla.sh
ros2 launch fast_lio mapping.launch.py
```

- 起動直後は IMU の初期化のため、数秒ロボットを動かさない。
- RViz が要らないときは `rviz:=false` を付ける。
- 設定は `~/ornebox_ws/src/FAST_LIO_ROS2/config/mid360.yaml` (`config_file:=` で別ファイルも指定できる)。

### 動作確認

```bash
ros2 topic hz /livox/imu   # 約 200 Hz
ros2 topic hz /livox/lidar # 約 10 Hz
ros2 topic hz /Odometry    # 約 10 Hz
```

`/livox/*` が出ない場合は、LAN の IP 設定とケーブルを確認する。`/livox/*` は出ているのに `/Odometry` が出ない場合は、FAST-LIO のターミナルにエラーが出ていないか見る。

### 地図の保存

`mid360.yaml` で `pcd_save_en: true` にしてあるので、FAST-LIO を Ctrl+C で止めると、走った範囲の点群が `~/ornebox_ws/src/FAST_LIO_ROS2/PCD/scans.pcd` に保存される。次に止めたときに上書きされるので、残したいものは別名でコピーしておく。

```bash
pcl_viewer ~/ornebox_ws/src/FAST_LIO_ROS2/PCD/scans.pcd   # 中身の確認 (pcl-tools)
```

### rosbag の記録 (データ収集時)

```bash
ros2 bag record -o tsukuba_$(date +%Y%m%d_%H%M%S) \
  /livox/lidar /livox/imu /Odometry /tf /tf_static \
  /image_raw/compressed /cmd_vel /joy /autonomous /prompt /path /debug_image
```
