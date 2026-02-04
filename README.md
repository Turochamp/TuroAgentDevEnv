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

## Disclaimer

The code in this repository is provided as-is, without warranties. Use at your
own risk.



