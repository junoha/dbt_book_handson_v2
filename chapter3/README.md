# 第 3 章 ハンズオン

## 前提

uv・AWS CLI のインストール、`dbt-book` プロファイルの作成、環境変数 `AWS_PROFILE` の設定は、[ハンズオン共通のセットアップ](../README.md#共通の前提条件)にまとめています。まだの場合は先に済ませてください。
以降のコマンドは `AWS_PROFILE=dbt-book` を設定した状態で実行します（未設定なら共通のセットアップを参照）。

後半では Git を利用するため、`git` を実行できることを確認してください。
Git のインストールは https://git-scm.com/install を参照してください。

また、後半では新しい GitHub リポジトリを作成します。
本書リポジトリの中で直接 `git init` するとリポジトリが入れ子になり混乱するため、本ディレクトリ（`chapter3/`）を、本書リポジトリの外にある作業用ディレクトリ（例: ホーム直下の `dbt_handson3`）にコピーしてから進めてください。

以下のコマンドでコピーします。`<本書リポジトリのパス>` は、クローンした本書リポジトリ（`dbt_book`）のパスに置換してください。

```sh
# macOS / Linux の例
cp -R <本書リポジトリのパス>/chapter3 ~/dbt_handson3
```

```powershell
# Windows (PowerShell) の例
Copy-Item -Recurse <本書リポジトリのパス>\chapter3 $HOME\dbt_handson3
```

以降では、コピーした作業用ディレクトリ（`dbt_handson3`）の直下でコマンドを実行します。

```sh
# macOS / Linux
cd ~/dbt_handson3
```

```powershell
# Windows (PowerShell)
cd $HOME\dbt_handson3
```

コピーが正しく行われたか、隠しファイルを含めて確認します。`.github`・`.gitignore`・`.python-version` が表示されることを確認してください。

```sh
# macOS / Linux
ls -a
```

```powershell
# Windows (PowerShell)
Get-ChildItem -Force
```

## ハンズオンのセットアップ

### 1. Python 仮想環境の構築

仮想環境を作成し、有効化（activate）します。以降のコマンドは、この仮想環境が有効な状態で実行します。

```sh
# macOS / Linux
uv sync --frozen
source .venv/bin/activate
```

```powershell
# Windows (PowerShell)
uv sync --frozen
.venv\Scripts\activate
```

### 2. ソースデータの生成

```bash
jafgen
```

`jafgen` は実行したディレクトリの直下に `jaffle-data/` を作成し、その中に CSV を出力します。

### 3. AWS リソースの作成とデータのロード

以下のスクリプトを実行すると、次の処理がまとめて行われます。

1. CloudFormation スタック `dbt-book-ch3-athena` により S3 バケットと Athena ワークグループを作成
2. ステップ 2 で生成した CSV を S3 にアップロードし、Athena（Glue）のテーブルを作成
3. 作成した S3 バケット名を `.env` に書き出し、環境変数 `S3_BUCKET_ATHENA` の設定方法を表示

```bash
uv run python utils/setup.py
```

### 環境変数 `S3_BUCKET_ATHENA` の設定

dbt の `profiles.yml` は、Athena 用の S3 バケット名を環境変数 `S3_BUCKET_ATHENA` から読み取ります。
セットアップスクリプトは、この値を作業用ディレクトリ直下の `.env` ファイルに書き出し、最後に環境変数として設定するためのコマンドを表示します。
表示されたコマンドを実行して、`S3_BUCKET_ATHENA` を設定してください（実際の値はスクリプトの出力に従ってください）。

```sh
# macOS / Linux (bash / zsh) の例
export S3_BUCKET_ATHENA=dbt-book-ch3-athena-XXXXXXXXXXXX-ap-northeast-1
```

```powershell
# Windows (PowerShell) の例
$env:S3_BUCKET_ATHENA = "dbt-book-ch3-athena-XXXXXXXXXXXX-ap-northeast-1"
```

> [!NOTE]
> 環境変数はターミナルのセッションごとに設定が必要です。ターミナルを開き直した場合は、仮想環境の再有効化（`source .venv/bin/activate` など）とあわせて、この環境変数も再度設定してください。値は `.env` ファイルにも保存されているので、そこから確認できます。

### データの確認

確認のため、Athena クエリエディタを開いてクエリを実行します。顧客の ID と氏名を取得できます。

1. 画面左上の検索窓に `athena` と入力し、サービス欄にある「Athena」をクリックしてください。
2. 画面左上のハンバーガーメニューを開き、「クエリエディタ」をクリックしてください。
3. 画面右上の「ワークグループ」で `dbt-book-ch3-athena-workgroup` を選択してください。
4. クエリエディタ左側の「データ」の各欄でデータソース `AwsDataCatalog` とデータベース `jaffle_shop_ch3_raw` を選択してください。
5. 以下のクエリを実行します。

```sql
SELECT * FROM jaffle_shop_ch3_raw.raw_customers LIMIT 10
```

### dbt-athena を利用するプロジェクトのデプロイ

dbt コマンドで Athena に接続できることを確認します。

```sh
# dbt プロジェクトのディレクトリに移動
cd dbt_project

# 接続確認
dbt debug
```

dbt モデルをデプロイします。

```sh
dbt run
```

デプロイが成功したことを確認するため、Athena クエリエディタで以下のクエリを実行します。

```sql
SELECT * FROM jaffle_shop_ch3_dev.customers LIMIT 10
```

## dbt test によるテスト実行

### データテスト: データの品質を確認

martsモデル `customers` のデータテストを実行します。

```sh
dbt test --select customers
```

#### 集計ロジックの検証

ユニットテストを実行します。

```sh
dbt test --select "test_type:unit"
```

## GitHub Actions による CI/CD パイプラインの構築

### 準備と構成確認

#### GitHub アカウントの用意

GitHub Actions を利用するために、GitHub リポジトリが必要です。
リポジトリ作成には GitHub アカウントが必要となるため、アカウントを持っていない方は、[GitHub](https://github.com/) でアカウントを作成してください。
GitHub には有料のプランやオプションがありますが、本章のハンズオンを進めるにあたっては無料の Free プランで十分です。

#### GitHub CLI のインストールと接続

GitHub CLI をインストールします。
OS に応じたインストール手順は[公式ページ](https://github.com/cli/cli#installation)を参照してください。
macOS は Homebrew、Windows は WinGet を利用できます。

インストールが完了したら、GitHub CLI で GitHub アカウントに接続します。

```sh
gh auth login -h github.com -p https -w
```

以下のような出力を確認できたら、Enter キーを押してください。ブラウザが開き、認証画面が表示されます。

```
! First copy your one-time code: XXXX-XXXX
Press Enter to open https://github.com/login/device in your browser...
```

ブラウザで one-time code を入力し、"Authorize github" をクリックすると、ログインが完了し `Logged in as <ユーザー名>` などのメッセージが出力されます。

> [!NOTE]
> ブラウザが自動的に開かない場合は、表示された URL（https://github.com/login/device）に手動でアクセスして one-time code を入力してください。

#### GitHub リポジトリの準備

ハンズオンで使うファイルを GitHub プライベートリポジトリにアップロードします。
まず、作業用ディレクトリを Git リポジトリとして初期化し、ファイルのステージングとコミットを実行します。
`<メールアドレス>` と `<名前>` の部分は GitHub アカウントで登録したメールアドレスや名前に置換してください。

```sh
# dbt_project にいる場合は、作業用ディレクトリ dbt_handson3 の直下に戻る
cd ..

# GitHub リポジトリ初期化
git config --global init.defaultBranch main
git init
git config user.email "<メールアドレス>"
git config user.name "<名前>"
git add .
git commit -m "最初のコミット"
```

次に、GitHub CLI コマンド `gh` でプライベートリポジトリを作成し、ブランチ `main` をプッシュしてください。
なお、以下の例では `dbt_handson3` という名前を設定していますが、適宜変更してかまいません。

```sh
gh repo create dbt_handson3 --private --source . --remote origin
git push -u origin main
```

リポジトリが作成され、ブランチ `main` がプッシュされたことを確認してください。

```sh
gh repo view dbt_handson3
```

#### CloudFormation による IAM ロールなどの作成

以下のスクリプトを実行すると、CloudFormation スタック `dbt-book-ch3-cicd` をデプロイし、CI/CD パイプラインで必要な IAM ロールや Amplify アプリなどを作成します。
作成された IAM ロール ARN（`AWS_ROLE_ARN`）と Amplify アプリ ID（`AMPLIFY_APP_ID`）は `.env` に追記されます。

`<GitHub アカウント名>` は、アカウント名に置換してください（不明な場合は `gh auth status` で確認できます）。
`--repo` は `gh repo create` で指定したリポジトリ名です。手順通りなら省略してかまいません（既定値 `dbt_handson3`）。

```bash
uv run python utils/setup_cicd.py --github-account <GitHub アカウント名>
```

> [!NOTE]
> アカウントに既に GitHub OIDC プロバイダーが存在する場合は、`--no-create-oidc-provider` を付けて実行してください（重複作成エラーを回避できます）。

スクリプトの実行が完了すると、IAM ロール ARN・Amplify アプリケーション ID・ドキュメント URL が表示されます。

> [!TIP]
> AWS Lake Formation を有効にしているアカウントでは、パイプライン実行時に Lake Formation の権限不足でエラーとなる場合があります。同ロールに Lake Formation 側でデータベース作成等の権限を別途付与してください。

#### GitHub シークレットの設定

`.env` に保存された値（`S3_BUCKET_ATHENA`・`AWS_ROLE_ARN`・`AMPLIFY_APP_ID`）を、GitHub シークレットとして一括登録します。

```bash
gh secret set --env-file .env
```

### プルリクエストによる CI パイプラインの実行

#### シナリオ 1: テスト追加でワークフローが成功する

ブランチを作成します。

```sh
git switch -c feature/add-customers-spend-consistency-test
```

続いて、エディタで `dbt_project/tests/assert_customers_lifetime_spend_consistent.sql` を新規作成し、以下の内容を保存してください。

```sql
select
    customer_id,
    lifetime_spend,
    lifetime_spend_pretax,
    lifetime_tax_paid

from {{ ref('customers') }}

where lifetime_spend <> lifetime_spend_pretax + lifetime_tax_paid
```

コミット・プッシュ後、プルリクエストを作成します。

```sh
git add dbt_project/tests/assert_customers_lifetime_spend_consistent.sql
git commit -m "customers の lifetime_spend 整合性テストを追加"

git push origin feature/add-customers-spend-consistency-test
gh pr create --title "customers の lifetime_spend 整合性テストを追加" --body "顧客単位の集計後も lifetime_spend = lifetime_spend_pretax + lifetime_tax_paid が維持されていることを検証するシンギュラーデータテストを追加します。"
```

ワークフロー実行を確認します。CI が成功することを確認してください。

```sh
gh run list
gh run watch "<ワークフロー実行の ID>"
```

#### シナリオ 2: モデル変更でワークフローが失敗する

シナリオ 1 と 2 の CI ワークフローはブランチが異なるため並列に実行可能ですが、`jaffle_shop_ch3_ci` データベース上のテーブルを互いに上書きしレースする可能性があります。
シナリオ 1 の `gh run watch` が完了したことを確認してから、シナリオ 2 を進めてください。

ブランチ `main` から新しいブランチを切ります。

```sh
git switch main
git switch -c experiment/break-is-food-order
```

続いて、エディタで `dbt_project/models/marts/orders.sql` を開き、`is_food_order` を定義している以下の行を探してください。

```sql
order_items_summary.count_food_items > 0 as is_food_order
```

この行を、次のように `false` を返すよう書き換えて保存します。

```sql
false as is_food_order
```

変更内容を確認します。

```sh
git diff dbt_project/models/marts/orders.sql
```

コミット・プッシュ後、プルリクエストを作成します。

```sh
git add dbt_project/models/marts/orders.sql
git commit -m "orders の is_food_order を一時的に false に変更"

git push origin experiment/break-is-food-order
gh pr create --title "[CI 動作確認] is_food_order を破壊" --body "CI ワークフローが意図したエラーを検出することを確認するためのプルリクエストです。マージはしません。"
```

ワークフロー実行を確認します。`dbt build` でユニットテストが失敗し、CI ワークフロー全体が失敗することを確認してください。

```sh
gh run list
gh run watch "<ワークフロー実行の ID>"
```

確認が完了したら、ローカルのブランチを `main` に戻します。

```sh
git switch main
```

### デプロイ用パイプラインの実行

#### ドキュメントをデプロイするための準備

ドキュメントのデプロイ先となる Amplify アプリケーション ID（`AMPLIFY_APP_ID`）は、前段の「[GitHub シークレットの設定](#github-シークレットの設定)」で実行した `gh secret set --env-file .env` により `.env` から一括登録済みです。
ここで改めて設定する必要はありません。

デプロイされるドキュメントの URL は、`setup_cicd.py` の出力で確認できます。
改めて確認したい場合は、以下のコマンドで取得できます。

```sh
aws cloudformation describe-stacks --stack-name dbt-book-ch3-cicd --query "Stacks[0].Outputs[?OutputKey=='AmplifyURL'].OutputValue" --output text --region ap-northeast-1
```

#### （任意）ドキュメントへのアクセス制限

デプロイされる dbt ドキュメントはデフォルトでパブリックアクセス可能ですが、以下の手順で Basic 認証を有効にしてアクセスを制限することもできます。

まず、`<ユーザー名>` と `<パスワード>` を任意の値に置換して、認証情報を Base64 エンコードします。

```sh
uv run python -c "import base64; print(base64.b64encode(b'<ユーザー名>:<パスワード>').decode())"
```

出力された文字列を `<Base64 文字列>` に、`.env` の `AMPLIFY_APP_ID` の値を `<AMPLIFY_APP_ID>` に置換して、以下のコマンドを実行します。

```sh
aws amplify update-branch --app-id <AMPLIFY_APP_ID> --branch-name main --enable-basic-auth --basic-auth-credentials "<Base64 文字列>" --region ap-northeast-1
```

#### 本番環境用ワークフローの実行

本番環境用のワークフローを実行します。

```sh
gh workflow run deploy_prod.yml
```

デプロイを確認するため、Athena クエリエディタで以下のコマンドを実行します。

```sql
SELECT * FROM jaffle_shop_ch3.customers LIMIT 10
```

### ハンズオンのクリーンアップ

ハンズオンで作成した AWS リソースを削除します。

```sh
uv run python utils/delete_resources.py
```

スクリプトを実行すると削除対象のリソース一覧が表示され、確認プロンプトで `y` を入力すると一括で削除されます（デフォルトはキャンセル）。
削除対象は以下の通りです。

- CloudFormation スタック `dbt-book-ch3-cicd`・`dbt-book-ch3-athena`（スタック内で作成された IAM ロール、Amplify アプリ、Athena ワークグループ、S3 バケットなどを含む）
- Glue データベース `jaffle_shop_ch3_raw`・`jaffle_shop_ch3_dev`・`jaffle_shop_ch3_ci`・`jaffle_shop_ch3`（dbt プロジェクトおよび `load_raw_data.py` により作成されたもの）

なお、このスクリプトでは GitHub リポジトリや GitHub シークレットは削除されませんので、不要であれば GitHub Web UI などで別途削除してください。
