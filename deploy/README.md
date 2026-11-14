# Deploying polticool

Every push to `main` runs `.github/workflows/deploy.yml`:

1. **test**: compile with warnings as errors, check formatting, run `mix test` against Postgres
2. **build**: build the release image from `Dockerfile` and push it to `ghcr.io/thenatespack/polticool:{sha,latest}`
3. **deploy**: SSH to the server, copy `docker-compose.yml`, `docker compose pull`, run `bin/migrate`, `up -d`, then smoke-test

```
Cloudflare (Full strict) → Apache :443 (certbot) → 127.0.0.1:4010 → app container :4000 → db container
```

## One-time server setup (Ubuntu, 217.77.7.98)

```sh
scp -r deploy you@217.77.7.98:~/polticool-deploy
ssh you@217.77.7.98 'sudo bash ~/polticool-deploy/server-setup.sh'
```

The script installs Docker and the compose plugin, creates a `deploy` user in the `docker` group,
creates `/opt/polticool/.env` with a generated DB password and `SECRET_KEY_BASE`,
installs the Apache vhost, and runs certbot.

Then:

1. Generate a CI key pair and authorize it for the `deploy` user:
   ```sh
   ssh-keygen -t ed25519 -f polticool_deploy -N "" -C "github-actions polticool"
   ssh you@217.77.7.98 'sudo tee -a /home/deploy/.ssh/authorized_keys' < polticool_deploy.pub
   ```
2. Add GitHub repo secrets (Settings → Secrets and variables → Actions):
   | Secret | Value |
   |---|---|
   | `DEPLOY_HOST` | `217.77.7.98` |
   | `DEPLOY_USER` | `deploy` |
   | `DEPLOY_SSH_KEY` | contents of `polticool_deploy` (private key) |
3. Put `ANTHROPIC_API_KEY` in `/opt/polticool/.env`.
4. In Cloudflare, set SSL/TLS mode to **Full (strict)**. Flexible causes a redirect loop because of `force_ssl`.

## Day-to-day

```sh
ssh deploy@217.77.7.98
cd /opt/polticool
docker compose logs -f app                 # tail logs
docker compose exec app bin/polticool remote   # IEx into the running node
docker compose ps
```

Roll back to an earlier build:

```sh
APP_TAG=<older-sha> docker compose up -d app
```

## Running data jobs on the server

The production image is a release with no `mix`, so the mix tasks have release
equivalents in `Polticool.Release`. Run them from `/opt/polticool` (they use the
container's env, so `LEGISCAN_API_KEY` / `ANTHROPIC_API_KEY` in `.env` apply). They start
the full app (Repo, PubSub, Finch) but not the web listener. If your user is not in the
`docker` group, prefix with `sudo`.

**LegiScan import** (about 3 LegiScan queries: 1 getDatasetList plus 1 per changed session;
default sessions 2026GS and 2025GS):

```sh
cd /opt/polticool
sudo docker compose exec app bin/polticool eval "Polticool.Release.import_legiscan()"
# options: sessions: ["2026GS"], zips: ["/app/ds.zip"] (no API calls), force: true,
#          strict: true, refresh_roster: true
sudo docker compose exec app bin/polticool eval 'Polticool.Release.import_legiscan(sessions: ["2026GS"], force: true)'
```

It prints per-session stats and any unmapped legislators (fix them in
`priv/data/legiscan_people.json`, commit, deploy, re-run).

**Backfill bill text** (one le.utah.gov request per bill, 2 s apart; no API quota). LegiScan
datasets carry no bill text, and matching only runs on bills with text, so run this before
recording. It only fills `provisions`/`versions` (and blank sponsor fields), never votes. Do
**not** run a full le.utah.gov ingest on prod: its votes would duplicate the LegiScan ones.

```sh
cd /opt/polticool
sudo docker compose exec app bin/polticool eval 'Polticool.Release.backfill_bill_text("THURSNK")'
```

**Seeds** (idempotent; removes SAMPLE placeholder pledges). A bare `eval` of
`Polticool.Seeds.hd62!()` fails because the Repo isn't started; use the wrapper:

```sh
sudo docker compose exec app bin/polticool eval 'Polticool.Release.seed()'
```

**Manual `docker compose up -d`:** run `sudo docker compose pull app` first. The compose file
falls back to the `:latest` tag, and the cached `:latest` on the server can be older than the
deployed SHA image.

**Record the cached research run** (about 70 Anthropic calls; `--skip-ingest` equivalent is
`skip_ingest: true`, which uses bills already in the database instead of le.utah.gov):

```sh
cd /opt/polticool
sudo docker compose exec app bin/polticool eval 'Polticool.Release.record_research("THURSNK", skip_ingest: true)'
```

It prints the saved path, message count, and the final grade, bars and counts.

**Where the recording lives.** It is written to `/app/research_cache/THURSNK.etf` inside the
`research_cache` named volume (`RESEARCH_CACHE_DIR`), which survives redeploys. Cached mode
(`RESEARCH_MODE=cached` in `.env`) reads the volume first and falls back to the file committed
under `priv/research_cache/`. To commit the recording:

```sh
cd /opt/polticool
sudo docker compose cp app:/app/research_cache/THURSNK.etf ./
# then scp it off the server to priv/research_cache/THURSNK.etf in the repo and commit
```

**First deploy of the volume:** the new `research_cache` volume is only created when the
compose file changes are applied, so after the deploy run `sudo docker compose up -d`
(the deploy workflow already does this on each push, but run it by hand if you copied
`docker-compose.yml` yourself).
