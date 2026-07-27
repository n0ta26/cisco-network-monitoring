# cisco-network-monitoring

自宅ラボの Cisco ルータを対象に、SNMP で情報収集できる監視基盤
（`snmp-exporter` / `Prometheus` / `Alertmanager` / `Grafana`）を Ansible で
プロビジョニングするためのリポジトリです。

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

## 事前設定

1. 監視サーバ接続先を設定する  
   `ansible/inventory.yml` の `ansible_host` / `ansible_user` / `ansible_ssh_private_key_file` を環境に合わせて変更します。
2. SNMP 監視対象を設定する  
   `monitoring_stack_targets` を Ansible の group vars で定義します。
   詳細は[監視対象の管理](#監視対象の管理)を参照してください。
3. SNMPv3 認証情報を設定する  
   `files/snmp_exporter/snmp.yml` の `auths.cisco_v3` に Cisco ルータで設定済みの `username` / `password` / `priv_password` を設定します。
   監視対象の `auth_profile` には、ここで定義した auth 名を指定します。
4. アラートの通知先や閾値を設定する
   [アラート通知](#アラート通知)を参照し、必要な Ansible 変数を上書きします。

## 監視対象の管理

監視対象は `monitoring_stack_targets` のリストで管理します。例えば
`ansible/group_vars/monitoring_servers.yml` に次のように定義します。
このファイルを Ansible Vault で暗号化している場合は、`ansible-vault edit` で編集してください。

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
| `auth_profile` | 必須 | `files/snmp_exporter/snmp.yml` の `auths` に定義した認証プロファイル名 |
| `modules` | 必須 | 使用する SNMP モジュールのリスト。標準は `if_mib` と `cisco_device` |
| `labels` | 任意 | `site` などの追加 Prometheus ラベル。不要な場合は `{}` または省略可能 |

ロールのデフォルト値には従来と同じ `172.16.2.1` の1台構成が定義されているため、
`monitoring_stack_targets` を上書きしない既存環境もそのままデプロイできます。group vars で
定義する場合はリスト全体が置き換わるため、監視を継続する機器をすべて記載してください。

機器を追加する場合はリストへ項目を追加し、`auth_profile` と `modules` が
`files/snmp_exporter/snmp.yml` および
`monitoring_stack_snmp_module_jobs` に存在することを確認します。機器を削除する場合は
対象の項目をリストから削除します。変更後は設定検証を実行してから再デプロイしてください。
Prometheus 設定は Ansible がリストから再生成するため、手作業で編集する必要はありません。

```bash
nix develop --command ./scripts/validate-monitoring-config.sh \
  -e @ansible/group_vars/monitoring_servers.yml

ansible-playbook -i ansible/inventory.yml ansible/playbooks/deploy-monitoring.yml
```

## デプロイ

```bash
ansible-playbook -i ansible/inventory.yml ansible/playbooks/deploy-monitoring.yml
```

デプロイ後、監視サーバの以下ポートで各コンポーネントにアクセスできます。

- Grafana: `http://<monitoring-host>:3000`
- Prometheus: `http://<monitoring-host>:9090`
- Alertmanager: `http://<monitoring-host>:9093`
- SNMP Exporter: `http://<monitoring-host>:9116`

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
生成した Prometheus 設定を `promtool` で検証します。Compose 設定と Alertmanager 設定も
それぞれ Docker Compose、`amtool` で検証します。同じ検証はローカルでも実行できます。

```bash
nix develop --command ./scripts/validate-monitoring-config.sh
```

独自の変数ファイルも検証する場合は、Ansible の追加引数として渡します。

```bash
nix develop --command ./scripts/validate-monitoring-config.sh \
  -e @ansible/group_vars/monitoring_servers.yml
```

## Grafana ダッシュボード

Grafana 13 の V2 Resource 形式で、次のダッシュボードをリポジトリ管理しています。

- `Cisco Router - Overview`
- `Cisco Router - Errors`

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
