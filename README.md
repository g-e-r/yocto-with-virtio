# Yocto with VirtIO Demo

このリポジトリは、Yocto Projectを使用してQEMU x86-64向けのカスタムLinuxイメージを構築し、**vhost-user** 技術を利用してゲストOSからアクセス可能なI2CおよびGPIOデバイスをシミュレーションするためのデモプロジェクトです。

実際のハードウェアを用意することなく、VirtIOを通じてLinuxカーネルドライバとアプリケーション（Python）の動作確認を行うことができます。

## リポジトリ構成ファイル

このGitリポジトリの主なファイル構造は以下の通りです。

```text
.
├── run.sh                                      # ビルドおよび実行用メインスクリプト
├── build/
│   └── conf/
│       ├── bblayers.conf                       # レイヤー定義ファイル
│       └── local.conf                          # ビルド設定ファイル
├── meta-virtio-py/                             # カスタムYoctoレイヤー
│   └── recipes-python/
│       └── python-app/
│           └── files/
│               └── app.py                      # ハードウェア検証用Pythonアプリケーション
└── vhost-stubs/                                # vhost-userバックエンド（Rust実装）
    └── target/release/                         # ビルド済みバイナリ配置先（run.shが参照）
```

## 開発者向けガイド: Yoctoビルド構造について

*   **Poky**: Yoctoのコアビルドシステムです。このリポジトリには含まれていないため、詳細は　https://docs.yoctoproject.org/bitbake/bitbake-user-manual/ を確認してください。
*   **Build Directory (`build/`)**: `run.sh build` を実行すると中身が自動的に生成されます。コンパイルされたバイナリや最終的なディスクイメージがここに格納されます。`build/conf/` 内の設定ファイル（`bblayers.conf`, `local.conf`）以外はGit管理外のディレクトリです。
*   **BitBake**: ビルドを実行するタスクランナーです。`run.sh build` は内部でBitBake環境をセットアップしてからイメージをビルドします。
*   **Recipes**: `meta-virtio-py` 内にあるレシピファイル（.bb）は、新しいソフトウェア（ここでは `app.py`）をシステムに追加する方法を定義しています。

## 必要要件

*   Linux ホスト環境 (Ubuntu等)
*   **Poky**: Yocto Project リファレンスディストリビューション
*   **QEMU**: `qemu-system-x86_64`

## 使用方法

ルートディレクトリにある `run.sh` スクリプトを使用して操作します。

### 1. イメージのビルド

Yoctoビルドを実行します。

```bash
./run.sh build
```

このコマンドは以下の処理を行います：
*   ビルド環境の初期化
*   `bitbake virtio-image` の実行

### 2. QEMUでの実行

```bash
./run.sh run
```

ビルドされたイメージをQEMUで起動し、同時にvhost-userデーモン（I2C/GPIOシミュレータ）をバックグラウンドで立ち上げます。
アプリケーションはinit.dによりシステム起動時に自動で開始します。
起動と終了は/etc/init.d/python-appを使います。
