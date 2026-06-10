# openEMS devcontainer

VS Code の Dev Containers で openEMS をビルド・実行するための作業用リポジトリです。

## 使い方

1. VS Code でこのフォルダを開きます。

   ```bash
   code /home/nero/workspace/openEMS
   ```

2. VS Code のコマンドパレットから `Dev Containers: Reopen in Container` を実行します。
3. 初回起動時に `.devcontainer/post-create.sh` が `openEMS-Project` をビルドし、成果物を `.openems-local` にインストールします。

## devcontainer に入るもの

- Ubuntu 24.04
- C/C++ ビルド環境: `build-essential`, `cmake`, `git`
- openEMS 依存関係: Boost, CGAL, FFTW, HDF5, TinyXML, VTK, Qt5
- Octave 環境: `octave`, `octave-dev`
- Python venv: `/opt/venv`
- Python パッケージ: `numpy`, `h5py`, `matplotlib`, `scipy`, `sympy`, `Cython` など

## インストール先

devcontainer 内では openEMS は次に入ります。

```bash
/workspaces/openEMS/.openems-local
```

`PATH`, `LD_LIBRARY_PATH`, `OPENEMS_HOME`, `VIRTUAL_ENV` は devcontainer 側で設定済みです。

確認例:

```bash
openEMS --help
python -c "import CSXCAD, openEMS; print(CSXCAD.__file__); print(openEMS.__file__)"
```

## 再ビルド

通常はインストール済みならスキップします。強制的にビルドし直す場合:

```bash
OPENEMS_REBUILD=1 .devcontainer/post-create.sh
```

GUI が不要な場合は AppCSXCAD を外せます。

```bash
OPENEMS_BUILD_GUI=NO OPENEMS_REBUILD=1 .devcontainer/post-create.sh
```

並列数を落としたい場合:

```bash
OPENEMS_BUILD_JOBS=2 OPENEMS_REBUILD=1 .devcontainer/post-create.sh
```

## Docker なしで動かす場合

Linux または WSL 上なら Docker なしでも動かせます。ただし、ホスト側に同じ依存関係を直接入れてビルドする必要があります。

Ubuntu 24.04 の例:

```bash
sudo apt-get update
sudo apt-get install build-essential cmake git libhdf5-dev libvtk9-dev \
  libboost-all-dev libcgal-dev libtinyxml-dev qtbase5-dev libvtk9-qt-dev \
  octave octave-dev python3-dev python3-pip python3-venv

cd openEMS-Project
./update_openEMS.sh ../.openems-local --python
```

この方式でも openEMS 本体は動きますが、ホスト環境のパッケージ差分や Python 環境の衝突を受けやすいため、VS Code 開発では devcontainer の方が再現性は高いです。
