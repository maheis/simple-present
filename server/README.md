# SimplePresent sync server (minimal scaffold)

Minimal Go scaffold for a Linux-only headless sync server using SQLite and JSON config.

Quick start:

1. Copy `config.json.example` to `config.json` and edit paths.
2. Build:

```bash
cd server
go build -o simplepresent
```

3. Run:

```bash
./simplepresent -config config.json
```

Installation (systemd):

1. Build the binary:

```bash
cd server
go build -o simplepresent
```

2. As root, run the installer (this will copy files to `/usr/local/bin`, `/etc/simplepresent`, create `/var/lib/simplepresent` and enable the service):

```bash
cd server
sudo ./deploy/install.sh
```

Remote install via `curl`:

You can host `server/install.sh` raw on GitHub and let users install directly with `curl`.
Example:

```bash
curl -sL https://raw.githubusercontent.com/<owner>/<repo>/main/server/install.sh | sudo sh -s -- https://github.com/<owner>/<repo>.git
```

The installer will clone the repo, build the binary and run the deploy script.


3. Edit `/etc/simplepresent/config.json` to set any TLS paths or bind address.

Logs: `journalctl -u simplepresent -f`

