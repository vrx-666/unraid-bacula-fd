# Bacula File Daemon for Unraid

A native [Bacula](https://www.bacula.org) 15 file daemon (`bacula-fd`) packaged as an Unraid plugin.
It lets an existing Bacula Director back up the Unraid host itself — the flash drive (`/boot/config`),
VM definitions (`/etc/libvirt`), appdata or anything else — without a container or bind mounts.

> **Status: early test release.** No GUI yet; configuration is a plain text file.

## Requirements

- Unraid 7.0.0 or newer
- A Bacula 15 Director and Storage Daemon somewhere on your network
  (for example the [bacula-server](https://github.com/vrx-666/bacula-server) container)

## Install

Unraid → *Plugins* → *Install Plugin*, paste:

```
https://github.com/vrx-666/unraid-bacula-fd/releases/latest/download/bacula-fd.plg
```

On first install the plugin writes `/boot/config/plugins/bacula-fd/bacula-fd.conf` with a random password
and prints it. Set the `Director` name to match your Director, then restart the daemon:

```
/etc/rc.d/rc.bacula-fd restart     # also: start | stop | status
```

On the Director, add a matching `Client` resource (address of your Unraid server, port 9102, same password).
The config file survives plugin updates and removal.

## Notes

- Paths under `/mnt` and `/etc/libvirt` exist only while the array is started.
- When restoring `/boot/config` to a new flash drive, the Unraid licence key is tied to the old drive's GUID —
  use Unraid's licence transfer.

## Building and testing

```
docker build --output type=local,dest=out .   # -> out/bacula-fd-<version>-x86_64-1_vrx.txz
./test-unraid.sh 7.3.3                         # run the package against a stock Unraid release
```

`test-unraid.sh` downloads the official Unraid release, unpacks its root filesystem and runs `bacula-fd`
in a chroot. CI runs it against 7.0.0 and the latest release of every 7.x line.

The package is built on Slackware 15.0 with OpenSSL 3 linked statically, so it does not depend on the
OpenSSL version shipped with Unraid.

## License

Bacula is licensed under the AGPL-3.0; the build scripts in this repository are under the same licence.
