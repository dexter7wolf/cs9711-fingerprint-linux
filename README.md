# Chipsailing CS9711 Fingerprint Reader — Linux Installer

Make the **Chipsailing CS9711** USB fingerprint reader (USB ID `2541:0236`) work on
Linux with `fprintd` / PAM — **without overwriting your distribution's `libfprint`**.

```
Bus 0xx Device 0xx: ID 2541:0236 Chipsailing CS9711Fingprint
```

This sensor is **not supported by stock `libfprint`**. Its Windows driver ships a
closed-source matching DLL (`CSAlgDll.dll`) and a Microsoft WBDI/WinUSB user-mode
driver — none of which can be used on Linux. The CS9711 is a **match-on-host**
device: the sensor only streams a raw image and all matching happens in software,
so an open-source driver is possible. The community already wrote one as a
`libfprint` fork; this repo just builds and wires it up cleanly.

## What the installer does

- Installs build dependencies (Debian/Ubuntu/Mint).
- Clones the [`archeYR/libfprint-CS9711`](https://github.com/archeYR/libfprint-CS9711)
  fork (branch `cs9711-rebase`), which contains the `cs9711` driver + the `sigfm`
  matcher.
- Builds **only** the `cs9711` driver into an **isolated prefix** `/opt/libfprint-cs9711`.
  Your distro's `libfprint` is left untouched.
- Points the `fprintd` daemon at the isolated build via a **reversible** systemd
  override (`LD_LIBRARY_PATH`).
- Adds a polkit rule so users in the `sudo` group can enroll/verify their own prints.
- Optional: exposes the library system-wide so graphical settings tools also detect
  the sensor (`--with-gui`).

Everything is reversible with `--uninstall`.

## Requirements

- A Debian/Ubuntu-based distribution (developed/tested on **Linux Mint 22.x**,
  Ubuntu 24.04 base).
- `sudo` access. ~300 MB of packages (mostly OpenCV, required by the matcher).

## Install

```bash
git clone https://github.com/dexter7wolf/cs9711-fingerprint-linux.git
cd cs9711-fingerprint-linux
sudo bash install-cs9711.sh
```

Then enroll a finger. **Important:** the CS9711 needs roughly **15 presses** to
complete an enrollment — keep pressing (lifting fully between presses, varying the
fingertip position) until you see `enroll-completed`:

```bash
fprintd-enroll      # press ~15x until "enroll-completed"
fprintd-verify      # should print "verify-match"
```

Enable fingerprint login / `sudo`:

```bash
sudo pam-auth-update   # tick "Fingerprint authentication", confirm
```

### Graphical settings don't see the sensor?

The `fprintd` daemon (used by `fprintd-*` and PAM) loads our isolated build and
works out of the box. Some **GUI** tools link `libfprint` *directly* and therefore
load the distro library instead. To make those detect the sensor too:

```bash
sudo bash install-cs9711.sh --with-gui
```

This adds an `/etc/ld.so.conf.d` entry so every consumer loads the CS9711 build.
ABI-compatible (same soname), and still removable via `--uninstall`.

## Uninstall

```bash
sudo bash install-cs9711.sh --uninstall
```

Removes the isolated build, the systemd override, the polkit rule and the optional
system-wide entry, and restores the distro `libfprint`. Enrolled prints in
`/var/lib/fprint` are left in place (delete manually if you want a clean slate).

## After a kernel / distro upgrade

If a `libfprint`/`fprintd` update ever breaks detection, just re-run:

```bash
sudo bash install-cs9711.sh
```

## Troubleshooting

| Symptom | Fix |
| --- | --- |
| `NoEnrolledPrints` after enrolling | Enrollment didn't finish — re-run `fprintd-enroll` and keep pressing until `enroll-completed` (~15 presses). |
| `PermissionDenied: Not Authorized` | The polkit rule is installed by the script. If you're on SSH/a bare TTY, run from a desktop session, or make sure your user is in the `sudo` group. |
| `No devices available` | Check the daemon picked up the override: `systemctl show fprintd -p Environment` should list `/opt/libfprint-cs9711/...`. Then `systemctl restart fprintd`. |
| GUI still says "no compatible device" | Run with `--with-gui` (see above). |

## Security note

The driver fork's author states it should not be used for anything serious without
serious testing. It's fine for convenience (desktop login, `sudo`), **not** for
high-security authentication.

## Credits

- [`archeYR/libfprint-CS9711`](https://github.com/archeYR/libfprint-CS9711) — maintained driver fork.
- [`ddlsmurf/libfprint-CS9711`](https://github.com/ddlsmurf/libfprint-CS9711) — original CS9711 driver.
- The [`sigfm`](https://gitlab.freedesktop.org/libfprint/libfprint/-/merge_requests/530) image-matching MR for libfprint.
- The [fprint / libfprint](https://fprint.freedesktop.org/) project.

This repository only contains the installer script that ties those together. All
fingerprint-driver credit belongs to the projects above.

## License

MIT — see [LICENSE](LICENSE). (Applies to the installer script in this repo only;
the upstream libfprint fork is LGPL-2.1+.)

---

## About

Maintained by **Andrea Armeni**.

I run **LocalBOOM** — digital marketing for **local businesses**: local SEO,
Google Business Profile optimization, websites, and content that helps shops,
restaurants and service providers get found by nearby customers and turn searches
into walk-ins and bookings.

<!-- TODO: add your real links, e.g. -->
<!-- Website: https://your-domain.example  ·  Contact: andrea.armeni@gmail.com -->>

If this saved you an afternoon of fighting with `libfprint`, a ⭐ on the repo is
appreciated. Found a bug or got it working on another distro? Open an issue or PR.
