# GEO Analysis and Scoring Agents

This is a local agent.d-backed webapp for multi-agent GEO analysis and AI ranking improvement work. It supports URL scans, pasted/rendered HTML, uploaded website files, and local project-path scans.

## Run

The root launchers install the matching `agent.d` release into this repo's `bin/` folder on first run, then start the daemon with this repo's init and grants. If `bin/daemon` or `bin/daemon.exe` already exists, the download step is skipped.

Downloaded releases:

| Platform | Archive |
|---|---|
| macOS Apple Silicon | [agentd-aarch64-macos.tar.gz](https://github.com/podofun/agent.d/releases/download/v0.3.0-alpha/agentd-aarch64-macos.tar.gz) |
| Linux x86_64 | [agentd-x86_64-linux.tar.gz](https://github.com/podofun/agent.d/releases/download/v0.3.0-alpha/agentd-x86_64-linux.tar.gz) |
| Windows x86_64 | [agentd-x86_64-windows.zip](https://github.com/podofun/agent.d/releases/download/v0.3.0-alpha/agentd-x86_64-windows.zip) |

### macOS

Run from the project root:

```bash
git clone https://github.com/Chi12346568/geo-analysis
cd geo-analysis
chmod +x ./run.sh
./run.sh
```

### Linux

Run from the project root:

```bash
git clone https://github.com/Chi12346568/geo-analysis
cd geo-analysis
chmod +x ./run.sh
./run.sh
```

### Windows

Run from PowerShell in the project root:

```powershell
git clone https://github.com/Chi12346568/geo-analysis
cd geo-analysis
.\run.ps1
```

If every AI action fails on Windows, first confirm the key is saved:

```powershell
.\bin\agentctl.exe call secrets.openai_status --result-only
```

Then confirm Windows can reach OpenAI. A `401 Unauthorized` response is OK for
this check because it proves HTTPS reached the API without sending a key:

```powershell
curl.exe -I https://api.openai.com/v1/models
```

If the curl command cannot connect, check VPN, corporate proxy, firewall, DNS,
and Windows TLS/certificate inspection settings for `api.openai.com`.

If only "Get AI recommendation" fails with `provider transport` or
`error sending request for url (https://api.openai.com/v1/chat/completions)`,
restart the daemon after updating this repo. That feature sends project files to
the model, and the request is now capped to a smaller prioritized file set.

The launcher binds to `127.0.0.1:7777` and passes `--no-auth` by default
because `site/index.html` is a static browser page; browser WebSocket clients
cannot attach the daemon's `Authorization: Bearer ...` handshake header.

Then open:

```text
site/index.html
```

The page talks to `ws://127.0.0.1:7777/ws` by default.

## Links
- [agent.d](https://github.com/podofun/agent.d)