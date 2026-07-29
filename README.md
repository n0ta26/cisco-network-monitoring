# cisco-network-monitoring

自宅ラボの Cisco ルータを対象に、SNMP で情報収集できる監視基盤
（`snmp-exporter` / `Node Exporter` / `Prometheus` / `Alertmanager` /
`Grafana`）を Ansible でプロビジョニングするためのリポジトリです。

## 前提

- Nix がインストール済みであること
- Cisco ルータ側の SNMP 設定が完了していること（本リポジトリではルータ設定自体は行いません）
- デプロイ先サーバに SSH 接続できること
- デプロイ先サーバは Debian 系 OS であること

## セットアップ

```bash
nix develop
```

`flake.nix` から次のツールが利用できます。

- `ansible`
- `ansible-lint`
- `snmpwalk`

初回と依存更新後は、固定された Ansible Collection をインストールします。

```bash
ansible-galaxy collection install --force -r ansible/requirements.yml
```

### Ansible ツールチェーンのバージョン

同じ commit を同じ依存関係で検証できるよう、主要ツールを完全固定しています。

| 対象 | バージョン | 固定箇所 |
| --- | --- | --- |
| Ansible Core | 2.20.5 | `flake.nix` と `ansible/requirements.txt` |
| ansible-lint | 25.8.2 | `flake.nix` と `ansible/requirements.txt` |
| community.docker | 5.1.0 | `ansible/requirements.yml` |

依存を更新するときは、Nix package set と Python package の互換性を確認してから
`flake.nix` の version assertion、`ansible/requirements.txt`、
`ansible/requirements.yml` を同じ変更で更新します。Nix package set を更新する場合は
`nix flake update` で `flake.lock` も更新し、Collection を再インストールします。
更新後は CI と同じ lint、全 playbook の syntax check、設定検証を実行し、成功を確認して
からコミットしてください。

## 事前設定

1. 監視サーバ接続先を設定する  
   `ansible/inventory.yml` の `ansible_host` / `ansible_user` / `ansible_ssh_private_key_file` を環境に合わせて変更します。
