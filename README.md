# omarchy-on-cachyos

Turns a fresh **CachyOS + Hyprland** install into the **Omarchy** desktop (bar,
menus, themes, keybindings, lock screen, web apps) with my own settings on top.
CachyOS stays in charge of the kernel, bootloader and package repos, so the
system keeps CachyOS's speed.

## Fresh install

1. Install CachyOS and pick **Hyprland** as the desktop.
2. Log in, open a terminal, then:

   ```sh
   git clone https://github.com/abd-farooqi/omarchy-on-cachyos ~/Projects/omarchy-on-cachyos
   cd ~/Projects/omarchy-on-cachyos
   ./setup.sh
   ```

3. Answer the questions. After that it asks for the sudo password **once** and
   runs on its own.
4. Reboot and log in on the tuigreet screen.

The password is not stored anywhere. sudo keeps it cached for the run and the
script refreshes that cache in the background until it finishes.

## Commands

| Command | What it does |
|---|---|
| `./setup.sh` | Ask the questions, then run every step. Re-running skips steps that already finished. |
| `./setup.sh update` | Get the newest Omarchy release, install new packages it needs, re-apply patches, run the health check. |
| `./setup.sh doctor` | Health check. `doctor --fix` re-runs the steps that repair what failed. |
| `./setup.sh capture` | After tweaking configs on the live system, copy them back into this repo. Then commit. |
| `./setup.sh report` | Write a debug report to `~/` (no passwords, emails hidden), ready to paste to Claude or an issue. |
| `./setup.sh steps` | List the steps and which are done. |
| `./setup.sh rollback-omarchy` | Go back to the Omarchy release from before the last update. |

Options: `--only a,b`, `--from step`, `--force`, `--reconfigure`, `--dry-run`, `--yes`.

## When something fails

Each step runs on its own. When one fails, the script:

1. shows the file, line and command that failed,
2. reads the step's log and says what the error means (stale pacman lock, bad
   keyring, broken mirror, file conflicts, failed AUR build, full disk, …),
3. applies the fix it knows for that error (removes the stale lock, refreshes the
   keyrings, re-ranks mirrors, …) and retries once,
4. otherwise asks: **r**etry, **s**kip, show the **l**ast log lines, or **a**bort.

A package that can't be found or built does not stop the run. It is listed at
the end, and `./setup.sh --only packages` retries it.

Logs live in `~/.local/state/omarchy-on-cachyos/runs/<time>/`: `setup.log`,
one log per step under `steps/`, `warnings.txt`, `package-failures.tsv`, and
`backup/` with every file the run replaced, at its original path.

Before changing anything it takes a snapper snapshot, which the CachyOS GRUB
menu can boot.

## How it stays future-proof

- **Always the newest Omarchy.** It reads Omarchy's own package index
  (`pkgs.omarchy.org`), downloads the latest `omarchy` and `omarchy-settings`,
  and checks each download against its sha256. Nothing is pinned.
- **Omarchy's own package list.** Packages come from the list inside the
  Omarchy release just downloaded, plus Omarchy's declared dependencies, minus
  `packages/omarchy-exclude.txt`. When Omarchy adds a package, it gets installed.
- **Packages that move.** Each name is looked up in CachyOS/Arch repos, then
  Omarchy's repo, then the AUR. A renamed package becomes a warning, not a crash.
- **Patches check themselves.** Each file in `patches/` says whether it is still
  needed, already applied, or no longer fits because Omarchy changed that code.
  It never forces a change onto code it doesn't recognise.
- **Layout check.** If a new Omarchy release reorganises its files, the core
  step stops *before* touching the installed version.
- **One-step rollback** to the previous Omarchy release.

## Why not just install the `omarchy` package?

The `omarchy` and `omarchy-settings` packages replace the bootloader (Limine),
the login screen (SDDM), Plymouth, `/etc/os-release` and several other `/etc`
files, and add boot hooks. On CachyOS that fights CachyOS's own setup. This repo
installs only the desktop layer: Omarchy's files go to
`~/.local/share/omarchy`, its commands to `~/.local/bin`, and
`/usr/share/omarchy` is a link to that folder.

## Layout

```
setup.sh               entry point (commands above)
lib/                   logging + sudo, package resolver, Omarchy repo reader,
                       patch runner, doctor, error diagnosis
steps/NN-name.sh       the steps, in order (# desc: is the title)
packages/*.txt         package groups; omarchy-exclude.txt filters Omarchy's list
overrides/home/        my configs, copied over Omarchy's defaults (mirrors $HOME)
templates/             configs generated from the answers (*.tmpl, @@VAR@@)
patches/               small fixes for running Omarchy from $HOME
optional/              pieces copied only when chosen (Discord autostart)
```

### Changing things

- **New app:** add it to the right `packages/*.txt`.
- **Changed a config on the live system:** `./setup.sh capture`, then commit.
- **New config file to manage:** put it under `overrides/home/` at its path relative to `~`.
- **New known error:** add a case to `lib/diagnose.sh`.
- **New health check:** add a `check_*` function in `lib/doctor.sh` and call it from `run_doctor`.

## Power, sleep and hibernate

- The power button opens Omarchy's power menu instead of powering off instantly.
- The lock screen gets 15 s to lock before sleep, and network drives are unmounted first.
- Hibernate (if you answer yes): a swap file in its own Btrfs subvolume
  (`/swap/swapfile`, about 60% of RAM, used only after zram), plus
  `resume=`/`resume_offset=` in `/etc/default/grub.d/90-omarchy-on-cachyos-resume.cfg`.
- Lid closed on battery: suspend, then hibernate after 3 h. On AC: suspend only.
- Critical battery: hibernate instead of suspend.
- thermald on Intel laptops, as Omarchy does.

To undo hibernate: remove the swap line from `/etc/fstab`, `sudo swapoff /swap/swapfile`,
delete the GRUB drop-in and run `sudo grub-mkconfig -o /boot/grub/grub.cfg`, then delete
`/etc/systemd/logind.conf.d/30-lid-suspend-then-hibernate.conf` and
`/etc/UPower/UPower.conf.d/10-critical-hibernate.conf`.

## Things it does not do

- Install CachyOS or partition disks.
- Sign in to apps or restore browser profiles, keyrings, SSH keys or app data.
  The end of the run prints a checklist.
- Run Omarchy's first-run provisioning. It is skipped on purpose, because it
  would make Chromium the default browser and run hooks meant for a full Omarchy
  install.
