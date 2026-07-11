# cisco-network-monitoring

自宅ラボの Cisco ルータを対象に、SNMP で情報収集できる監視基盤
（`snmp-exporter` / `Prometheus` / `Grafana`）を Ansible でプロビジョニングするためのリポジトリです。

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
   `files/prometheus/prometheus.yml` の2つのジョブにある `targets`（例: `172.16.2.1`）やラベルを自宅ラボ構成に合わせます。
   `cisco-router-snmp` と `cisco-router-device` には同じ対象機器を設定してください。
3. SNMPv3 認証情報を設定する  
   `files/snmp_exporter/snmp.yml` の `auths.cisco_v3` に Cisco ルータで設定済みの `username` / `password` / `priv_password` を設定します。

## デプロイ

```bash
ansible-playbook -i ansible/inventory.yml ansible/playbooks/deploy-monitoring.yml
```

デプロイ後、監視サーバの以下ポートで各コンポーネントにアクセスできます。

- Grafana: `http://<monitoring-host>:3000`
- Prometheus: `http://<monitoring-host>:9090`
- SNMP Exporter: `http://<monitoring-host>:9116`

## Grafana ダッシュボード

Grafana 13 の V2 Resource 形式で、次のダッシュボードをリポジトリ管理しています。

- `Cisco Router - Overview`
- `Cisco Router - Errors`

ダッシュボード JSON は `files/grafana/dashboards` に配置され、デプロイ時に Grafana へ
自動プロビジョニングされます。Grafana 上での編集は許可していますが、変更内容は
リポジトリへ自動反映されないため、サーバ上で編集した場合は JSON を再取得してください。

### Cisco 固有メトリクス

Prometheus は対象ルータを次の2ジョブで収集します。

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
