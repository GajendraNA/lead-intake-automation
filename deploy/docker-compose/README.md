# n8n Self-Hosted Starter Kit

A Docker Compose setup for self-hosted n8n with PostgreSQL, optional queue mode (Redis and workers), an optional HTTPS proxy (Caddy), backup and restore scripts, and a workflow-export script.

## What is in this folder

| File | Purpose |
| --- | --- |
| `docker-compose.yml` | n8n and Postgres by default; `queue` and `proxy` profiles add Redis, workers and Caddy |
| `.env.example` | Settings template. Copy it to `.env` |
| `Caddyfile` | Reverse proxy with automatic HTTPS |
| `scripts/backup.sh` | Postgres dump and n8n data volume archive |
| `scripts/restore.sh` | Restore a Postgres dump |
| `scripts/export-workflows.sh` | Export workflows as JSON and commit them to a Git repo |

Requirements: Docker Engine or Docker Desktop with Compose v2. On Windows, run the scripts from WSL or Git Bash.

---

## 1. Start in simple mode (local)

1. Copy the settings file and generate two secrets:

   ```bash
   cp .env.example .env
   openssl rand -hex 32      # paste into N8N_ENCRYPTION_KEY
   openssl rand -base64 24   # paste into POSTGRES_PASSWORD
   ```

2. Start the stack and check it:

   ```bash
   docker compose up -d
   docker compose ps
   ```

3. Open `http://localhost:5678` and create the owner account.
4. Copy `N8N_ENCRYPTION_KEY` into a password manager now. Never change it after you save credentials in n8n.

Webhooks from the internet cannot reach your laptop. For testing, run a tunnel tool, set `WEBHOOK_URL` in `.env` to the tunnel's public URL, and run `docker compose up -d` again.

## 2. Go to production (VPS with HTTPS)

1. Create a Linux VPS (Ubuntu is assumed below) and install Docker Engine and the Compose plugin from Docker's official instructions.
2. Point a DNS A record, for example `n8n.yourdomain.com`, at the server's IP address.
3. Copy this folder to the server and edit `.env`:

   ```text
   N8N_HOST=n8n.yourdomain.com
   N8N_PROTOCOL=https
   WEBHOOK_URL=https://n8n.yourdomain.com/
   N8N_SECURE_COOKIE=true
   COMPOSE_PROFILES=proxy
   ```

   Remove or comment out the local values for the same four variables.

4. Start it. Caddy requests the certificate automatically when ports 80 and 443 are reachable:

   ```bash
   docker compose up -d
   docker compose logs caddy --tail 30
   ```

5. Verify that n8n is only reachable through the proxy:

   ```bash
   curl -I https://n8n.yourdomain.com
   ss -tlnp | grep 5678     # should show 127.0.0.1:5678, not 0.0.0.0
   ```

## 3. Switch to queue mode (only when you need it)

Queue mode spreads executions over worker containers through Redis. Use it for heavy or business-critical load. Start with simple mode otherwise.

1. In `.env` set:

   ```text
   EXECUTIONS_MODE=queue
   COMPOSE_PROFILES=queue,proxy
   ```

2. Apply it and add workers:

   ```bash
   docker compose up -d
   docker compose up -d --scale n8n-worker=3
   docker compose logs n8n-worker --tail 20
   ```

All n8n processes read the same `N8N_ENCRYPTION_KEY` and database from `.env`, which is what queue mode requires.

## 4. Backups and a restore test

1. Make the scripts executable and run a first backup:

   ```bash
   chmod +x scripts/*.sh
   ./scripts/backup.sh
   ls -lh backups/
   ```

2. Schedule it nightly with cron (`crontab -e`). Create the folder first so the log file can be written:

   ```bash
   mkdir -p ~/n8n-starter-kit/backups
   ```

   ```text
   0 3 * * * /home/youruser/n8n-starter-kit/scripts/backup.sh >> /home/youruser/n8n-starter-kit/backups/backup.log 2>&1
   ```

3. Copy backups off the server regularly (`scp`, `rsync` or a cloud storage tool). A backup on the same disk is not enough.
4. Keep `.env` in a password manager, separate from the backups. The dump holds credentials in encrypted form, and the key decrypts them.
5. Test a restore on another machine (your laptop) before you need it:

   ```bash
   cp /path/to/.env .env
   docker compose up -d
   ./scripts/restore.sh backups/n8n-db-YYYY-MM-DD_HHMM.sql.gz
   ```

   Then log in and check that workflows and credentials work.

