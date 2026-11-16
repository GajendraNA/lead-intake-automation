# Deploy n8n (Lead Intake) to Render, free

- **n8n** runs on a Render free web service, using the official `n8nio/n8n:2.44.5` image. That's the same version as your Kubernetes setup.
- **Postgres** runs on Neon's free plan. Render's free Postgres is deleted after 30 days, so we don't use it.
- **Data** comes over from your local Kubernetes cluster: 3 workflows, 4 credentials, and the `leads` + `error_log` tables.

Neither service needs a credit card for the free plan, but sign-up rules can change.

---

## 1. Neon: create the databases (about 5 min)

1. Sign up at neon.tech (free plan).
2. Create a project:
   - Name: `n8n-render`
   - Postgres version: **16**
   - Region: **AWS Asia Pacific (Singapore)**
   - Database name: `n8n`
3. In the project, open **Databases → New database** and create a second database named `leads`. Use the same owner role.
4. Click **Connect**:
   1. Turn **Connection pooling OFF**.
   2. Copy the connection string for the `n8n` database.
   3. Switch the database to `leads` and copy that string too.
5. In Git Bash, from the `Automation_Learning` folder, create your settings file:

   ```bash
   cp render-deploy/.neon.env.example render-deploy/.neon.env
   ```

   Paste the two strings into `render-deploy/.neon.env`. That file is git-ignored and stays on your machine.

## 2. Copy your data into Neon (about 1 min)

```bash
bash render-deploy/migrate-to-neon.sh
```

The script:

1. Briefly stops your local n8n.
2. Dumps the `n8n` and `leads` databases from the `postgres-0` pod.
3. Restores both into Neon.
4. Prints the row counts. You should see 3 workflows, 4 credentials and 1 lead.
5. Starts your local n8n again.

## 3. Get your encryption key

Your saved credentials (Slack, Groq, Postgres, Basic Auth) are encrypted with this key. The Render instance **must use the same key**.

```bash
kubectl get secret n8n-secret -n lead-intake -o jsonpath='{.data.N8N_ENCRYPTION_KEY}' | base64 -d; echo
```

Keep it in a password manager too.

## 4. Render: create the web service (about 5 min)

1. Sign up at render.com.
2. Go to **New → Web Service → Existing Image**.
3. Image URL: `docker.io/n8nio/n8n:2.44.5`
4. Name: choose one, for example `leads-n8n`. Your URL will be `https://<name>.onrender.com`. If the name is taken, Render adds a suffix, so use the URL it shows you.
5. Region: **Singapore**. Instance type: **Free**.
6. Under **Advanced**, set **Health Check Path** to `/healthz`.
7. Add these **Environment Variables**. Replace `<name>` with your service name. The Neon host, user and password come from the n8n connection string: `postgresql://USER:PASSWORD@HOST/n8n`.

| Key | Value |
| --- | --- |
| `DB_TYPE` | `postgresdb` |
| `DB_POSTGRESDB_HOST` | Neon host (`ep-....ap-southeast-1.aws.neon.tech`) |
| `DB_POSTGRESDB_PORT` | `5432` |
| `DB_POSTGRESDB_DATABASE` | `n8n` |
| `DB_POSTGRESDB_USER` | Neon user |
| `DB_POSTGRESDB_PASSWORD` | Neon password |
| `DB_POSTGRESDB_SSL_ENABLED` | `true` |
| `N8N_ENCRYPTION_KEY` | the key from step 3 |
| `N8N_HOST` | `<name>.onrender.com` |
| `N8N_PROTOCOL` | `https` |
| `N8N_PORT` | `5678` |
| `PORT` | `5678` |
| `WEBHOOK_URL` | `https://<name>.onrender.com/` |
| `N8N_PROXY_HOPS` | `1` |
| `GENERIC_TIMEZONE` | `Asia/Kolkata` |
| `TZ` | `Asia/Kolkata` |
| `NODE_OPTIONS` | `--max-old-space-size=400` |
| `EXECUTIONS_DATA_PRUNE` | `true` |
| `EXECUTIONS_DATA_MAX_AGE` | `168` |
| `N8N_DIAGNOSTICS_ENABLED` | `false` |

8. Click **Deploy**. The first boot takes a few minutes while n8n checks the database.

## 5. After it's live

1. Open `https://<name>.onrender.com`. Log in with your **existing** n8n owner account; it came over with the database.
2. **Credentials → Postgres account**: your local credential points at host `postgres`, which doesn't exist on Render. Change it to the Neon `leads` database:
   - Host: Neon host
   - Database: `leads`
   - User / Password: Neon user and password
   - SSL: **Require**
   - Port: `5432`

   Then click **Save** and the connection test should pass.
3. Your public webhook is now:
   `https://<name>.onrender.com/webhook/lead-intake`

   Update your form or anything else that posts leads so it uses this URL.
4. Send one test lead and check that it appears in the Neon `leads` table and in Slack.

## 6. Keep it awake (optional, recommended)

Render's free plan puts the service to sleep after 15 minutes without traffic. Waking it takes about a minute, so the first lead after a quiet spell can time out.

- Fix: create a free job on cron-job.org that sends a GET to `https://<name>.onrender.com/healthz` every 10 minutes.
- Render gives 750 free instance hours a month, which is enough for one service running all month.

## Limits to know

- **Memory:** the free instance has 512 MB of RAM. `NODE_OPTIONS` above keeps n8n inside that. If Render's logs show out-of-memory restarts, the next step is a paid instance or the Oracle Always Free VM.
- **Storage:** Neon's free plan gives 0.5 GB. Execution history is pruned after 7 days to stay well under it; your data is about 25 MB now.
- **Updates:** to upgrade n8n, change the image tag in Render and redeploy. Upgrade one version line at a time, and back up first with the `pg_dump` command from the script.
