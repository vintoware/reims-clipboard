#!/usr/bin/env bash
# Installs the clipboard bridge for the current user: the script into ~/.local/bin, the systemd
# user unit into ~/.config/systemd/user, and an SSH key for the bridge alone (~/.ssh/reims-macos)
# where there is none. It then says how to put the key in the guest, and enables the unit once
# the key works. Nothing in the guest is changed (README.md, "Setup").
#
# usage: ./install.sh [-f]
#   -f  replace an installed script or unit that differs from this checkout's
# env:  REIMS_CLIP_PORT (10022), REIMS_CLIP_USER (user): the guest's SSH port and user, used to
#       check the key and given to the unit where they differ from the defaults
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
force=0
[[ ${1:-} == -f ]] && force=1
PORT=${REIMS_CLIP_PORT:-10022}
GUEST_USER=${REIMS_CLIP_USER:-user}
KEY=$HOME/.ssh/reims-macos
BIN=$HOME/.local/bin/reims-clipboard
UNIT_DIR=$HOME/.config/systemd/user
UNIT=$UNIT_DIR/reims-clipboard.service

die() { echo "install: $*" >&2; exit 2; }
say() { echo "install: $*"; }

[[ $(uname -s) == Linux ]] || die "the bridge runs on a Linux host"
for t in ssh ssh-keygen wl-paste wl-copy md5sum systemctl; do
  command -v "$t" > /dev/null || die "needs $t (Fedora: sudo dnf install openssh-clients wl-clipboard)"
done
[[ ${XDG_SESSION_TYPE:-} == wayland ]] || say "warning: this session is not Wayland (${XDG_SESSION_TYPE:-unknown}); the bridge uses wl-clipboard"

# place SRC DEST MODE: copy SRC to DEST, refusing to replace a different file without -f.
place() {
  local src=$1 dest=$2 mode=$3
  if [[ -e $dest ]] && ! cmp -s "$src" "$dest"; then
    ((force)) || die "$dest differs from $src: rerun with -f to replace it"
  fi
  install -D -m "$mode" "$src" "$dest"
  say "installed $dest"
}
place "$here/reims-clipboard" "$BIN" 0755
place "$here/reims-clipboard.service" "$UNIT" 0644

# A port or user other than the defaults goes into a drop-in, so the unit file stays as shipped.
if [[ $PORT != 10022 || $GUEST_USER != user ]]; then
  mkdir -p "$UNIT_DIR/reims-clipboard.service.d"
  printf '[Service]\nEnvironment=REIMS_CLIP_PORT=%s REIMS_CLIP_USER=%s\n' "$PORT" "$GUEST_USER" \
    > "$UNIT_DIR/reims-clipboard.service.d/guest.conf"
  say "the unit uses port $PORT and user $GUEST_USER (reims-clipboard.service.d/guest.conf)"
fi
systemctl --user daemon-reload

if [[ ! -f $KEY ]]; then
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  ssh-keygen -q -t ed25519 -N '' -C 'reims-clipboard-bridge' -f "$KEY"
  say "made the bridge's SSH key, $KEY"
fi

if ssh -p "$PORT" -i "$KEY" -o BatchMode=yes -o IdentitiesOnly=yes -o ConnectTimeout=5 \
  -o UserKnownHostsFile="$HOME/.ssh/reims-macos.known_hosts" -o StrictHostKeyChecking=accept-new \
  "$GUEST_USER@127.0.0.1" true 2> /dev/null; then
  systemctl --user enable --now reims-clipboard.service
  say "the key works: reims-clipboard.service is enabled and running"
else
  cat << EOF
install: the guest did not take the key yet. With the VM running, Remote Login on in it, and
install: its SSH forwarded to port $PORT (reims-ctl set <vm> --ssh-port $PORT), run once:

  ssh-copy-id -i $KEY.pub -p $PORT -o UserKnownHostsFile=$HOME/.ssh/reims-macos.known_hosts \\
    -o StrictHostKeyChecking=accept-new $GUEST_USER@127.0.0.1

install: then run ./install.sh again to enable the bridge.
EOF
fi
