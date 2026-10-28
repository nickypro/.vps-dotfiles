# This box

You are in an **agent box**: a Docker container on a server, set up for
coding agents. You run as `dev` (uid 1000) with sudo and no password. The
owner reaches the box over SSH and through T3 Code's web UI. How it's built:
github.com/nickypro/.vps-dotfiles, folder `agent-box`.

## What survives a rebuild

The owner rebuilds the image now and then (security fixes, new CLIs). Only
these folders are kept:

- `/home/dev`, your home: logins, `~/.env`, history, `~/.local`
- `/data`: projects and data
- `/cells`: the isolated agents' folders (below)

Everything else goes back to the image: `apt install`s, `/usr`, `/opt`,
`/etc`. So install tools into your home (`pipx install`, `npm install -g
--prefix ~/.local`, a project's own venv or `node_modules`); `~/.local/bin`
and `~/bin` are on PATH. If a tool can only come from apt, install it and
tell the owner, so they can add it to the Dockerfile.

## Limits

- The whole box has about 5 GB of RAM, 3.5 CPUs and 4096 processes. Run one
  heavy build or test suite at a time.
- `/tmp` is on the server's disk. Delete big files there when you're done.

## Network

- The internet works: package managers, git, APIs.
- The server itself and private networks (10/8, 172.16/12, 192.168/16,
  Tailscale's 100.64/10, the cloud metadata address) are blocked on purpose.
  A timeout there is the firewall, not a bug: don't try to get around it.
- Servers you start can only be reached from inside the box. To show one to
  the owner, tell them the port; they open it with
  `ssh -L 8080:127.0.0.1:8080 agent-box` (their SSH name for the box may
  differ).
- Leave these ports alone: 2222 (SSH), 3773 (T3), 6080 and 9222 (the
  desktop), 20000-29999 (isolated agents).

## Secrets

API keys are in `~/.env` (`KEY=value` lines). Your shell and T3 load it, so
they are already in your environment. Never print them, put them in files
you commit, or send them anywhere except the service they belong to. The
owner adds keys with `make secret KEY=NAME` on the server.

## Isolated agents ("cells")

Each `/cells/<name>` folder belongs to an isolated agent: a separate Linux
user, without sudo, for work the owner trusts less. Treat its files as
untrusted:

- Don't run, build, test or install anything from a cell's folder as `dev`.
  `cell <name> <command>` runs a command as that cell instead. `cell <name>
  import <path>` gives it a copy of your files.
- Don't copy a cell's files into your folders, change their owner or
  permissions, or add `/cells` to git's `safe.directory`.
- Claude and Codex refuse to start in `/cells` as you. That's deliberate.

## Claude accounts

The owner may have more than one Claude login here. Each one shows up in T3
as its own provider, has its own folder (`~/.claude-<name>`), and has a
`claude-<name>` command in the shell. All of them share `~/.claude/CLAUDE.md`
and `~/.claude/{rules,skills,agents,commands}`, so put new skills there.

## Extras

These are only here if the owner chose them when building the image:

- **Desktop** (`command -v Xvnc` finds it): `desktop start`, then `desktop
  browser` starts Chromium, which you can drive at http://127.0.0.1:9222. The
  owner can watch it in their browser.
- **Scraping tools** (`/opt/scrape` exists): curl_cffi, trafilatura, yt-dlp,
  Camoufox, Playwright and markitdown. Use `/opt/scrape/bin/python`.
- **Synthesizer V** (desktop and Wine): `/opt/agent-box/extras/synthv/setup`,
  then `synthv`.

Claude's `/sandbox` and Codex's own sandbox don't work in Docker, because they
need user namespaces. The container is the sandbox.
