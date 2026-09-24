# Lightweight Cog Kiosk

A small fullscreen Web kiosk for Raspberry Pi OS Lite and Debian 13
(Trixie). It uses Cage as a minimal Wayland compositor and Cog/WPE WebKit as
the browser, without installing a desktop environment.

The repository is intentionally generic. It does not contain a default Web
address, Wi-Fi configuration, passwords, SSH keys, or organization-specific
settings. The target URL and existing Linux username are selected when the
installer is run.

This project was validated on a Raspberry Pi 3 Model A+ with 512 MB RAM using:

- Raspberry Pi OS Lite 32-bit, Debian 13 (Trixie)
- Cog 0.18.4 / WPE WebKit 2.48.1
- Cage 0.3.1
- GStreamer 1.26

## What the installer configures

- Cog, Cage, WebKit media codecs, fonts, and D-Bus support
- A fullscreen kiosk on `tty1`
- Automatic startup after boot
- Automatic restart after a browser or compositor crash
- The Raspberry Pi OS Trixie Bubblewrap capability fix
- A periodic page reload watchdog
- A complete kiosk-service restart when D-Bus page reload fails

The installer does **not** store or configure Wi-Fi credentials, user
passwords, SSH keys, or GitHub credentials.

## Prepare the Pi

Use Raspberry Pi Imager to install **Raspberry Pi OS Lite 32-bit (Trixie)**.
Use Imager customization to configure the hostname, Wi-Fi, kiosk user, and
SSH access. Boot the Pi and connect over SSH.

Update the base operating system before the first kiosk installation:

```bash
sudo apt update
sudo apt full-upgrade -y
sudo reboot
```

## Quick start

Clone the repository to the Pi:

```bash
git clone https://github.com/DakotaS96/lightweight-cog-kiosk.git
cd lightweight-cog-kiosk
```

When logged in as the account that should run the kiosk, install with:

```bash
sudo bash ./install.sh \
  --url "https://example.com" \
  --refresh-minutes 30
```

The installer uses the account that invoked `sudo`. To run the kiosk under a
different existing account, specify it explicitly:

```bash
sudo bash ./install.sh \
  --user kioskuser \
  --url "https://example.com" \
  --refresh-minutes 30
```

Replace the example URL and username for the target kiosk. The specified user
must already exist; the installer deliberately does not create accounts or
manage passwords.

The installer is safe to rerun when changing the URL or refresh interval.

## Centrally managed signage example

```bash
sudo bash ./install.sh \
  --user kioskuser \
  --url "https://signage.example.com/device-name.html" \
  --refresh-minutes 30
```

The URL is stored locally in:

```text
/etc/default/lightweight-cog-kiosk
```

No organization-specific URL is committed to this repository.

## Per-device deployment

For installations that use a standard account name, create that account while
flashing the operating system, then provide it at installation time:

```bash
sudo bash ./install.sh \
  --user kioskuser \
  --url "https://signage.example.com/device-name.html" \
  --refresh-minutes 30
```

There is no need to fork or maintain a private copy merely to use a different
username. Keep organization-specific URLs and credentials in deployment
documentation or a separate private configuration system.

## Administration

Service status:

```bash
systemctl status lightweight-cog-kiosk.service --no-pager
```

Recent logs:

```bash
sudo journalctl -u lightweight-cog-kiosk.service -b --no-pager -n 100
```

Reload timer status:

```bash
systemctl status lightweight-cog-kiosk-refresh.timer --no-pager
systemctl list-timers lightweight-cog-kiosk-refresh.timer
```

Force a page reload now:

```bash
sudo systemctl start lightweight-cog-kiosk-refresh.service
```

Restart the graphical kiosk:

```bash
sudo systemctl restart lightweight-cog-kiosk.service
```

Change the displayed URL by rerunning the installer with `--url`, or carefully
edit `/etc/default/lightweight-cog-kiosk` and restart the service.

## Removing the kiosk

```bash
sudo bash ./uninstall.sh
```

The uninstaller restores `getty@tty1`, retains the local URL configuration,
and does not remove shared Debian packages.

## Important notes

- The original Pi Zero and Pi Zero W are not recommended for modern WebKit
  dashboards because they have a single-core processor.
- A Pi Zero 2 W may work for simple pages, but the Pi 3 A+ is faster and has
  the same 512 MB RAM limitation.
- Heavy video, complex animation, and multiple simultaneous dashboard iframes
  can exceed the practical limits of a 512 MB Pi.
- A systemd service can remain `active` even when page JavaScript is stuck.
  The reload watchdog exists to recover that condition.

## License

Released under the [MIT License](LICENSE).
