#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$ROOT/bin"
DAEMON="$BIN_DIR/daemon"
AGENTD_VERSION="v0.3.0-alpha"

download() {
  local url="$1"
  local output="$2"

  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 -o "$output" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$output" "$url"
  else
    printf 'curl or wget is required to download agent.d.\n' >&2
    exit 1
  fi
}

release_url() {
  local os
  local arch

  os="$(uname -s)"
  arch="$(uname -m)"

  case "$os:$arch" in
    Darwin:arm64|Darwin:aarch64)
      printf 'https://github.com/podofun/agent.d/releases/download/%s/agentd-aarch64-macos.tar.gz\n' "$AGENTD_VERSION"
      ;;
    Linux:x86_64|Linux:amd64)
      printf 'https://github.com/podofun/agent.d/releases/download/%s/agentd-x86_64-linux.tar.gz\n' "$AGENTD_VERSION"
      ;;
    *)
      printf 'Unsupported platform for automatic agent.d download: %s %s\n' "$os" "$arch" >&2
      printf 'Install agent.d manually into %s.\n' "$BIN_DIR" >&2
      exit 1
      ;;
  esac
}

install_agentd() {
  local tmp
  local archive
  local url

  mkdir -p "$BIN_DIR"
  tmp="$(mktemp -d)"
  archive="$tmp/agentd.tar.gz"
  url="$(release_url)"

  trap 'rm -rf "$tmp"' RETURN

  printf 'Downloading agent.d %s...\n' "$AGENTD_VERSION"
  download "$url" "$archive"

  tar -xzf "$archive" -C "$tmp"
  install -m 0755 "$tmp/daemon" "$BIN_DIR/daemon"
  install -m 0755 "$tmp/agentctl" "$BIN_DIR/agentctl"
}

if [[ ! -x "$DAEMON" ]]; then
  install_agentd
fi

exec "$DAEMON" \
  --init "$ROOT/agents/init.lua" \
  --grants-file "$ROOT/agents/grants.toml" \
  --trace-file "$ROOT/agentd-trace.jsonl" \
  --addr 127.0.0.1:7777 \
  --no-auth