## 5. Harden the server (Ubuntu)

1. Firewall:

   ```bash
   sudo ufw allow OpenSSH
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   sudo ufw enable
   ```

2. SSH keys. From your computer, copy your key, then confirm key login works in a second terminal before changing anything:

   ```bash
   ssh-copy-id youruser@your-server-ip
   ```

   On the server, create `/etc/ssh/sshd_config.d/99-hardening.conf`:

   ```text
   PasswordAuthentication no
   PermitRootLogin no
   ```

   ```bash
   sudo systemctl restart ssh
   ```

3. fail2ban:

   ```bash
   sudo apt install -y fail2ban
   sudo systemctl enable --now fail2ban
   sudo fail2ban-client status sshd
   ```

4. Two-factor authentication: turn on 2FA for your n8n owner account in n8n's personal settings and save the recovery codes.
5. Note on Docker and ufw: ports that Docker publishes can bypass ufw rules. This kit publishes n8n on `127.0.0.1` only, and Postgres and Redis publish no ports. Only Caddy publishes 80 and 443, on purpose.

## 6. Self-monitoring: failed-execution alerts

1. In Telegram, message `@BotFather`, send `/newbot`, and copy the bot token.
2. Send any message to your new bot, then open `https://api.telegram.org/bot<TOKEN>/getUpdates` in a browser and note the `chat` `id` number.
3. In n8n, create a Telegram credential with the bot token.
4. Create a workflow named `Global Error Alert` with two nodes:
   - **Error Trigger**
   - **Telegram** (Send Message), chat ID from step 2, text:

   ```text
   Workflow failed: {{ $json.workflow.name }}
   Last node: {{ $json.execution.lastNodeExecuted }}
   Error: {{ $json.execution.error.message }}
   {{ $json.execution.url }}
   ```

5. Save it. Then open each workflow you want watched, go to its settings, set **Error Workflow** to `Global Error Alert`, and save.
6. Test with a workflow that has a trigger and a Code node that throws an error. Error workflows run for automatic executions, not manual test runs.
7. Add an outside check: create a free uptime monitor that requests `https://n8n.yourdomain.com/healthz` every few minutes and alerts you. If n8n is down, its own alerts cannot fire.

## 7. Self-monitoring: export workflows to Git

1. Create a private Git repository (for example on GitHub) for your workflows.
2. Link it and run the first export:

   ```bash
   mkdir -p workflow-export && cd workflow-export
   git init
   git remote add origin git@github.com:youruser/n8n-workflows.git
   cd ..
   ./scripts/export-workflows.sh
   ```

3. On a server, give it push access with a deploy key that has write access to that one repository.
4. Schedule it with cron:

   ```text
   30 3 * * * /home/youruser/n8n-starter-kit/scripts/export-workflows.sh >> /home/youruser/n8n-starter-kit/backups/export.log 2>&1
   ```

The script exports workflows only, never credentials. Check workflows for hard-coded keys before pushing.

## 8. Updating n8n

```bash
./scripts/backup.sh
docker compose pull
docker compose up -d
docker compose logs n8n --tail 30
```

For client installs, set `N8N_IMAGE_TAG` in `.env` to a tested version and read the release notes before upgrading.

## Licence note for freelancers

n8n uses the Sustainable Use License. Building and maintaining workflows for clients on their own instances is generally accepted, but offering n8n as a paid hosted service where customers log in to your instance is not. Some features (such as SSO) need a paid Enterprise key. When in doubt, confirm with n8n at license@n8n.io.

## Checklist

- [ ] `.env` created, encryption key saved in a password manager
- [ ] Stack running on Postgres, n8n bound to localhost
- [ ] HTTPS working through the proxy profile
- [ ] Nightly backup scheduled, copies stored off the server, restore tested
- [ ] Firewall, SSH keys, fail2ban and n8n 2FA enabled
- [ ] `Global Error Alert` workflow attached to your workflows
- [ ] External uptime monitor on `/healthz`
- [ ] Workflow export scheduled to a private Git repo
