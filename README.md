# Lead Intake Automation (n8n)

An automation that takes leads from a web form, checks them, enriches them, scores them with an AI model, saves them to Postgres, and alerts a Slack channel for the ones worth a quick reply.

Built with **n8n**, **Postgres**, **Groq** (LLM scoring) and **Slack**. This repo is a ready-to-import package: workflows, database schema, and three ways to run it.

> This package contains **no secrets**. You supply your own Groq key, Slack app and database, so running it costs only your own usage.

## How it works

```
POST /webhook/lead-intake  (Basic Auth)
        │
        ▼
 WF1 Lead Intake
   Normalise fields ─► valid email? ──no──► reject (400)
        │ yes
        ├─► acknowledge the sender immediately
        ▼
   WF2 Enrich Lead (sub-workflow: demo company lookup)
        ▼
   Score lead with Groq (fit score 0-100, urgency, budget, summary)
        ▼
   Build record (tier = needs_review if the score is missing or outside 0-100)
        ▼
   Save lead to Postgres (upsert by email)
        ▼
   Route by tier ─► hot  (score ≥ 70) ► Slack alert
                 ├─► warm (score ≥ 40) ► Slack message
                 └─► cold              ► saved only

 WF3 Error Handler: any failed run ─► Slack alert + row in error_log
```

| Workflow | File | Role |
| --- | --- | --- |
| WF1 Lead Intake | [workflows/WF1-lead-intake.json](workflows/WF1-lead-intake.json) | Webhook, validation, scoring, save, routing |
| WF2 Enrich Lead | [workflows/WF2-enrich-lead.json](workflows/WF2-enrich-lead.json) | Enrichment step called by WF1. It currently calls the public placeholder API `jsonplaceholder.typicode.com`, which returns demo data. Swap in a real company-data API to get real enrichment. |
| WF3 Error Handler | [workflows/WF3-error-handler.json](workflows/WF3-error-handler.json) | Notifies Slack and logs failures |
| WF4 Demo Lead | [workflows/WF4-demo-lead.json](workflows/WF4-demo-lead.json) | Optional. A public, rate-limited endpoint behind the live demo page. It does not save leads or post to Slack. |

Database tables are in [sql/schema.sql](sql/schema.sql): `leads` and `error_log`. The optional demo adds `demo_runs` ([sql/demo.sql](sql/demo.sql)), which stores only hashed IPs for rate limiting.

## Live demo

**https://gajendrana.github.io/lead-intake-automation/**

The page in [docs/index.html](docs/index.html) sends a sample lead to WF4, which runs the same enrichment and AI scoring as WF1 and returns the result. It is limited to 3 runs per visitor per hour and 50 per day, stores no lead data, and never posts to Slack. The demo runs on a free server that sleeps when idle, so the first run can take up to a minute.

To run your own copy of the demo, import WF4, create the `demo_runs` table, and change `ENDPOINT` and the allowed origin (the webhook's **Allowed Origins** option) to your own URLs.

## What you need

- An n8n instance (self-hosted, version 2.x was used here)
- A Postgres database
- A [Groq](https://groq.com) API key
- A Slack app with a bot token and two channels (hot and warm leads) plus one for errors

## Setup

1. **Create the tables.** Run `sql/schema.sql` on a database named `leads` (or any name you like).
2. **Import the workflows.** Import all three files in `workflows/`. Importing with the n8n CLI keeps the workflow IDs, which WF1 uses to call WF2 and the error workflow setting:
   ```bash
   n8n import:workflow --separate --input=workflows
   ```
   If you import through the UI, open the **Enrich lead** node in WF1 and re-select WF2, and set WF3 as the error workflow in WF1's settings.
3. **Create credentials in n8n** and attach them to the nodes. The exports use placeholders (`REPLACE_ME`), so n8n will show which nodes need a credential:
   - **Basic Auth** for the webhook (choose your own username and password)
   - **Groq** API key
   - **Postgres** pointing at your `leads` database
   - **Slack** bot token
4. **Set the Slack channels.** The Slack nodes contain `YOUR_SLACK_CHANNEL_ID`. Replace it with your own channel IDs.
5. **Activate** WF1, WF2 and WF3.

## Try it

```bash
curl -i -u YOUR_USER:YOUR_PASS -X POST https://YOUR-N8N-HOST/webhook/lead-intake \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","name":"Test User","company":"Test Co","message":"We need automation for our sales team, budget approved, want to start this month.","source":"manual-test"}'
```

Fields: `email` (required, must be valid), `name`, `company`, `message`, `source`.

## Ways to run it

| Option | Best for | Guide |
| --- | --- | --- |
| Docker Compose | Local use or a VPS with HTTPS (Caddy) | [deploy/docker-compose](deploy/docker-compose/README.md) |
| Kubernetes | A local or cloud cluster | [deploy/kubernetes](deploy/kubernetes) |
| Render + Neon | Free hosting, with caveats | [deploy/render](deploy/render/README.md) |

### Kubernetes notes

The manifests expect a namespace `lead-intake` and two secrets you create yourself:

```bash
kubectl create namespace lead-intake
kubectl create secret generic postgres-secret -n lead-intake \
  --from-literal=POSTGRES_USER=n8n --from-literal=POSTGRES_PASSWORD='<choose one>'
kubectl create secret generic n8n-secret -n lead-intake \
  --from-literal=N8N_ENCRYPTION_KEY="$(openssl rand -hex 32)"
kubectl apply -f deploy/kubernetes/postgres.yaml -f deploy/kubernetes/n8n.yaml
```

Keep the encryption key safe. Without it, credentials saved in n8n cannot be decrypted after a restore.

## Things to know

- **Costs and abuse.** The webhook calls an LLM and posts to Slack on every valid lead, so protect it. Keep the Basic Auth on, and consider rate limiting in front of it before exposing it publicly.
- **Free hosting sleeps.** On Render's free plan the service sleeps after 15 minutes without traffic, so the first request afterwards can take around a minute.
- **Personal data.** Leads are personal data. Treat the `leads` table accordingly and don't commit backups or dumps.

## License

MIT, see [LICENSE](LICENSE).
