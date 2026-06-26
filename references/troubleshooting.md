# Troubleshooting

## cc-connect Bridge

- `agent_room_id` must be a real Matrix room id beginning with `!`. Values like `!agent:<domain>` are legacy pseudo ids and must be fixed by redeploying or restarting a current message-server build.
- `agent.matrix_session.create` must return `@agent:<server>`. If it returns `@owner:<server>`, deploy a message-server build that includes agent Matrix session support.
- `cc-connect/config.toml` must contain one Matrix platform and the same `room_id` as S5/S6 state.
- `direxio-connect daemon status` checks the local bridge process. If no daemon is installed, run the command printed in S6 state `agent_install_command`.
- If npm install fails, verify `npm view @direxio/connent` and that the GitHub release contains the matching `direxio-connect` binary asset.

## Matrix Checks

The deployed homeserver should answer:

```bash
curl -k https://<domain>/_matrix/client/versions
```

The local bridge should use the Matrix session file at:

```text
~/.direxio/nodes/<service_id>/cc-connect/matrix-session.json
```

Do not hand-edit the access token unless S6 cannot create a session; rerun S6 after refreshing server credentials.
