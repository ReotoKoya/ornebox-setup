# ornebox-setup

orne-box を動かす PC の環境を一括で用意するためのリポジトリ。

## 前提

- Ubuntu 22.04 (x86_64)
- NVIDIA GPU とドライバ (`nvidia-smi` が通ること)。CUDA Toolkit は不要 (torch の wheel に同梱されている)
- open-rdc の GitHub メンバーであること

## 使い方

```bash
git clone https://github.com/Kasaiatsuki/ornebox-setup.git ~/ornebox_setup
cd ~/ornebox_setup
./setup.sh
```

途中で失敗したら、原因を直してからそのステップだけ再実行する (例: `./setup.sh rosdep build`)。

| ステップ | 内容 |
|---|---|
| `apt` | ROS 2 Humble (desktop-full)、joy、v4l2_camera、colcon、vcstool、PCL/Eigen などのビルド依存、pcl-tools、音声案内用の espeak-ng / alsa |
| `udev` | icart-mini を `/dev/sensors/icart-mini` に固定し、ユーザーを `dialout` に追加 |
| `livox` | Livox-SDK2 をビルドして `/usr/local` にインストール |
| `repos` | `ornebox.repos` のリポジトリを `~/ornebox_ws` に clone |
| `ypspur` | yp-spur を `/usr/local` にインストール (`ypspur-coordinator` を使うため) |
| `rosdep` | 各 `package.xml` の依存を apt で入れる |
| `build` | `~/ornebox_ws` を colcon build (apt 版 ROS 2) |
| `navvla` | NavVLA 用 venv `~/navvla_venv` (torch 2.6 + CLIP) |
| `env` | `env_navvla.sh` を `~/ornebox_ws` に配置 |
| `models` | CLIP ViT-B/32 を事前ダウンロード (現地はオフライン前提) |

`udev` のあとは一度ログアウトして入り直すこと (`dialout` の反映のため)。

## インストールされるもの

`setup.sh` が入れるものを、入る場所ごとにまとめる。どれも orne-box のどこかで使っている。

### 1. apt パッケージ (`apt` / `rosdep` ステップ)

システム全体に入る。確認は `dpkg -l <名前>`。

| パッケージ | 何に使うか |
|---|---|
| `ros-humble-desktop-full` | ROS 2 Humble 本体。rviz2・rosbag2・pcl_ros・cv_bridge など、よく使うものが一通り入る |
| `ros-humble-joy` | ジョイスティックの入力を `/joy` に流す。手動操作で使う (ros2-controller) |
| `ros-humble-v4l2-camera` | USB カメラの映像を `/image_raw` に流す (icart_driver の launch から起動) |
| `python3-colcon-common-extensions` | ワークスペースをビルドする `colcon` コマンド |
| `python3-rosdep` | `package.xml` に書かれた依存を apt で自動インストールする |
| `python3-vcstool` | `ornebox.repos` のリポジトリをまとめて clone する `vcs` コマンド |
| `python3-venv`, `python3-pip` | NavVLA 用の Python 仮想環境を作る |
| `git`, `build-essential`, `cmake`, `curl` | ソースからのビルドとダウンロード |
| `libpcl-dev`, `libeigen3-dev` | 点群処理ライブラリ (PCL) と行列ライブラリ (Eigen)。FAST-LIO のビルドに必要 |
| `libapr1-dev` | livox_ros_driver2 のビルドに必要 |
| `libreadline-dev` | yp-spur のビルドに必要 (対話コマンド `ypspur-interpreter` 用) |
| `pcl-tools` | 保存した地図 (`.pcd`) を見る `pcl_viewer` |
| `alsa-utils`, `pulseaudio-utils`, `libasound2-plugins` | NavVLA の音声案内の再生 (`aplay` / `paplay`) |
| `espeak-ng` | 音声合成。音声案内の音声ファイルを作り直すときに使う |

`rosdep` ステップは、各リポジトリの `package.xml` を読んで、上に含まれていない依存があれば追加で入れる。

### 2. ソースからビルドして `/usr/local` に入れるもの (`livox` / `ypspur` ステップ)

apt にないので、ソースからビルドしてシステムに入れる。

