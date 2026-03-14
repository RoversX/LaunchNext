# LaunchNext

**言語**: [English](../README.md) | [中文](README.zh.md) | [日本語](README.ja.md) | [한국어](README.ko.md) | [Français](README.fr.md) | [Español](README.es.md) | [Deutsch](README.de.md) | [Русский](README.ru.md) | [हिन्दी](README.hi.md) | [Tiếng Việt](README.vi.md) | [Italiano](README.it.md) | [Čeština](README.cs.md)

## 📥 ダウンロード

**[こちらからダウンロード](https://github.com/RoversX/LaunchNext/releases/latest)** - 最新版を入手

🌐 **公式サイト**: [closex.org/launchnext](https://closex.org/launchnext/)  
📚 **ドキュメント**: [docs.closex.org/launchnext](https://docs.closex.org/launchnext/)

⭐ [LaunchNext](https://github.com/RoversX/LaunchNext) と元プロジェクト [LaunchNow](https://github.com/ggkevinnnn/LaunchNow) へのスターをお願いします！

| | |
|:---:|:---:|
| ![](../public/banner.webp) | ![](../public/setting1.webp) |
| ![](../public/setting2.webp) | ![](../public/setting3.webp) |

macOS Tahoe は Launchpad を削除しましたが、新しいインターフェースは使いにくく、Bio GPU を十分に活用できません。Apple よ、せめて元に戻すオプションを提供してください。それまでは、LaunchNext があります。

*[LaunchNow](https://github.com/ggkevinnnn/LaunchNow)（ggkevinnnn）をベースに開発しました。原プロジェクトに心から感謝します！❤️*

*LaunchNow は GPL 3 ライセンスを選択しており、LaunchNext も同じライセンス条件に従います。*

⚠️ **macOS がアプリをブロックする場合、ターミナルで実行してください：**
```bash
sudo xattr -r -d com.apple.quarantine /Applications/LaunchNext.app
```
**理由**：私は Apple の開発者証明書（年間 $99）を購入する余裕がないため、macOS は未署名アプリをブロックします。このコマンドは隔離フラグを削除してアプリを実行可能にします。**信頼できるアプリにのみ使用してください。**

## LaunchNext が提供するもの

- ✅ **旧システム Launchpad からのワンクリックインポート** - ネイティブ Launchpad SQLite データベースを直接読み取り、フォルダ、アプリ位置、レイアウトを復元
- ✅ **手動でのアプリ整理** - アプリ移動、フォルダ作成、好みのレイアウト維持が可能
- ✅ **2 つの描画パス** - 互換性重視の `Legacy Engine` と、最良の体験を提供する `Next Engine + Core Animation`
- ✅ **コンパクト / フルスクリーン** - それぞれ別設定を保持可能
- ✅ **キーボード中心の操作** - 高速検索、ナビゲーション、起動
- ✅ **CLI / TUI 自動化サポート** - ターミナルからレイアウト確認と管理が可能
- ✅ **Hot Corner とネイティブジェスチャー起動** - 複数のグローバル起動方法
- ✅ **アプリを Dock に直接ドラッグ** - Core Animation エンジンで利用可能
- ✅ **Markdown リリースノート対応の更新センター** - より充実したアプリ内更新体験
- ✅ **バックアップ / 復元ツール** - より安全なエクスポートと復元フロー
- ✅ **アクセシビリティとコントローラ対応** - 音声フィードバックとコントローラ操作を強化
- ✅ **多言語対応** - 幅広いローカライズを提供

## macOS Tahoe が失わせたもの

- ❌ カスタムアプリ整理なし
- ❌ ユーザー作成フォルダなし
- ❌ ドラッグ＆ドロップカスタマイズなし
- ❌ 視覚的なアプリ管理なし
- ❌ 強制的なカテゴリ分類

## データ保存

アプリデータは以下に保存されます：

```text
~/Library/Application Support/LaunchNext/Data.store
```

## ネイティブ Launchpad 統合

LaunchNext はシステム Launchpad データベースを直接読み取れます：

```bash
/private$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db/db
```

## インストール

### 必要条件

- macOS 26（Tahoe）以降
- Apple Silicon または Intel プロセッサ
- Xcode 26（ソースからビルドする場合）

### ソースからビルド

1. **リポジトリをクローン**
   ```bash
   git clone https://github.com/RoversX/LaunchNext.git
   cd LaunchNext
   ```

2. **Xcode で開く**
   ```bash
   open LaunchNext.xcodeproj
   ```

3. **ビルドして実行**
   - 対象デバイスを選択
   - `⌘+R` でビルドして実行
   - `⌘+B` でビルドのみ

### コマンドラインビルド

**通常ビルド：**
```bash
xcodebuild -project LaunchNext.xcodeproj -scheme LaunchNext -configuration Release
```

**ユニバーサルバイナリ（Intel + Apple Silicon）：**
```bash
xcodebuild -project LaunchNext.xcodeproj -scheme LaunchNext -configuration Release ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO clean build
```

## 使い方

### はじめに

1. LaunchNext は初回起動時にインストール済みアプリをスキャンします
2. 旧 Launchpad レイアウトを取り込むか、新規レイアウトから開始します
3. 検索、キーボード操作、マウスドラッグ、フォルダでアプリを整理します
4. 設定でエンジン、レイアウトモード、起動方法、自動化を構成します

### Launchpad をインポート

1. 設定を開く
2. **Import Launchpad** をクリック
3. 既存レイアウトとフォルダが自動で取り込まれます

### エンジンと表示モード

- **Legacy Engine** - 旧レンダリングパスを維持し、互換性を優先
- **Next Engine + Core Animation** - 推奨。全体的な体験と新機能対応がより良い
- **コンパクト / フルスクリーン** - 2 つのモードをサポートし、それぞれ別設定を保持可能

## 主な機能

### 起動と入力

- **Hot Corner 対応** - 設定可能な画面コーナーから LaunchNext を起動
- **実験的ネイティブジェスチャー対応** - 4 本指 pinch / tap アクション
- **グローバルショートカット対応** - どこからでも LaunchNext を開ける
- **Dock へのドラッグ** - Core Animation エンジンで macOS Dock に直接アプリを渡せる

### 自動化とパワーユーザー向けワークフロー

- **CLI / TUI 対応** - レイアウト確認、アプリ検索、フォルダ作成、アプリ移動、自動化が可能
- **agent 向けワークフロー** - ターミナル型 AI agent や shell 自動化と相性が良い
- **設定からコマンドラインを有効化** - 管理対象 `launchnext` コマンドの追加 / 削除が可能

### 更新体験

- **アプリ内更新センター** - アプリを離れずに更新確認
- **Markdown リリースノート** - 設定内でより豊かなリリースノート表示
- **モダン通知 API** - 新しい macOS 通知方式に対応

### バックアップと復元

- 設定からバックアップ作成と復元が可能
- より信頼性の高いバックアップ書き出し
- 一時ファイルとクリーンアップ経路の安全性を改善

### アクセシビリティとナビゲーション

- **音声フィードバック対応** - ナビゲーション時にアプリやフォルダ名を読み上げ
- **コントローラ対応** - ゲームコントローラで LaunchNext とフォルダを操作
- **キーボード中心の操作** - マウスなしでも高速検索と移動が可能

## パフォーマンスと安定性

- アイコンキャッシュによる滑らかなブラウズ
- 遅延読み込みとバックグラウンドスキャンで大規模ライブラリにも対応
- 設定やナビゲーションの状態同期を改善
- 更新処理、バックアップ書き出し、ジェスチャー復帰の信頼性向上

## トラブルシューティング

### よくある質問

**Q: アプリが起動しない？**  
A: macOS 26 以降であることを確認し、必要なら quarantine を外し、信頼できるビルドを使用してください。

**Q: どのエンジンを使うべき？**  
A: `Next Engine + Core Animation` を推奨します。旧互換パスが必要な場合のみ `Legacy Engine` を使ってください。

**Q: CLI コマンドがまだ使えないのはなぜ？**  
A: まず設定でコマンドラインインターフェースを有効にしてください。LaunchNext は管理対象の `launchnext` shim を追加 / 削除できます。

## コントリビューション

コントリビューション歓迎です。

1. リポジトリを Fork
2. 機能ブランチを作成（`git checkout -b feature/amazing-feature`）
3. 変更をコミット（`git commit -m 'Add amazing feature'`）
4. ブランチを Push（`git push origin feature/amazing-feature`）
5. Pull Request を作成

### 開発ガイドライン

- Swift のスタイル規約に従う
- 複雑なロジックには意味のあるコメントを追加する
- 可能な限り複数の macOS バージョンでテストする
- 実験的機能を無関係なファイルへ散らさない
- 取り外し可能な統合はなるべく分離する

## アプリ管理の未来

Apple がカスタマイズ可能なランチャーから離れていく中で、LaunchNext は現代 macOS 上でも手動整理、ユーザー制御、高速なアプリアクセスを維持しようとしています。

**LaunchNext** は単なる Launchpad の代替ではなく、ワークフローの後退に対する現実的な回答です。

---

**LaunchNext** - アプリランチャーの主導権を取り戻す 🚀

*カスタマイズを妥協したくない macOS ユーザーのために。*

## 開発ツール

- Claude Code
- Cursor
- OpenAI Codex CLI
- Perplexity
- Google

- 実験的ジェスチャー機能は [OpenMultitouchSupport](https://github.com/Kyome22/OpenMultitouchSupport) と [KrishKrosh](https://github.com/KrishKrosh/OpenMultitouchSupport) の fork をベースにしています。❤️

![GitHub downloads](https://img.shields.io/github/downloads/RoversX/LaunchNext/total)
