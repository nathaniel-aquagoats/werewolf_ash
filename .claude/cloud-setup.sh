#!/usr/bin/env bash
# Setup script for the claude.ai cloud environment that runs the bead pipeline.
#
# THIS FILE IS NOT RUN FROM THE REPO. It is kept here for review and history;
# the live copy is pasted into the environment's "Setup script" field at
# claude.ai/code -> cloud icon -> edit environment. Edit both together.
#
# It runs once per environment and the resulting filesystem is snapshotted, so
# later sessions start with everything below already installed. Processes are
# NOT snapshotted: Postgres is started per session by .claude/hooks/session-start.sh.
#
# DESIGN NOTE, learned the hard way: this script NEVER fails. A non-zero exit
# aborts the session before it starts, so the only evidence left is a truncated
# line in the routine run log — which is not enough to debug anything. Instead
# every step is guarded, everything is teed to /var/log/werewolf-setup.log, and
# the script always exits 0. A broken environment then produces a *session* you
# can interrogate, and the probe reads the log. Verify with:
#   tail -100 /var/log/werewolf-setup.log; grep -n 'STEP FAILED' /var/log/werewolf-setup.log
#
# REQUIRED environment setting: Network access -> Custom, with the default
# package-manager list included, plus these two domains:
#   repo.hex.pm     (mix deps.get)
#   builds.hex.pm   (precompiled Erlang/OTP)
# The stock Trusted list only allows hex.pm itself, which is not enough.
#
# The egress proxy terminates TLS with its own certificate authority. That
# authority is in the system trust store, so curl and Mix's own downloader are
# fine, but Hex ships its own CA bundle and fails with "Unknown CA" until it is
# pointed at the system store. See the hex.config call below.

set -uo pipefail

LOG=/var/log/werewolf-setup.log
mkdir -p /var/log
exec > >(tee -a "$LOG") 2>&1

OTP_VERSION=29.0.6
ELIXIR_VERSION=1.20.4
GH_VERSION=2.100.0
REPO_DIR=/home/user/werewolf_ash

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export NEEDRESTART_SUSPEND=1
# The image's default locale is latin1, which Elixir warns will make it
# malfunction. C.UTF-8 is built into glibc and needs no locale package.
export LANG=C.UTF-8
export LC_ALL=C.UTF-8

# The egress proxy's own CA bundle if the platform provides one, else the
# system store. Confirmed 2026-09-12: the platform ships /root/.ccr/ca-bundle.crt
# and exports HEX_CACERTS_PATH pointing at it.
if [ -f /root/.ccr/ca-bundle.crt ]; then
  CA_BUNDLE=/root/.ccr/ca-bundle.crt
else
  CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
fi

FAILED=""
step() {
  echo ""
  echo "==> $1"
  shift
  if "$@"; then
    return 0
  fi
  local rc=$?
  echo "STEP FAILED (rc=$rc): $*"
  FAILED="${FAILED}${FAILED:+, }$1"
  return 0
}

apt_install() {
  apt-get install -y -qq --no-install-recommends \
    -o Dpkg::Options::=--force-confold \
    -o Dpkg::Options::=--force-confdef \
    "$@"
}

