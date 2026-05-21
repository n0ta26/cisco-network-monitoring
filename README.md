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
   `files/prometheus/prometheus.yml` の `targets`（例: `172.16.2.1`）やラベルを自宅ラボ構成に合わせます。
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