| ソフト | 何に使うか |
|---|---|
| [Livox-SDK2](https://github.com/Livox-SDK/Livox-SDK2) | LiDAR (Livox MID-360) と通信するライブラリ。livox_ros_driver2 がこれを使う |
| [yp-spur](https://github.com/openspur/yp-spur) | 車体 (T-frog モータドライバ) を制御するソフト。`ypspur-coordinator` が常駐し、icart_driver がそれ経由で車輪を動かす |

### 3. システム設定 (`udev` ステップ)

| 設定 | 何のためか |
|---|---|
| `/etc/udev/rules.d/99-icart-mini.rules` | 車体の USB シリアルを `/dev/sensors/icart-mini` という固定名にする。`/dev/ttyACM0` などの番号は挿し直すと変わるため |
| ユーザーを `dialout` グループに追加 | sudo なしでシリアルポートを開けるようにする |

### 4. ワークスペース `~/ornebox_ws` のリポジトリ (`repos` / `build` ステップ)

`ornebox.repos` に書いたものを clone して colcon build する。

icart_driver・livox_ros_driver2・ros2-controller・yp-spur は、orne-box 用の変更 (カメラ、MID-360 の IP、横断歩道の /cross など) を入れた [Kasaiatsuki の fork](https://github.com/Kasaiatsuki?tab=repositories) を使う。

| リポジトリ | 役割 |
|---|---|
| `icart_driver` | 車体のドライバ。yp-spur とカメラをまとめて起動する |
| `ros2-controller` | ジョイスティックで手動操作し、自律走行との切り替えを行う |
| `livox_ros_driver2` | LiDAR の点群と IMU を `/livox/lidar`, `/livox/imu` に流す |
| `FAST_LIO_ROS2` | LiDAR と IMU から自己位置 `/Odometry` を推定する |
| `yp-spur` | 上の yp-spur のソース (`/usr/local` へのインストール元) |
| `NavVLA` | OmniVLA ベースの走行モデル (`navvla`) と、場所認識の `pfoe` |

### 5. NavVLA 用の Python 仮想環境 `~/navvla_venv` (`navvla` ステップ)

apt 版 ROS 2 と同じ Python 3.10 で動かす。システムの Python を汚さないよう venv に分けている。中身は `requirements-navvla.txt`。

| パッケージ | 何に使うか |
|---|---|
| `torch`, `torchvision` (2.6 / CUDA 12.4 版) | 走行モデルの推論 (GPU) |
| `clip` (OpenAI CLIP) | 画像と言語の特徴抽出。走行の指示 (プロンプト) を扱う |
| `efficientnet_pytorch` | OmniVLA-edge モデルの画像エンコーダ |
| `ftfy`, `regex` | CLIP の依存 |

numpy・PyYAML・scipy は venv に入れず、apt 版をそのまま使う (`--system-site-packages`)。

### 6. 事前にダウンロードするモデル (`models` ステップ)

現地ではネットにつながらないことがあるので、公開されている重みを先に取っておく。

| モデル | 保存先 | 使う所 |
|---|---|---|
| CLIP ViT-B/32 | `~/.cache/clip/` | NavVLA |

自分たちで学習した重みは含まれない (下の「重みの配置」を参照)。

## 構成

ROS 2 は apt 版の Humble (`/opt/ros/humble`, Python 3.10) を使う。新しいターミナルを開いたら、まず次を実行する。

```bash
source ~/ornebox_ws/env_navvla.sh
```

これで ROS 2 とワークスペースが読み込まれ、NavVLA 用 venv の torch / CLIP も import できるようになる (`PYTHONPATH` に venv を足している)。

```
~/ornebox_ws/
├── src/  FAST_LIO_ROS2, livox_ros_driver2, icart_driver, ros2-controller, yp-spur
├── NavVLA/            # src/ の外。env_navvla.sh の PYTHONPATH がこの位置を前提にしている
└── env_navvla.sh
~/navvla_venv/
```

## 重みの配置

学習済みの重みは git に入っていないので、手で置く。

| ファイル | 置き場所 |
|---|---|
| `omnivla-edge_fisheye_tsudanuma_v2_e22.pth` | `~/ornebox_ws/NavVLA/deployment/weights/` |
| `placenet.pt` | `~/ornebox_ws/NavVLA/deployment/weights/` |

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
