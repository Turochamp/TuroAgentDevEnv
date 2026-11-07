# TuroAgentDevEnv

Personal Windows developer environment setup scripts and configuration files.

## Overview

This repository contains:
- PowerShell scripts to configure Windows and install tools
- App installs via winget and Chocolatey
- Configuration files for common dev tools and IDEs

IDE setup is split into Cursor (primary), Claude Code, and optional Visual Studio
scripts; adjust `scripts-to-run.ps1` as needed.

It is tailored to my workflow. If you want to use it, please fork and adjust.

## Quick start (public bootstrap)

Run the bootstrap script from an **admin** PowerShell to install core tools, clone the repo,
and open a file where you can comment out scripts you do not want to run:

```
irm https://raw.githubusercontent.com/Turochamp/TuroAgentDevEnv/main/bootstrap.ps1 | iex
```

The selection file is `scripts-to-run.ps1`. Comment out any script lines you
do not want to run, save, and close the editor to continue.

## Wi-Fi (optional)

`scripts/WiFi.ps1` keeps saved Wi-Fi profiles in a fixed priority order, with passwords and the
order held in a self-hosted [Infisical](https://infisical.com). It is commented out in
`scripts-to-run.ps1`; enable it there or run it on its own. No admin needed; safe to re-run.

In Infisical, project of your choice, env `prod`, folder `/workstation/wifi`:

- One secret per network holding its password, named upper-snake, e.g. `WIFI_HOMENET`.
- `WIFI_ORDER`: a JSON array in priority order, shaped like
  [`config/wifi-order.example.json`](config/wifi-order.example.json). `"hotspot": true` marks the
  phone hotspot (connect automatically, switch away when a preferred network appears, metered).
  `"retired": true` deletes that profile. Profiles not listed keep their order below.

First run asks for three values and stores them as user environment variables:

| Variable | Value |
|---|---|
| `WORKSTATION_INFISICAL_URL` | Infisical base URL |
| `WORKSTATION_INFISICAL_PROJECT_ID` | Project ID |
| `WORKSTATION_CA_SOURCE` | `owner/repo/path/to/root.crt`, the root CA behind that URL, fetched with `gh`; `none` if the URL has a public certificate |

Needs `gh auth login` done. Installs the Infisical CLI if missing and runs `infisical login` when
needed. Missing config, an unreachable server or a cancelled login: it warns and changes nothing.

```powershell
.\scripts\WiFi.ps1 -WhatIf   # show what would change
.\scripts\WiFi.ps1
```

Tests: `Invoke-Pester .\tests` (Pester 5+).

## Disclaimer

The code in this repository is provided as-is, without warranties. Use at your
own risk.



