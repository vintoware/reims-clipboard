# reims-clipboard

Shares the clipboard between a Linux desktop (Wayland) and a macOS VM over SSH. Text only.

It was written for a macOS guest that [reims-vgpu](https://github.com/steelbrain/reims-vgpu)'s
`reims-ctl` runs under KVM on Apple silicon with Asahi Linux. reims-vgpu's window has no clipboard
sharing, and macOS has no SPICE agent. It works with any macOS VM whose SSH the host can reach.

## How it works

- **Host to Mac:** `wl-paste --watch` runs the bridge on every host copy, which pipes the text to
  `pbcopy` in the guest.
- **Mac to host:** every second the bridge hashes the guest's clipboard (`pbpaste | md5`). When the
  hash changes it fetches the text and gives it to `wl-copy`.
- **No echo:** it keeps the hash of the last text synced in either direction, so a synced copy is
  not sent back.
- **One SSH connection** (`ControlMaster`) carries every call, with a key used only by the bridge.
- **Passwords stay on the host:** a copy that a KDE password manager marks
  (`x-kde-passwordManagerHint`) is not sent to the guest.
- **VM off:** a host copy is skipped (about 8 ms, since nothing answers), and the bridge retries
  every 5 s. When the guest answers again, it gets the host's current clipboard.

It runs as a systemd user service that starts with the desktop session
(`graphical-session.target`).

## Requirements

- **Host:** Linux with a Wayland session, `wl-clipboard`, `openssh-clients` and systemd.
  Tested on Fedora Asahi Remix 45 with KDE Plasma 6.
- **Guest:** macOS with **Remote Login** on. Tested on macOS 27.2.1.
- **The guest's SSH forwarded to the host's `127.0.0.1:10022`.** With `reims-ctl`:

  ```sh
  reims-ctl set <vm> --ssh-port 10022   # applies at the VM's next start
  ```

  With plain QEMU, add `hostfwd=tcp:127.0.0.1:10022-:22` to the user-mode `-netdev`.

## Setup

1. **In the Mac:** System Settings › General › Sharing › turn on **Remote Login**.
2. **On the host**, with the VM running and its SSH forwarded:

   ```sh
   git clone https://github.com/vintoware/reims-clipboard.git
   cd reims-clipboard
   ./install.sh
   ```

   This installs `~/.local/bin/reims-clipboard` and
   `~/.config/systemd/user/reims-clipboard.service`, and makes the bridge's key
   `~/.ssh/reims-macos` if there is none. It prints the `ssh-copy-id` command that puts the key in
   the guest; that asks for the Mac user's password once.
3. Run `./install.sh` again. Once the key works, it enables and starts the service.

A guest user other than `user`, or another port:

```sh
REIMS_CLIP_USER=alice REIMS_CLIP_PORT=2222 ./install.sh
```

This goes into a systemd drop-in (`reims-clipboard.service.d/guest.conf`), so the unit file stays
as shipped.

## Use

Copy on one side and paste on the other. Host copies reach the Mac at once; Mac copies reach the
host within about a second.

```sh
journalctl --user -u reims-clipboard -f              # what it does
systemctl --user restart reims-clipboard             # after changing the script or settings
systemctl --user disable --now reims-clipboard       # turn it off
```

Settings, all optional, as environment variables of the service (`systemctl --user edit
reims-clipboard`): `REIMS_CLIP_HOST` (127.0.0.1), `REIMS_CLIP_PORT` (10022), `REIMS_CLIP_USER`
(user), `REIMS_CLIP_KEY` (~/.ssh/reims-macos), `REIMS_CLIP_POLL` (1, seconds between checks of the
guest).

## Limits

- Text only: images and files are not synced.
- Copies made on the host while the VM is off are not queued; the guest gets the latest when it
  is back.
- When the bridge reconnects, the host's clipboard wins over the guest's.
- While macOS boots, a host copy can wait up to 3 s in the background for SSH to answer.

## Files it creates

| Path | What |
| --- | --- |
| `~/.local/bin/reims-clipboard` | the bridge |
| `~/.config/systemd/user/reims-clipboard.service` | its user unit, and its enable link |
| `~/.ssh/reims-macos`, `~/.ssh/reims-macos.pub` | the bridge's own SSH key |
| `~/.ssh/reims-macos.known_hosts` | the guest's host key, apart from your `known_hosts` |
| `$XDG_RUNTIME_DIR/reims-clipboard/` | its state: the last hash and the SSH control socket |

In the guest, `ssh-copy-id` adds the key to the user's `~/.ssh/authorized_keys`.

## Uninstall

```sh
systemctl --user disable --now reims-clipboard
rm -f ~/.local/bin/reims-clipboard ~/.config/systemd/user/reims-clipboard.service
rm -rf ~/.config/systemd/user/reims-clipboard.service.d
rm -f ~/.ssh/reims-macos ~/.ssh/reims-macos.pub ~/.ssh/reims-macos.known_hosts
systemctl --user daemon-reload
```

Then remove the `reims-clipboard-bridge` line from `~/.ssh/authorized_keys` in the Mac.
