# Token Refresh

每次重部署或清空数据卷后，`password`、owner `access_token`、`agent_token` 和 cc-connect Matrix session 都会变化。状态机 S6 会自动回填；手动恢复时按这里检查。

## 远端凭据

EC2 机器内 `/opt/p2p/bootstrap.json`:

```json
{
  "version": 1,
  "owner_user_id": "__OWNER_USER_ID__",
  "user_id": "__OWNER_USER_ID__",
  "homeserver": "https://__DOMAIN__",
  "access_token": "<ACCESS_TOKEN>",
  "agent_token": "<AGENT_TOKEN>",
  "password": "<LOGIN_PASSWORD>",
  "agent_room_id": "__ROOM_ID__"
}
```

取回:

```bash
ssh -i <key.pem> ubuntu@<ip> 'sudo cat /opt/p2p/bootstrap.json' > bootstrap.json
```

## 本地服务凭据

`~/.direxio/nodes/<service_id>/credentials.json`:

```json
{
  "profiles": {
    "default": {
      "password": "<LOGIN_PASSWORD>",
      "access_token": "<ACCESS_TOKEN>",
      "agent_room_id": "__ROOM_ID__",
      "direxio_domain": "https://__DOMAIN__",
      "direxio_agent_token": "<AGENT_TOKEN>",
      "direxio_agent_room_id": "__ROOM_ID__",
      "direxio_agent_node_id": "<agent_node_id>"
    }
  }
}
```

权限必须是 `0600`:

```bash
chmod 600 ~/.direxio/nodes/<service_id>/credentials.json
```

S6 也会写：

```text
~/.direxio/nodes/<service_id>/env
~/.direxio/nodes/<service_id>/cc-connect/matrix-session.json
~/.direxio/nodes/<service_id>/cc-connect/config.toml
```

刷新后重新安装或重启本地 bridge：

```bash
direxio-connect daemon install --config ~/.direxio/nodes/<service_id>/cc-connect/config.toml --force
direxio-connect daemon status
```

## 验证

```bash
curl -skf https://<domain>/healthz && echo OK
curl -sk https://<domain>/.well-known/portal/owner.json
curl -sk https://<domain>/_matrix/client/versions
```
