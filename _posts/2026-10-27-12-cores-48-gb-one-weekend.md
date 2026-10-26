---
title: "12 Cores, 48 GB, One Weekend"
date: 2026-10-27 05:00:00 -0700
tags: [homelab, self-hosting, vps, tailscale, docker, plex, security]
---

I paid $56 for a year of a KVM VPS with 12 CPU cores, about 48 GB of RAM, around 700 GB of disk, and nested virtualization switched on. I'm not going to quote a hyperscaler price, because it'll be stale by the time you read this. Price an instance with those specs by the month and do the arithmetic yourself. It's many times more. Mine works out to under five dollars a month.

By Sunday night it was running Plex, a torrent client that physically can't leak my server's IP, and a browser-based file manager, and almost none of it was reachable from the public internet. This post is the order I'd do it in if you've never self-hosted, plus the places it went sideways, which is the part most guides leave out. If you do this for a living, skip ahead to the traps. That's where the security details are.

## Why a VPS and not a box in the closet

I already run Plex at home, so this wasn't about Plex. I wanted a machine with a real uplink and a stable public address, no fan noise, and nested virtualization, so I can run VMs inside it later for pentest labs (authorized engagements only, with a written scope).
The honest downsides: the provider's hypervisor can see everything on this box, so I don't put anything on it I'd be wrecked to lose to them. There's no GPU, so transcoding is CPU only. And 700 GB is a lot until it's a media library. Know those going in.

## Security first (about 30 minutes)

Before anything fun, I patched, created a non-root user, and locked the door:

```bash
sudo apt update && sudo apt full-upgrade -y
sudo apt install -y unattended-upgrades ufw fail2ban
sudo dpkg-reconfigure -plow unattended-upgrades
sudo adduser --disabled-password --gecos "" admin
sudo usermod -aG sudo admin
sudo ufw default deny incoming && sudo ufw allow OpenSSH && sudo ufw enable
sudo reboot
```

I gave `admin` passwordless sudo. That's a real tradeoff: the SSH key is the only thing standing between an attacker and root. But login is key-only and root already accepts the same kind of key, so the delta is small, and I'd rather not type a password forty times a day.

The SSH config goes in a drop-in file named `00-hardening.conf`, not in `sshd_config`. sshd takes the first value it sees for a setting, and cloud-init ships a `50-cloud-init.conf` that can quietly turn password auth back on. The `00-` prefix makes mine load first:

```
# /etc/ssh/sshd_config.d/00-hardening.conf
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
AllowUsers root admin
MaxAuthTries 3
X11Forwarding no
```

Run `sudo sshd -t && sudo systemctl reload ssh`, then test from a second terminal before you close the first. Every change in this post got that treatment, because the only way to lock yourself out of a VPS is to be confident.

### Keys that never touch the disk

My SSH keys live in 1Password and get served through its SSH agent. No private key sits on the server, and none sits on my laptop either. Three Windows gotchas ate an hour:

- **Git Bash's `ssh` can't talk to the agent.** The agent listens on a Windows named pipe, and the OpenSSH that ships with Git for Windows doesn't speak it. It failed with a `libcrypto: unsupported` error. Windows' built-in OpenSSH, run from PowerShell, works.
- **Connecting to a raw IP skips your `Host` block.** The agent then offers every key it has, and the server hangs up with "Too many authentication failures." Pin the key and connect through the alias:

```
Host homelab
  HostName <server-ip>
  User admin
  IdentitiesOnly yes
  IdentityFile ~/.ssh/homelab.pub
```

If you need a different address, override only that: `ssh -o HostName=<tailscale-ip> homelab`.

- **The agent sometimes refuses to sign.** Unlock the vault or approve the prompt. It looks exactly like a network problem and isn't.

### Tailscale, so nothing private is public

I installed Tailscale so every admin page lives on a private network instead of the internet. I also made the server an exit node, which needs IP forwarding and two firewall rules:

```bash
echo 'net.ipv4.ip_forward = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
echo 'net.ipv6.conf.all.forwarding = 1' | sudo tee -a /etc/sysctl.d/99-tailscale.conf
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf
sudo ufw allow in on tailscale0
sudo ufw route allow in on tailscale0 out on <public-iface>
```