park_foreign_apt_sources() {
  # The base image ships third-party PPAs (deadsnakes, ondrej/php) whose hosts
  # sit outside this environment's egress allowlist. apt-get update exits 100
  # when it cannot reach them, so park every source that is not Ubuntu's own.
  mkdir -p /etc/apt/disabled-sources
  local src
  for src in /etc/apt/sources.list.d/*; do
    [ -e "$src" ] || continue
    case "$(basename "$src")" in
    ubuntu.sources | ubuntu.list) ;;
    *) mv "$src" /etc/apt/disabled-sources/ || true ;;
    esac
  done
  apt-get update -qq
}

step "park foreign apt sources and update" park_foreign_apt_sources

# Split the installs: one failing package should not cost us the rest, and the
# log then names exactly which group broke.
step "apt: base tools" apt_install unzip curl ca-certificates
step "apt: erlang runtime libs" apt_install libssl3 libncurses6 libsctp1 libodbc2
step "apt: postgres" apt_install postgresql-16 postgresql-client-16

echo ""
echo "==> trust store after apt"
ls -la /etc/ssl/certs/ca-certificates.crt 2>&1 | tail -2
grep -c 'BEGIN CERTIFICATE' /etc/ssl/certs/ca-certificates.crt 2>/dev/null |
  sed 's/^/certificates in bundle: /'
ls -la /usr/local/share/ca-certificates/ 2>&1 | tail -5

install_otp() {
  mkdir -p /usr/local/otp
  curl -fsSL "https://builds.hex.pm/builds/otp/amd64/ubuntu-24.04/OTP-${OTP_VERSION}.tar.gz" |
    tar -xz -C /usr/local/otp --strip-components=1 || return 1
  (cd /usr/local/otp && ./Install -minimal /usr/local/otp) || return 1
  local bin
  for bin in erl erlc escript dialyzer typer ct_run run_erl to_erl; do
    if [ -f "/usr/local/otp/bin/$bin" ]; then
      ln -sf "/usr/local/otp/bin/$bin" "/usr/local/bin/$bin"
    fi
  done
}
step "Erlang/OTP ${OTP_VERSION}" install_otp

install_elixir() {
  curl -fsSL -o /tmp/elixir.zip \
    "https://github.com/elixir-lang/elixir/releases/download/v${ELIXIR_VERSION}/elixir-otp-29.zip" || return 1
  rm -rf /usr/local/elixir
  mkdir -p /usr/local/elixir
  unzip -q /tmp/elixir.zip -d /usr/local/elixir || return 1
  rm -f /tmp/elixir.zip
  local bin
  for bin in elixir elixirc iex mix; do
    ln -sf "/usr/local/elixir/bin/$bin" "/usr/local/bin/$bin"
  done
}
step "Elixir ${ELIXIR_VERSION}" install_elixir

install_gh() {
  curl -fsSL -o /tmp/gh.deb \
    "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.deb" || return 1
  apt-get install -y -qq /tmp/gh.deb || return 1
  rm -f /tmp/gh.deb
}
step "gh ${GH_VERSION}" install_gh

start_postgres() {
  pg_ctlcluster 16 main start || service postgresql start || true
  local i
  for i in $(seq 1 30); do
    if pg_isready -h localhost -q; then
      break
    fi
    sleep 1
  done
  pg_isready -h localhost || return 1
  su - postgres -c "psql -qc \"ALTER USER postgres WITH PASSWORD 'postgres';\""
}
step "Postgres role" start_postgres

persist_env() {
  # Processes are not snapshotted but the filesystem is, so persist three ways:
  # PAM reads /etc/environment, login shells read profile.d, and the session's
  # own non-login bash reads .bashrc.
  # Written with printf rather than a heredoc on purpose: this script is pasted
  # into a web form, and a heredoc whose terminator gets mangled swallows the
  # rest of the file and bash dies with a syntax error (exit 2).
  #
  # HEX_CACERTS_PATH is deliberately NOT forced here. The platform sets it to
  # its own proxy bundle (/root/.ccr/ca-bundle.crt, confirmed 2026-09-12) and
  # that value is the correct one; hardcoding ours would override it in any
  # session where this file wins. Only fill it in if nothing else has.
  printf '%s\n' \
    'export LANG=C.UTF-8' \
    'export LC_ALL=C.UTF-8' \
    'export ELIXIR_ERL_OPTIONS="+fnu"' \
    ': "${HEX_CACERTS_PATH:=$CA_BUNDLE}"' \
    'export HEX_CACERTS_PATH' \
    >/etc/profile.d/elixir.sh
  sed -i "s#\$CA_BUNDLE#${CA_BUNDLE}#" /etc/profile.d/elixir.sh
  chmod 0644 /etc/profile.d/elixir.sh
  local line
  for line in 'LANG=C.UTF-8' 'LC_ALL=C.UTF-8' 'ELIXIR_ERL_OPTIONS=+fnu'; do
    grep -qxF "$line" /etc/environment 2>/dev/null || echo "$line" >>/etc/environment
  done
  grep -qxF '. /etc/profile.d/elixir.sh' /root/.bashrc 2>/dev/null ||
    echo '. /etc/profile.d/elixir.sh' >>/root/.bashrc
}
step "persist shell environment" persist_env

setup_hex() {
  cd "$REPO_DIR" || return 1
  mix local.hex --force || return 1
  mix local.rebar --force || return 1
  # Hex verifies repo.hex.pm against its own bundled CA list, which does not
  # include the egress proxy's authority. Writing to ~/.hex/hex.config makes it
  # survive the snapshot; an ambient HEX_CACERTS_PATH still takes precedence,
  # which is what we want.
  export HEX_CACERTS_PATH="${HEX_CACERTS_PATH:-$CA_BUNDLE}"
  echo "using CA bundle: $HEX_CACERTS_PATH"
  mix hex.config cacerts_path "$HEX_CACERTS_PATH"
}
step "hex" setup_hex

warm_build() {
  cd "$REPO_DIR" || return 1
  mix deps.get || return 1
  MIX_ENV=test mix compile
}
step "warm the Elixir build" warm_build

echo ""
echo "==> versions"
erl -noshell -eval 'io:format("OTP ~s~n", [erlang:system_info(otp_release)]), halt().' 2>&1 | tail -1
elixir --version 2>&1 | tail -1
psql --version 2>&1
gh --version 2>&1 | head -1

echo ""
if [ -n "$FAILED" ]; then
  echo "==> SETUP FINISHED WITH FAILED STEPS: $FAILED"
  echo "    Full log: $LOG"
else
  echo "==> setup complete, all steps OK"
fi

# Always succeed. A failed setup script means no session and no way to debug.
exit 0
