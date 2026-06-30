#!/usr/bin/env bash
#
# install-cs9711.sh
#
# Make the Chipsailing CS9711 USB fingerprint reader (USB ID 2541:0236)
# work on Linux, WITHOUT touching your distro's libfprint.
#
# It builds the community libfprint fork that contains the cs9711 driver
# into an ISOLATED prefix (/opt/libfprint-cs9711) and points the fprintd
# daemon at it through a reversible systemd override. Nothing in the
# distribution package is overwritten.
#
#   Driver fork : https://github.com/archeYR/libfprint-CS9711  (branch cs9711-rebase)
#   Device      : Chipsailing CS9711  -  match-on-host  -  vendor-class USB
#
# Tested on Linux Mint 22.x (Ubuntu 24.04 base). Should work on any
# recent Debian/Ubuntu derivative.
#
# Usage:
#   sudo bash install-cs9711.sh            # build + install + enable for fprintd
#   sudo bash install-cs9711.sh --with-gui # also expose the lib system-wide so
#                                          # GUI tools (Settings) detect the sensor
#   sudo bash install-cs9711.sh --uninstall
#
set -euo pipefail

# --------------------------------------------------------------------------- #
PREFIX=/opt/libfprint-cs9711                  # where the isolated lib is installed
SRC=/opt/libfprint-cs9711-src                 # where the source is cloned/built
REPO=https://github.com/archeYR/libfprint-CS9711.git
BRANCH=cs9711-rebase

MULTIARCH="$(gcc -dumpmachine 2>/dev/null || echo x86_64-linux-gnu)"  # e.g. x86_64-linux-gnu
LIBDIR="$PREFIX/lib/$MULTIARCH"

OVERRIDE_DIR=/etc/systemd/system/fprintd.service.d
OVERRIDE="$OVERRIDE_DIR/10-cs9711-prefix.conf"
POLKIT_RULE=/etc/polkit-1/rules.d/50-fprint.rules
LDCONF=/etc/ld.so.conf.d/cs9711-libfprint.conf
# --------------------------------------------------------------------------- #

WITH_GUI=0
ACTION=install
for arg in "${@:-}"; do
  case "$arg" in
    --with-gui)  WITH_GUI=1 ;;
    --uninstall) ACTION=uninstall ;;
    "" ) ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done

if [[ $EUID -ne 0 ]]; then echo "Please run with sudo."; exit 1; fi

if [[ "$ACTION" == "uninstall" ]]; then
  echo ">> Uninstalling"
  rm -f "$OVERRIDE"; rmdir --ignore-fail-on-non-empty "$OVERRIDE_DIR" 2>/dev/null || true
  rm -f "$POLKIT_RULE"
  rm -f "$LDCONF"; ldconfig
  systemctl daemon-reload
  systemctl restart fprintd 2>/dev/null || true
  rm -rf "$PREFIX" "$SRC"
  echo ">> Done. Distro libfprint restored; isolated build, override, polkit rule removed."
  echo "   (Enrolled prints in /var/lib/fprint were left untouched; delete manually if wanted.)"
  exit 0
fi

echo ">> [1/7] Build dependencies"
apt-get update -qq
apt-get install -y \
  build-essential meson ninja-build pkg-config git cmake \
  libgusb-dev libnss3-dev libglib2.0-dev libgudev-1.0-dev \
  libpixman-1-dev libgnutls28-dev libsystemd-dev \
  libpolkit-gobject-1-dev libdbus-1-dev python3-pil \
  libopencv-dev doctest-dev

echo ">> [2/7] Fetch / update source ($BRANCH)"
if [[ -d "$SRC/.git" ]]; then
  git -C "$SRC" fetch --depth 1 origin "$BRANCH"
  git -C "$SRC" reset --hard "origin/$BRANCH"
else
  git clone --depth 1 -b "$BRANCH" "$REPO" "$SRC"
fi

echo ">> [3/7] Configure (isolated prefix: $PREFIX, arch: $MULTIARCH)"
cd "$SRC"
rm -rf build
meson setup build \
  --prefix="$PREFIX" \
  --libdir="lib/$MULTIARCH" \
  -Ddrivers=cs9711 \
  -Dgtk-examples=false \
  -Dintrospection=false \
  -Ddoc=false \
  -Dudev_rules=disabled \
  -Dinstalled-tests=false

echo ">> [4/7] Compile"
ninja -C build

echo ">> [5/7] Install into $PREFIX"
ninja -C build install
test -e "$LIBDIR/libfprint-2.so.2" || { echo "ERROR: build did not produce libfprint-2.so.2"; exit 1; }

echo ">> [6/7] Point fprintd at the isolated lib (reversible systemd override)"
mkdir -p "$OVERRIDE_DIR"
cat > "$OVERRIDE" <<EOF
# Added by install-cs9711.sh - makes fprintd load the CS9711 libfprint build.
# Remove this file (or run the script with --uninstall) to revert.
[Service]
Environment=LD_LIBRARY_PATH=$LIBDIR
EOF

echo ">> [7/7] Allow sudo-group users to enroll/verify (polkit rule)"
mkdir -p "$(dirname "$POLKIT_RULE")"
cat > "$POLKIT_RULE" <<'RULE'
// Allow members of the "sudo" group to manage their own fingerprints.
polkit.addRule(function(action, subject) {
    if (action.id.indexOf("net.reactivated.fprint.") === 0 &&
        subject.isInGroup("sudo")) {
        return polkit.Result.YES;
    }
});
RULE

if [[ "$WITH_GUI" -eq 1 ]]; then
  echo ">> [extra] Exposing the lib system-wide so GUI tools detect the sensor"
  echo "$LIBDIR" > "$LDCONF"
  ldconfig
fi

systemctl daemon-reload
systemctl restart fprintd

cat <<EOF

>> DONE.

   Verify fprintd loaded the right lib:
     systemctl show fprintd -p Environment
   Enroll a finger (PRESS ~15 times, lifting between, until "enroll-completed"):
     fprintd-enroll
   Test:
     fprintd-verify
   Enable fingerprint login / sudo:
     sudo pam-auth-update        # tick "Fingerprint authentication"

$( [[ "$WITH_GUI" -eq 0 ]] && echo "   GUI tools not detecting the sensor? Re-run with:  sudo bash $0 --with-gui" )

   Undo everything:  sudo bash $0 --uninstall
EOF