(You also approve the exit node in the Tailscale admin console. Advertising it isn't enough.) If you've got Tailnet Lock on, the node prints a scary "locked out" message until it's signed. It resolved itself once signed.

Once SSH worked over the tailnet I closed public IPv4 SSH, and then I did something I'd argue about with myself: I kept SSH open on IPv6 only, key-only, as a failsafe if Tailscale ever breaks. IPv6's address space is so big that blind scanning doesn't work the way it does on IPv4, but it's still public SSH, so it's a tradeoff, not a free lunch. The provider's reset and console tools run through the hypervisor and `qemu-guest-agent`, so they don't need port 22. Check that console actually works in your dashboard before you close the last door.

**Sidebar: Ubuntu 26.04 ships `sudo-rs` and Rust coreutils.** Some old habits behave differently. `visudo -cf <file>` complained about a sudoers file that `sudo` and plain `visudo -c` were both fine with, and a few `head`/`tail` flags errored. If a classic command misbehaves, suspect the rewrite before you suspect yourself.

## The traps that nearly got me

### Docker walks around your firewall

This is the one I most want sysadmins to take away. Docker publishes ports by inserting its own iptables rules ahead of ufw's, so `-p 8080:80` is open to the world even with ufw set to deny everything. The fix is to make localhost the default:

```json
{
  "ip": "127.0.0.1",
  "log-driver": "local",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
```

That's `/etc/docker/daemon.json`; restart Docker after. Then test it instead of trusting it:

```bash
docker run -d --rm --name test -p 8080:80 nginx
sudo ss -tlnp | grep 8080     # want 127.0.0.1:8080, not 0.0.0.0
docker stop test
```

When I want tailnet access I publish to the Tailscale IP on purpose: `-p <tailscale-ip>:8080:80`. One compose project per app under `/opt/stacks/<app>` keeps spinning up new things easy.

### I pasted a live auth key

I ran the Tailscale install with `--auth-key=tskey-...` inline, so it landed in shell history, and then I pasted the terminal output somewhere it didn't belong. I'd set the key to expire at the shortest interval Tailscale offers, so it killed itself, but I didn't know that was enough until it was. Treat any key you've pasted as burned. Revoke it in the admin console (Settings → Keys) right away, and next time use an interactive login or a one-use key with a short expiry.

### Plex said it was fine and wasn't

I started Plex, signed in, and saw only my home server, with none of the library options you'd expect. The server log had the real answer: the new server's call to plex.tv was failing with an HTTP 403, so plex.tv never listed it. The fix was to stop the container, move the config directory aside, drop the `ADVERTISE_IP` variable, and claim again with a fresh token. It registered immediately, and `ADVERTISE_IP` is staying out of my compose file. I changed two things at once, so I can't tell you which one mattered, and I'd rather say that than invent a cause.

### 46 GB used, zero processes

Right after the reboot, `free` showed 46 GB used and almost nothing available, and no process was using it. I almost opened a support ticket. Then I checked:

```bash
grep -i balloon /proc/meminfo
```

The hypervisor's virtio memory balloon was holding about 44 GB and releasing it gradually. Within roughly three minutes it hit zero and 47 GB was available. Wait a few minutes after a boot before judging RAM, and check the balloon line if memory looks wrong. While I was in there I confirmed `/dev/kvm` exists, so nested virtualization is real.

## The media pipeline

**Plex** runs in Docker with host networking, which means its ports are the host's ports and ufw gets a say again. The claim token from plex.tv/claim is only valid for about four minutes. Claim the server over the tailnet first, and only then open port 32400, otherwise a stranger could claim an unclaimed public server before you do. The media mount is read-only:

```yaml
services:
  plex:
    image: plexinc/pms-docker:latest
    network_mode: host
    environment:
      TZ: America/Los_Angeles
      PLEX_CLAIM: ${PLEX_CLAIM}
    volumes:
      - ./config:/config
      - /srv/media:/data:ro
```

Libraries point at `/data/movies`, `/data/tv`, and `/data/music`.

**qBittorrent** runs inside a VPN container. A quick note first: this is for content you're allowed to have, like your own media, public-domain and openly licensed material, and Linux ISOs. Read your VPS provider's acceptable-use policy before you start, because plenty of providers restrict torrenting.

qBittorrent shares Gluetun's network stack (`network_mode: service:gluetun`), and Gluetun's firewall blocks everything that isn't the tunnel. If the VPN drops, the torrent client goes dark instead of leaking my server's IP. That's why the web UI port is published on the Gluetun container:

```yaml
services:
  gluetun:
    image: qmcgaw/gluetun:latest
    cap_add: [NET_ADMIN]
    devices: ["/dev/net/tun:/dev/net/tun"]
    environment:
      VPN_SERVICE_PROVIDER: private internet access
      VPN_TYPE: openvpn
      OPENVPN_USER: ${PIA_USER}
      OPENVPN_PASSWORD: ${PIA_PASS}
      SERVER_REGIONS: CA Vancouver
      VPN_PORT_FORWARDING: "on"
    ports:
      - <tailscale-ip>:8080:8080
  qbittorrent:
    image: lscr.io/linuxserver/qbittorrent:latest
    network_mode: service:gluetun
    depends_on:
      gluetun: { condition: service_healthy }
```

The credentials went into a `chmod 600` `.env` file through a silent prompt, so they never hit shell history:

```bash
read -rp 'VPN user: ' U; read -rsp 'VPN pass: ' P; echo
printf "PIA_USER='%s'\nPIA_PASS='%s'\n" "$U" "$P" > .env
chmod 600 .env; unset U P
```

My first region, Toronto, died with `TLS key negotiation failed` and never connected. Forcing TCP (`OPENVPN_PROTOCOL: tcp`) worked, and so did switching to a different region. I stayed on Vancouver. Pick a region that supports port forwarding. Then I verified the thing I care about: `docker exec gluetun wget -qO- https://ipinfo.io/ip` returned the VPN's address, not the server's. (MFA on the account wasn't a problem for the OpenVPN login.)

If you're picking a provider, this is the glue Gluetun needs from them, and it's a short list:

- **Gluetun has to support them.** It ships with built-in server lists for most of the big names, and the `VPN_SERVICE_PROVIDER` value is the only line that changes. Check its wiki for your provider's exact settings.
- **They have to hand out credentials for third-party clients.** You need OpenVPN or WireGuard details, not just their app. Mine is a separate username and password. Some providers want a WireGuard private key instead, and some use an account number.
- **Port forwarding, if you want to seed properly.** Without it you can download fine but you'll be a poor peer. Some providers offer it only on certain servers, and some don't offer it at all.
- **They have to allow P2P** on the servers you pick, and have a logging policy you can live with.
- **Your VPS has to give the container a tunnel device.** That means `/dev/net/tun` and the `NET_ADMIN` capability, which is what those two lines in the compose file are for. They worked on my KVM box without anything special, but check yours.

Inside qBittorrent I changed the temporary password, bound the network interface to `tun0` as a second kill switch, set the incoming port to the one the VPN forwards, turned UPnP off, and switched to automatic torrent management with categories that map to `/downloads/<category>`.

**File Browser** closes the loop. It's a web file manager bound to the Tailscale IP and mounted on `/srv`, so I move finished downloads from `downloads/<category>` to `media/<category>` in a browser. The move is instant, because it's the same disk and the same mount, and Plex picks the files up on a library scan.

## Where it stands

**Done and verified:** baseline hardening, key-only SSH through 1Password, Tailscale with the exit node, Docker bound to localhost by default, Plex claimed and registered with libraries, qBittorrent behind a verified VPN IP, and File Browser.

**Not verified:** Plex from outside my tailnet. That needs port 32400 open. Most apps want a Plex Pass or a Remote Watch Pass for remote playback, and I have a lifetime Plex Pass, so that part is covered. I also haven't rebooted with everything running to confirm the containers bound to the Tailscale IP come back after Tailscale does.

**Planned:** Incus or libvirt for nested pentest VMs on an isolated network, Sonarr/Radarr/Prowlarr, Immich for photos, a file-sync app like Nextcloud, automatic container updates, and a script to update qBittorrent's port when the forwarded one changes. Right now I copy that number by hand.

## What it costs

| Item | Cost | Notes |
|---|---|---|
| VPS (12 cores, ~48 GB, ~700 GB) | $56/year | About $4.67 a month |
| VPN (Private Internet Access) | ~$17/year | About $50 for a 3-year plan; required for the torrent stack |
| Plex Pass (lifetime) | ~$150 one-time | Bought about ten years ago; covers remote playback on most apps |
| Tailscale | $0 | Free tailnet, with my phone and everything else on it |
| Domain (optional) | $9/year | One I already own for the blog, with DNS on Cloudflare. Not used by this server, so not in the total |
| **Total (recurring)** | **~$73/year** | About $6 a month, plus the one-time Plex Pass |

## The checklist

If you want to copy this, here's the order:

1. Buy a VPS with KVM, and nested virtualization if you want VMs later. Read its acceptable-use policy first.
2. Patch everything, enable unattended security upgrades, install `fail2ban` and `ufw`, and reboot.
3. Create a non-root user and move your SSH keys into an agent so no private key sits on disk.
4. Put SSH hardening in `/etc/ssh/sshd_config.d/00-hardening.conf`, run `sshd -t`, and test from a second session before you close the first.
5. Wait five minutes after any reboot before you trust `free`. Check the balloon line if memory looks wrong.
6. Install Tailscale with an interactive login, not a pasted key. Add the `tailscale0` ufw rules, and enable IP forwarding only if you want an exit node.
7. Close public IPv4 SSH once the tailnet works. Decide on a failsafe, and confirm your provider's console works.
8. Install Docker and set `"ip": "127.0.0.1"` in `daemon.json`. Verify with `ss -tlnp`.
9. Keep one compose project per app in `/opt/stacks/<app>`, and publish to the Tailscale IP on purpose.
10. Claim Plex over the tailnet before you open its port. If registration fails, read the server log.
11. Run your torrent client inside a VPN container, publish its UI only on the tailnet, and verify the public IP from inside the container.
12. Revoke every key you've pasted anywhere.

The thing I keep coming back to is how little of this was hard. Nearly every problem was a default doing something I hadn't asked it to: Docker bypassing the firewall, an SSH agent offering every key, a drop-in file loading in the wrong order. A cheap server and a free weekend is plenty, and I'd love for more people to try this. Keep it to media you're allowed to have (Linux ISOs, obviously), and verify each default instead of assuming it. That second part is the only one that takes discipline.
