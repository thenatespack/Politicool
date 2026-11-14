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
