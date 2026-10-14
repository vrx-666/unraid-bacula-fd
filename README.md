# Bacula File Daemon for Unraid

A native [Bacula](https://www.bacula.org) 15 file daemon (`bacula-fd`) packaged as an Unraid plugin.
It lets an existing Bacula Director back up the Unraid host itself — the flash drive (`/boot/config`),
VM definitions (`/etc/libvirt`), appdata or anything else — without a container or bind mounts.

## Requirements

- Unraid 7.0.0 or newer
- A Bacula 15 Director and Storage Daemon somewhere on your network
  (for example the [bacula-server](https://github.com/vrx-666/bacula-server) container)

## Install

Unraid → *Plugins* → *Install Plugin*, paste:

```
https://github.com/vrx-666/unraid-bacula-fd/releases/latest/download/bacula-fd.plg
```

The daemon starts right away and listens on port 9102.

## Configuration

*Settings* → *Network Services* → *Bacula File Daemon* shows the daemon status, lets you start, stop and
restart it, and edit its config file (`/boot/config/plugins/bacula-fd/bacula-fd.conf`).

On first install the plugin writes that file with a random password. Set the `Director` name to match your
Director, click *Apply*, then *Restart*. The config is checked before it is saved; if it has errors, nothing
is saved and the error is shown. The file survives plugin updates and removal.

On the Director, add a matching `Client` resource: the address of your Unraid server, port 9102 and the
same password. A FileSet that keeps ACLs and extended attributes:

```
FileSet {
  Name = "unraid"
  Include {
    Options {
      signature = MD5
      aclsupport = yes
      xattrsupport = yes
    }
    File = /boot/config
    File = /etc/libvirt
  }
}
```

From the command line: `/etc/rc.d/rc.bacula-fd start|stop|restart|status`.

## The array and the daemon

- **Stopping the array restarts the daemon.** A daemon that reads files under `/mnt` keeps the shares busy,
  and Unraid then waits forever to unmount them, so the array never stops. The plugin stops the daemon when
  the array starts stopping and starts it again once the array is stopped. A backup job running at that
  moment fails. The daemon is started again so that the flash drive (`/boot`) can still be backed up while
  the array is stopped — even if you had stopped it on the settings page.
- **The daemon also starts when the server boots**, before the array is started, and regardless of whether
  it was stopped on the settings page before the reboot. To keep it off for good, remove the plugin; the
  config file stays on the flash drive.
- **A backup of an unmounted path reports success.** Paths under `/mnt` and `/etc/libvirt` exist only while
  the array is started. If a job runs while the array is stopped, Bacula can back up an empty directory
  and still report *Backup OK*. Schedule jobs for times when the array is up and check the
  number of files backed up.

- **Updating the plugin restarts the daemon**, so a backup job running at that moment fails. Keep this in
  mind if you let plugins update automatically.

## Restoring the flash drive

When restoring `/boot/config` to a new flash drive, the Unraid licence key is tied to the old drive's GUID —
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
