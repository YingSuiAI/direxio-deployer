# Verification And Recovery

## Fresh Verification

Run the built-in acceptance phase through the state machine:

```bash
bash scripts/orchestrate.sh status
```

Complete state shows `current: DONE` and S0-S7 as `done`.

Independent checks:

```bash
curl -fsS https://<DOMAIN>/healthz
curl -fsS https://<DOMAIN>/_matrix/client/versions
curl -fsS https://<DOMAIN>/.well-known/matrix/server
curl -fsS https://<DOMAIN>/.well-known/portal/owner.json
```

If local DNS lags but authoritative DNS is correct, use:

```bash
curl --resolve <DOMAIN>:443:<PUBLIC_IP> -fsS https://<DOMAIN>/healthz
```

## Common Waiting Points

- S0 waits for valid AWS credentials.
- S1 waits for default VPC, EC2 quota, or AMI availability.
- S3 waits for DNS A record.
- S4 waits for Docker/image pulls/Caddy certificate issuance.
- S5 waits for `/opt/p2p/bootstrap.json` and password/agent_token extraction.

Rerun the same command after fixing the blocker; state resumes from the first unfinished phase.

## Destroy

Destroy recorded AWS resources while state exists:

```bash
DOMAIN=__DOMAIN__ bash scripts/destroy.sh
```

Destroy stops the local `direxio-connect` daemon only when its reported `WorkDir` matches the current service's `~/.direxio/nodes/<service_id>/cc-connect` directory. It then cleans recorded EC2, EIP, key pair, security group, and current service directory best-effort. User-managed DNS records and purchased domains remain the user's responsibility.