2. Ansible Vault のパスワードを設定する
   [Ansible Vaultによる機密情報管理](#ansible-vaultによる機密情報管理)を参照し、
   リポジトリルートに `secret` を作成します。
3. SNMP 監視対象を設定する
   `monitoring_stack_targets` を Ansible の group vars で定義します。
   詳細は[監視対象の管理](#監視対象の管理)を参照してください。
4. SNMPv3 認証情報を Ansible Vault に設定する
   [SNMPv3 認証情報](#snmpv3-認証情報)の手順で暗号化した変数を作成します。
   監視対象の `auth_profile` には、Vault 内で定義した auth 名を指定します。
5. アラートの通知先や閾値を設定する
   [アラート通知](#アラート通知)を参照し、必要な Ansible 変数を上書きします。

## Ansible Vaultによる機密情報管理

Webhook URL などの機密情報を含む
`ansible/group_vars/monitoring_servers.yml` は、Ansible Vault でファイル全体を暗号化して
リポジトリに保存します。Vault パスワード自体は、リポジトリルートの `secret` に1行で
記載します。

```bash
touch secret
chmod 600 secret
${EDITOR:-vi} secret
```

`secret` は `.gitignore` の `/secret` でGit管理から除外されています。作成後に次のコマンドで
除外状態を確認できます。

```bash
git check-ignore secret
```

暗号化済みの変数ファイルは通常のエディタで直接編集せず、次のコマンドで復号・再暗号化
しながら編集します。

```bash
nix develop --command ansible-vault edit \
  --vault-password-file secret \
  ansible/group_vars/monitoring_servers.yml
```

新しい平文の変数ファイルを暗号化する場合は、次のコマンドを使用します。

```bash
nix develop --command ansible-vault encrypt \
  --vault-password-file secret \
  ansible/group_vars/monitoring_servers.yml
```

Vault パスワードを変更する場合は、古いパスワードファイルを別途用意したうえで
`ansible-vault rekey` を使用します。`secret` の内容や復号した変数ファイルはコミット
しないでください。

## 監視対象の管理

監視対象は `monitoring_stack_targets` のリストで管理します。例えば
`ansible/group_vars/monitoring_servers.yml` に次のように定義します。
このファイルは暗号化されているため、前節の `ansible-vault edit` で編集してください。

```yaml
monitoring_stack_targets:
  - name: edge-router
    address: 172.16.2.1
    role: edge-router
    auth_profile: cisco_v3
    modules:
      - if_mib
      - cisco_device
    labels:
      site: home
      floor: first

  - name: access-switch
    address: 172.16.2.2
    role: access-switch
    auth_profile: cisco_v3
    modules:
      - if_mib
    labels:
      site: home
      floor: second
```

各対象の項目は次のとおりです。

| 項目 | 必須 | 用途 |
| --- | --- | --- |
| `name` | 必須 | Prometheus の `device` ラベル。リスト内で一意にする |
| `address` | 必須 | SNMP Exporter が接続する IP アドレスまたはホスト名 |
| `role` | 必須 | 機器の用途を表す `role` ラベル |
| `auth_profile` | 必須 | Vault の `vault_monitoring_stack_snmp_auths` に定義した認証プロファイル名 |
| `modules` | 必須 | 使用する SNMP モジュールのリスト。標準は `if_mib` と `cisco_device` |
| `labels` | 任意 | `site` などの追加 Prometheus ラベル。不要な場合は `{}` または省略可能 |

ロールのデフォルト値には従来と同じ `172.16.2.1` の1台構成が定義されているため、
`monitoring_stack_targets` を上書きしない既存環境もそのままデプロイできます。group vars で
定義する場合はリスト全体が置き換わるため、監視を継続する機器をすべて記載してください。

機器を追加する場合はリストへ項目を追加し、`auth_profile` と `modules` が
Vault の `vault_monitoring_stack_snmp_auths` および
`monitoring_stack_snmp_module_jobs` に存在することを確認します。機器を削除する場合は
対象の項目をリストから削除します。変更後は設定検証を実行してから再デプロイしてください。
Prometheus 設定は Ansible がリストから再生成するため、手作業で編集する必要はありません。

```bash
nix develop --command ./scripts/validate-monitoring-config.sh \
  --vault-password-file secret \
  -e @ansible/group_vars/monitoring_servers.yml

ansible-playbook \
  -i ansible/inventory.yml \
  ansible/playbooks/deploy-monitoring.yml \
  --vault-password-file secret
```

## SNMPv3 認証情報

追跡対象の SNMP Exporter 設定には認証情報を保存しません。デプロイ時に
`vault_monitoring_stack_snmp_auths` を `monitoring_stack_snmp_auths` として参照し、
`ansible/roles/monitoring_stack/templates/snmp.yml.j2` から配置用 `snmp.yml` を生成します。

初回は example をコピーして実値へ置き換え、直後に既存の Vault パスワードで暗号化します。
Webhook 用の `monitoring_servers.yml` と SNMP 用の `vault.yml` は同じ `secret` を使用します。

```bash
cp ansible/group_vars/monitoring_servers/vault.example.yml \
  ansible/group_vars/monitoring_servers/vault.yml
ansible-vault encrypt \
  --vault-password-file secret \
  ansible/group_vars/monitoring_servers/vault.yml
```

暗号化済みの `vault.yml` はコミットできます。Vault パスワードを保存する `secret` は
`.gitignore` で除外されています。以降の編集と内容確認は次のように行います。

```bash
ansible-vault edit \
  --vault-password-file secret \
  ansible/group_vars/monitoring_servers/vault.yml
ansible-vault view \
  --vault-password-file secret \
  ansible/group_vars/monitoring_servers/vault.yml
```

実環境変数を使った設定検証とデプロイでは、同じ Vault パスワードファイルを指定します。
検証スクリプトは SNMP 認証情報を画面へ出力しません。

```bash
nix develop --command ./scripts/validate-monitoring-config.sh \
  --vault-password-file secret \
  -e @ansible/group_vars/monitoring_servers/vault.yml

ansible-playbook \
  --vault-password-file secret \
  -i ansible/inventory.yml \
  ansible/playbooks/deploy-monitoring.yml
```

## デプロイ

```bash
ansible-playbook \
  -i ansible/inventory.yml \
  ansible/playbooks/deploy-monitoring.yml \
  --vault-password-file secret
```

デプロイ後、監視サーバの以下ポートで各コンポーネントにアクセスできます。

- Grafana: `http://<monitoring-host>:3000`
- Prometheus: `http://<monitoring-host>:9090`
- Alertmanager: `http://<monitoring-host>:9093`
- SNMP Exporter: `http://<monitoring-host>:9116`

Node Exporter は監視サーバの CPU、メモリ、および Prometheus データボリュームの容量を
収集するため、Compose の内部ネットワークだけで公開します。

## アラート通知

Prometheus のアラートを Alertmanager へ送り、任意の Webhook へ通知します。Webhook を
設定しない場合も、発生中のアラートは Prometheus と Alertmanager の Web UI で確認できます。

通知先は、例えば `ansible/group_vars/monitoring_servers.yml` で設定します。Webhook URL に
認証情報が含まれる場合は、平文でコミットせず Ansible Vault などで暗号化してください。

```yaml
monitoring_stack_alertmanager_webhook_url: "https://example.net/prometheus-alerts"
monitoring_stack_alertmanager_webhook_send_resolved: true
```

Alertmanager の通知間隔は次の変数で上書きできます。

| 変数 | デフォルト | 用途 |
| --- | --- | --- |
| `monitoring_stack_alertmanager_resolve_timeout` | `5m` | 更新されないアラートを解決済みとみなすまでの時間 |
| `monitoring_stack_alertmanager_group_wait` | `30s` | 同時発生したアラートを最初にまとめる待ち時間 |
| `monitoring_stack_alertmanager_group_interval` | `5m` | 同じグループの追加通知間隔 |
| `monitoring_stack_alertmanager_repeat_interval` | `4h` | 継続中アラートの再通知間隔 |

Prometheus は次のルールを評価します。閾値、継続時間、severity はすべて Ansible 変数で
上書きできます。`for` の継続時間と Alertmanager のグルーピング／再通知間隔により、
一時的なフラップや短時間のスパイクによる過剰通知を抑えます。

| 障害条件 | 閾値変数（デフォルト） | 継続時間変数（デフォルト） | severity変数（デフォルト） |
| --- | --- | --- | --- |
| SNMP 収集失敗 | - | `monitoring_stack_alert_snmp_down_for` (`2m`) | `monitoring_stack_alert_snmp_down_severity` (`critical`) |
| admin-up / oper-down | - | `monitoring_stack_alert_interface_down_for` (`5m`) | `monitoring_stack_alert_interface_down_severity` (`critical`) |
| 受信／送信帯域使用率 | `monitoring_stack_alert_bandwidth_utilization_percent` (`85`) | `monitoring_stack_alert_bandwidth_high_for` (`10m`) | `monitoring_stack_alert_bandwidth_high_severity` (`warning`) |
| error 増加（受信＋送信 packets/s） | `monitoring_stack_alert_interface_error_rate` (`1`) | `monitoring_stack_alert_interface_error_for` (`5m`) | `monitoring_stack_alert_interface_error_severity` (`warning`) |
| discard 増加（受信＋送信 packets/s） | `monitoring_stack_alert_interface_discard_rate` (`1`) | `monitoring_stack_alert_interface_discard_for` (`5m`) | `monitoring_stack_alert_interface_discard_severity` (`warning`) |
| CPU 使用率 | `monitoring_stack_alert_cpu_utilization_percent` (`85`) | `monitoring_stack_alert_cpu_high_for` (`10m`) | `monitoring_stack_alert_cpu_high_severity` (`warning`) |
| メモリ使用率 | `monitoring_stack_alert_memory_utilization_percent` (`90`) | `monitoring_stack_alert_memory_high_for` (`10m`) | `monitoring_stack_alert_memory_high_severity` (`warning`) |
| 温度 | `monitoring_stack_alert_temperature_celsius` (`70`) | `monitoring_stack_alert_temperature_high_for` (`10m`) | `monitoring_stack_alert_temperature_high_severity` (`critical`) |

error / discard / 帯域の計算期間は `monitoring_stack_alert_rate_window`（デフォルト `5m`）で
変更できます。温度ルールは ENTITY-SENSOR-MIB の Celsius、unit scale のセンサーを対象とし、
対応センサーを公開しない機器では発火しません。

## 監視スタックのヘルス監視

Prometheus は `monitoring-stack` ジョブで Prometheus、Alertmanager、SNMP Exporter、
Node Exporter、Grafana の `/metrics` endpoint を収集します。Prometheus の
`http://<monitoring-host>:9090/targets` で、各コンポーネントの状態を確認できます。

Compose は全コンポーネントに HTTP healthcheck を設定しています。起動状態と healthcheck
結果はデプロイ先の `/opt/network-monitoring` で確認します。

```bash
cd /opt/network-monitoring
docker compose ps
```

Grafana の `Monitoring Stack - Health` ダッシュボードには次の状態を表示します。

- 各コンポーネントの scrape 成否
- 監視対象・SNMP モジュールごとの収集成否
- Prometheus の直近の設定リロード成否
- Prometheus データボリュームの使用率
- 監視サーバの CPU とメモリの使用率

Prometheus は監視スタック自身について次のアラートを評価します。

| 障害条件 | 閾値変数（デフォルト） | 継続時間変数（デフォルト） | severity変数（デフォルト） |
| --- | --- | --- | --- |
| コンポーネントの scrape 失敗 | - | `monitoring_stack_alert_component_down_for` (`2m`) | `monitoring_stack_alert_component_down_severity` (`critical`) |
| Prometheus 設定リロード失敗 | - | `monitoring_stack_alert_config_reload_failed_for` (`5m`) | `monitoring_stack_alert_config_reload_failed_severity` (`critical`) |
| Prometheus データ空き容量低下 | `monitoring_stack_alert_prometheus_data_free_percent` (`15`) | `monitoring_stack_alert_prometheus_data_low_for` (`10m`) | `monitoring_stack_alert_prometheus_data_low_severity` (`critical`) |
| Prometheus データ容量 metric 消失 | - | `monitoring_stack_alert_prometheus_data_metrics_missing_for` (`5m`) | `monitoring_stack_alert_prometheus_data_metrics_missing_severity` (`critical`) |
| 監視サーバ CPU 使用率 | `monitoring_stack_alert_host_cpu_utilization_percent` (`90`) | `monitoring_stack_alert_host_cpu_high_for` (`10m`) | `monitoring_stack_alert_host_cpu_high_severity` (`warning`) |
| 監視サーバメモリ使用率 | `monitoring_stack_alert_host_memory_utilization_percent` (`90`) | `monitoring_stack_alert_host_memory_high_for` (`10m`) | `monitoring_stack_alert_host_memory_high_severity` (`warning`) |

CPU 使用率の計算期間は `monitoring_stack_alert_host_cpu_rate_window`（デフォルト `5m`）で
変更できます。閾値や通知間隔を変更した場合は、設定検証後に再デプロイしてください。

### 障害時の確認と復旧

最初にコンテナ状態、healthcheck の詳細、直近のログを確認します。

```bash
cd /opt/network-monitoring
docker compose ps
docker inspect --format '{{json .State.Health}}' <container-name>
docker compose logs --tail=200 <service-name>
```

主な障害ごとの確認・復旧手順は次のとおりです。

| 症状 | 確認 | 復旧 |
| --- | --- | --- |
| コンポーネントが `unhealthy` または停止 | `docker compose logs --tail=200 <service-name>` と対象コンテナの healthcheck endpoint を確認 | 一時的な障害なら `docker compose restart <service-name>`。設定・ファイル不備なら修正後に Ansible で再デプロイ |
| `CiscoSnmpCollectionFailed` | Prometheus の Targets で対象、auth、module を確認し、`docker compose logs --tail=200 snmp-exporter` を確認 | 到達性、SNMPv3 認証情報、対象の `auth_profile` / `modules` を修正して再デプロイ |
| `PrometheusConfigReloadFailed` または Prometheus が起動しない | 下記の `promtool` で生成済み設定とルールを検証し、Prometheus ログのエラー位置を確認 | Ansible 変数またはテンプレートを修正し、検証成功後に再デプロイ |
| `PrometheusDataStorageLow` | Grafana の使用率、`docker system df`、データ保存先ファイルシステムの空き容量を確認 | 不要な別データを安全に退避・削除するかファイルシステムを拡張し、Prometheus が正常に書き込めることを確認 |
| CPU・メモリアラート | Grafana の推移と `docker stats`、監視サーバ上のプロセスを確認 | 高負荷の原因を解消するか監視サーバのリソースを増強 |

デプロイ済みの Prometheus 設定は次のコマンドで検証できます。

```bash
cd /opt/network-monitoring
docker run --rm \
  --entrypoint /bin/promtool \
  -v "$PWD/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro" \
  -v "$PWD/prometheus/rules:/etc/prometheus/rules:ro" \
  prom/prometheus:latest \
  check config /etc/prometheus/prometheus.yml
```

修正後はローカルでリポジトリ全体の設定を検証してから再デプロイします。

```bash
nix develop --command ./scripts/validate-monitoring-config.sh \
  -e @ansible/group_vars/monitoring_servers.yml

ansible-playbook -i ansible/inventory.yml ansible/playbooks/deploy-monitoring.yml
```

Prometheus 自体が完全に停止すると、Prometheus から Alertmanager へアラートを送信できません。
Compose healthcheck に加え、必要に応じて別ホストから Prometheus の `/-/ready` を監視してください。

### テスト通知

デプロイ後、Alertmanager API へテストアラートを送信します。

```bash
curl -X POST "http://<monitoring-host>:9093/api/v2/alerts" \
  -H "Content-Type: application/json" \
  -d '[{
    "labels": {
      "alertname": "ManualNotificationTest",
      "instance": "manual-test",
      "severity": "warning"
    },
    "annotations": {
      "summary": "Alertmanager manual notification test"
    },
    "endsAt": "2099-01-01T00:00:00Z"
  }]'
```

Alertmanager の `http://<monitoring-host>:9093/#/alerts` と通知先 Webhook で受信を確認します。
確認後は、同じラベルと過去の `endsAt` を送ってテストアラートを解決します。

```bash
curl -X POST "http://<monitoring-host>:9093/api/v2/alerts" \
  -H "Content-Type: application/json" \
  -d '[{
    "labels": {
      "alertname": "ManualNotificationTest",
      "instance": "manual-test",
      "severity": "warning"
    },
    "endsAt": "2000-01-01T00:00:00Z"
  }]'
```

### 設定ファイルの検証

CI はデフォルトの1台構成と2台構成のfixtureについて Ansible テンプレートをレンダリングし、
生成した Prometheus 設定を `promtool` で検証します。Compose 設定、Grafana dashboard JSON、
Alertmanager 設定もそれぞれ Docker Compose、`jq`、`amtool` で検証します。同じ検証は
ローカルでも実行できます。

```bash
nix develop --command ./scripts/validate-monitoring-config.sh
```

独自の変数ファイルも検証する場合は、Ansible の追加引数として渡します。

```bash
nix develop --command ./scripts/validate-monitoring-config.sh \
  --vault-password-file secret \
  -e @ansible/group_vars/monitoring_servers.yml
```

## Grafana ダッシュボード

Grafana 13 の V2 Resource 形式で、次のダッシュボードをリポジトリ管理しています。

- `Cisco Router - Overview`
- `Cisco Router - Errors`
- `Monitoring Stack - Health`

ダッシュボード JSON は `files/grafana/dashboards` に配置され、デプロイ時に Grafana へ
自動プロビジョニングされます。Grafana 上での編集は許可していますが、変更内容は
リポジトリへ自動反映されないため、サーバ上で編集した場合は JSON を再取得してください。

### Cisco 固有メトリクス

Prometheus は対象ごとの `modules` 設定に応じて次の2ジョブで収集します。

- `cisco-router-snmp`: `if_mib` によるインターフェース情報
- `cisco-router-device`: `cisco_device` による機器内部の状態

対象のCisco C800（IOS 15.8(3)M9）で `snmpwalk` により取得を確認した項目だけを、
`Cisco Router - Overview` ダッシュボードに表示します。

| 種別 | 主なメトリクス | 備考 |
| --- | --- | --- |
| CPU | `cpmCPUTotal1minRev`, `cpmCPUTotal5minRev` | ダッシュボードは装置全体の5分平均を表示 |
| メモリ | `cempMemPoolUsed`, `cempMemPoolFree`, `ciscoMemoryPoolUsed`, `ciscoMemoryPoolFree` | 新旧両方のCisco Memory Pool MIBに対応し、使用量と使用率を表示 |
| 電源 | `cefcFRUPowerOperStatus` | 電源・FRUごとの状態を表示 |
| ソフトウェアイメージ | `ciscoImageString` | OLD-CISCO-IMAGE-MIBからIOSイメージ、ファミリー、機能、バージョンを表示 |

Cisco固有MIBの実装範囲は機種、IOS/IOS XEのバージョン、ライセンスによって異なります。
この機器ではCISCO-ENTITY-SENSOR-MIBの温度センサーとCISCO-IMAGE-MIBには応答しないため、
本ダッシュボードの対象外です。`cisco_device` は未対応OIDを読み飛ばし、対応する他の系列を
継続して収集します。また、Cisco固有監視を `if_mib` と別ジョブにしているため、Cisco固有
ジョブでタイムアウトなどが発生してもインターフェース監視には影響しません。

## 動作確認（任意）

`snmpwalk` を使った SNMP 設定確認例（`net-snmp` が別途インストール済みの場合）:

```bash
snmpwalk -v3 \
  -l authPriv \
  -u <snmp-username> \
  -a SHA -A <auth-password> \
  -x AES -X <priv-password> \
  <router-ip> 1.3.6.1.2.1.1
```
