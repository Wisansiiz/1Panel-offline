<p align="center"><a href="https://1panel.pro"><img src="https://resource.1panel.pro/img/1panel-logo.png" alt="1Panel" width="300" /></a></p>

<h3 align="center">1Panel Offline Community Edition (Modified Fork)</h3>

> [!IMPORTANT]
> This repository is an independently maintained, modified fork of
> [1Panel-dev/1Panel](https://github.com/1Panel-dev/1Panel). It is not an
> official 1Panel release and is not maintained or supported by FIT2CLOUD or
> the upstream 1Panel team. Issues specific to this offline edition should be
> reported in this repository.

This edition is designed for enterprise intranets, isolated data centers and
other air-gapped environments. Runtime services default to offline mode and
block automatic internet access. Standard releases include the Docker runtime
and selected OpenResty/MySQL images, but intentionally contain no application
catalog.

[中文说明](docs/README.zh-Hans.md) · [Offline build and deployment guide](offline/README.md)

## Offline edition changes

- Disables remote app-store synchronization, online upgrades, public NTP,
  online documentation indexes, language/GeoIP downloads and anonymous
  installation analytics.
- Prevents Docker image pulls and starts Compose projects with `--pull never`.
- Installs bundled Docker Engine, containerd, runc and Docker Compose when the
  target host has no Docker installation.
- Includes only the OpenResty/MySQL application definitions matching bundled
  images; users import definitions and images for any additional applications.
- Builds reproducible `linux/amd64` and `linux/arm64` offline bundles.
- Installs systemd network restrictions that only permit loopback and private
  network ranges.

Prepackaged images:

| Application | amd64 | arm64 |
|---|---|---|
| OpenResty | `1.27.1.2-2-3-focal` | `1.27.1.2-2-3-focal` |
| MySQL | `8.4.6`, `8.0.43`, `5.7.44`, `5.6.51` | `8.4.6`, `8.0.43` |

Bundled runtime: Docker Engine `29.6.0` and Docker Compose `2.40.3`.

## Downloads and automated builds

Every push to `dev-v2` builds both architectures and creates a GitHub
Release. Tags matching `offline-v*` can be used to publish a named version.
Each architecture is provided as a directly downloadable `.tar.gz`:

```bash
sha256sum -c SHA256SUMS
tar -xzf 1panel-offline-*-linux-amd64.tar.gz
```

See [the offline guide](offline/README.md) for local builds, installation and
external image import instructions.

The same Release also publishes architecture-specific import bundles for
MySQL 8.4.10, MySQL 5.7.44 (amd64 only), Redis 7.4.9, and Java 8/17/21.

<p align="center">
  <a href="https://trendshift.io/repositories/2462" target="_blank"><img src="https://trendshift.io/api/badge/repositories/2462" alt="1Panel-dev%2F1Panel | Trendshift" style="width: 240px; height: auto;" /></a>
</p>

<p align="center">
  <a href="https://www.gnu.org/licenses/gpl-3.0.html"><img src="https://shields.io/github/license/1Panel-dev/1Panel?color=%231890FF" alt="License: GPL v3"></a>
  <a href="https://app.codacy.com/gh/1Panel-dev/1Panel"><img src="https://app.codacy.com/project/badge/Grade/da67574fd82b473992781d1386b937ef" alt="Codacy"></a>
  <a href="https://discord.gg/bUpUqWqdRr"><img src="https://img.shields.io/discord/1318846410149335080?logo=discord&labelColor=%20%235462eb&logoColor=%20%23f5f5f5&color=%20%235462eb" alt="Discord"></a>
  <a href="https://github.com/1Panel-dev/1Panel/releases"><img src="https://img.shields.io/github/v/release/1Panel-dev/1Panel" alt="GitHub release"></a>
  <a href="https://github.com/1Panel-dev/1Panel"><img src="https://img.shields.io/github/stars/1Panel-dev/1Panel?color=%231890FF&style=flat-square" alt="Stars"></a>
</p>

<p align="center">
  <a href="/README.md"><img alt="English" src="https://img.shields.io/badge/English-d9d9d9"></a>
  <a href="/docs/README.zh-Hans.md"><img alt="中文(简体)" src="https://img.shields.io/badge/中文(简体)-d9d9d9"></a>
  <a href="/docs/README.ja.md"><img alt="日本語" src="https://img.shields.io/badge/日本語-d9d9d9"></a>
  <a href="/docs/README.pt-br.md"><img alt="Português (Brasil)" src="https://img.shields.io/badge/Português (Brasil)-d9d9d9"></a>
  <a href="/docs/README.ar.md"><img alt="العربية" src="https://img.shields.io/badge/العربية-d9d9d9"></a>
  <a href="/docs/README.de.md"><img alt="Deutsch" src="https://img.shields.io/badge/Deutsch-d9d9d9"></a>
  <a href="/docs/README.es.md"><img alt="Español" src="https://img.shields.io/badge/Español-d9d9d9"></a>
  <a href="/docs/README.fr.md"><img alt="français" src="https://img.shields.io/badge/français-d9d9d9"></a>
  <a href="/docs/README.ko.md"><img alt="한국어" src="https://img.shields.io/badge/한국어-d9d9d9"></a>
  <a href="/docs/README.id.md"><img alt="Bahasa Indonesia" src="https://img.shields.io/badge/Bahasa Indonesia-d9d9d9"></a>
  <a href="/docs/README.zh-Hant.md"><img alt="中文(繁體)" src="https://img.shields.io/badge/中文(繁體)-d9d9d9"></a>
  <a href="/docs/README.tr.md"><img alt="Türkçe" src="https://img.shields.io/badge/Türkçe-d9d9d9"></a>
  <a href="/docs/README.ru.md"><img alt="Русский" src="https://img.shields.io/badge/Русский-d9d9d9"></a>
  <a href="/docs/README.ms.md"><img alt="Bahasa Melayu" src="https://img.shields.io/badge/Bahasa Melayu-d9d9d9"></a>
</p>

---

## What is 1Panel?

The upstream 1Panel project is a modern, open-source VPS control panel. This
fork adapts its non-AI community management features for fully offline
environments; the AI module is disabled in this distribution.

👉 Watch the [2-minute introduction](https://www.youtube.com/watch?v=Jl_wqp-XA08)

## Why 1Panel?

| | 1Panel | cPanel / Plesk | aaPanel | Webmin |
|--|--------|----------------|---------|--------|
| Free & open source | ✅ | ❌ | Partial | ✅ |
| One-click app marketplace | ✅ 165+ apps | ❌ | ✅ | ❌ |
| Modern UI (post-2020) | ✅ | ❌ | Partial | ❌ |
| Docker / container management | ✅ | ❌ | ❌ | ❌ |
| Active development | ✅ | ✅ | ✅ | Slow |

## Key Features

- **One-Click Website Deployment**: Launch production-ready websites with automatic domain binding, SSL provisioning, and Nginx config — zero manual setup.
- **App Marketplace**: 165+ trusted open-source apps (Nextcloud, Bitwarden, Umami, NocoBase, and more) installed and updated with a single click.
- **Docker & Container Management**: Create, start, stop, and inspect containers, images, networks, and volumes through a visual UI — no CLI juggling.
- **Security Out of the Box**: Firewall rules, fail2ban, container isolation, WAF, and audit logs — configured and running from day one.
- **Backup & Restore**: Schedule automated backups to AWS S3, Cloudflare R2, or local storage. Restore any snapshot in one click.

## Offline quick start

Download the matching Actions artifact or GitHub Release on an internet-connected
machine, transfer it to the isolated Linux server, then run:

```bash
tar -xzf 1panel-offline-*-linux-amd64.tar.gz
cd 1panel-offline-*-linux-amd64
sudo ./install.sh
```

After installation, open `http://<your-server-ip>:<port>/<security-path>` in your browser.  
Run `1pctl user-info` via SSH if you need to retrieve your access credentials.

## Screenshot

![1Panel UI](https://resource.1panel.pro/img/overview_en_v2.png)

## Pro Edition

1Panel OSS is free forever. Pro adds features built for teams and production workloads:

| Feature | OSS | Pro |
|---------|:---:|:---:|
| One-click app installs | ✅ | ✅ |
| WAF & advanced security | Basic | ✅ |
| Website tamper protection | ❌ | ✅ |
| Website uptime monitoring | ❌ | ✅ |
| Multi-node management | ❌ | ✅ |
| Custom logo & theme | ❌ | ✅ |
| Priority support | ❌ | ✅ |

**From $80/year.** [Compare plans & start 30-day free trial →](https://1panel.pro/pricing)

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=1Panel-dev/1Panel&type=Date)](https://star-history.com/#1Panel-dev/1Panel&Date)

## Community & Support

- **Offline fork issues** — [Wisansiiz/1Panel-offline](https://github.com/Wisansiiz/1Panel-offline/issues)
- **Discord** — [Join the community](https://discord.gg/bUpUqWqdRr) for help, feature requests, and show-and-tell
- **Docs** — [1panel.pro/docs](https://1panel.pro/docs)
- **Upstream issues** — [1Panel-dev/1Panel](https://github.com/1Panel-dev/1Panel/issues)

## Security

Found a vulnerability? Please read [SECURITY.md](/SECURITY.md) before disclosing.

## License

Licensed under the [GNU General Public License v3.0](https://www.gnu.org/licenses/gpl-3.0.html).
