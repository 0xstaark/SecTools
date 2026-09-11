# SecTools

A script that bootstraps a pentest workstation: it installs common
offensive-security tools from apt/pip, pulls a curated set of scripts and
binaries into a working directory of your choice, and adds a couple of handy
shell helpers. It runs interactively via a menu, or non-interactively with
command-line flags.

## Usage

```
wget -q https://github.com/0xstaark/SecTools/raw/refs/heads/main/sectools.sh
chmod +x sectools.sh
sudo ./sectools.sh
```

With no arguments, you can optionally run `apt update` / `apt upgrade`, then pick
from the menu:

| Option | Action |
| ------ | ------ |
| 1 | Install tools |
| 2 | Download scripts |
| 3 | Download obfuscated scripts |
| 4 | Add custom shell functions |
| 5 | All of the above |
| 0 | Exit |

### Non-interactive mode

Pass one or more action flags to run without the menu (useful for VM
provisioning or unattended setup):

```
sudo ./sectools.sh --all -y                       # everything, assume defaults
sudo ./sectools.sh --tools                         # just install tools
sudo ./sectools.sh --scripts --dir /opt/tools -y   # download scripts to a set dir
```

| Flag | Purpose |
| ---- | ------- |
| `--tools` / `--scripts` / `--obfuscated` / `--functions` | Run that phase (combine freely) |
| `--all` | All of the above |
| `--dir PATH` | Download target directory; skips the prompt |
| `--only a,b,c` | Tool phase: install only these tools |
| `--skip a,b,c` | Tool phase: skip these tools |
| `--dry-run` | Show what would happen; change nothing |
| `--list` | Print the tool inventory and exit |
| `--update` / `--upgrade` | Run `apt update` / `apt upgrade` first |
| `-y`, `--yes` | Assume defaults, run non-interactively |
| `--no-color` | Disable colour and animation |
| `-h`, `--help` / `-V`, `--version` | Help / version |

```
sudo ./sectools.sh --tools --only netexec,impacket,bloodhound
sudo ./sectools.sh --tools --skip docker,docker-compose
sudo ./sectools.sh --all --dry-run
```

### Output and logging

* Colour and Unicode are auto-detected. When the output is piped or the terminal
  is limited, the script falls back to plain ASCII, and `NO_COLOR` is honoured.
* Each item prints a single aligned status line, and every phase ends with an
  `ok / skipped / failed` summary.
* Failures are recorded in `sectools.log` (in the directory you launched from)
  instead of being printed to the screen.

## Shell functions added to `~/.zshrc`

* **servtools** &mdash; start an HTTP server from the tools directory.
  ```
  servtools <port>          # serve the tools directory
  servtools <port> --obf    # serve the obfuscated sub-folder
  ```
* **extract_ports** &mdash; turn tool output (e.g. RustScan) into a
  comma-separated port list.
  ```
  extract_ports <file>
  ```
* **`cat` &rarr; `bat`** &mdash; adds `alias cat` to `~/.zshrc` and `~/.bashrc`
  (uses `batcat` on Debian/Kali, `bat` elsewhere) when `bat` is installed.
* **rockyou** &mdash; if `/usr/share/wordlists/rockyou.txt.gz` is present and not
  yet extracted, it is gunzipped to `rockyou.txt`.

## Tools

Installed via apt/pip (RustScan falls back to the latest GitHub `.deb` if the
apt package is unavailable):

* seclists
* rustscan
* wfuzz
* ffuf
* bloodhound
* neo4j
* gobuster
* feroxbuster
* certipy-ad
* pypykatz
* sublime-text
* docker
* docker-compose
* bloodhound-CE (docker-compose deployment under `/opt/bloodhoundCE`)
* netexec (CrackMapExec successor)
* impacket (secretsdump, psexec, GetNPUsers, ...)
* responder
* mitm6
* evil-winrm
* enum4linux-ng
* ldapdomaindump
* smbmap
* pipx
* fzf (installed into the invoking user's `~/.fzf`, not root's)
* bat (aliased to `cat`; see shell functions above)
* masscan
* nuclei
* httpx (ProjectDiscovery)
* subfinder
* coercer
* bloodyAD
* ligolo-ng (pivoting; apt or GitHub release)

Active Directory / network tools are installed from the distro repo (apt) on
Kali and fall back to `pip`/`gem`/GitHub release on other systems.

The full tool list lives in a single registry table near the top of
`install_tools` in `sectools.sh`; adding a tool is a one-line `tool ...` entry.

## Scripts

Downloaded into your chosen tools directory (default `/opt/tools`). Latest
releases are fetched from GitHub where available:

* mimikatz.exe
* SharpHound.exe
* winPEASx64.exe
* winPEASany.exe
* linpeas.sh
* pspy32
* pspy64
* kerbrute_linux_amd64
* kerbrute_windows_amd64.exe
* powercat.ps1
* Invoke-Mimikatz.ps1
* PowerView.ps1
* PowerUp.ps1
* Rubeus.exe
* Inveigh.ps1
* nc64.exe
* nc.exe
* PlumHound.py
* linux-exploit-suggester.sh
* linuxprivchecker.py
* LinEnum.sh
* Whisker.exe
* SharpMapExec.exe
* SharpChisel.exe
* Seatbelt.exe
* ADCSPwn.exe
* BetterSafetyKatz.exe
* PassTheCert.exe
* SharPersist.exe
* MailSniper.ps1
* ADSearch.exe
* Invoke-DCOM.ps1
* PowerUpSQL.ps1
* SharpSCCM.exe
* LAPSToolkit.ps1
* Certify.exe
* Inveigh.exe
* Invoke-RunasCs.ps1
* Snaffler.exe
* chisel
* PSTools
* RunasCs.exe
* AutoRecon
* PassTheCert
* PetitPotam
* SprayingToolkit
* BloodHound.py

## Obfuscated payloads

Option 3 downloads obfuscated builds from
[ObfuscatedSharpCollection](https://github.com/Flangvik/ObfuscatedSharpCollection)
into an `obfuscated/` sub-folder of your tools directory:

* Certify, Rubeus, Seatbelt, SharpEDRChecker, SharpHound, SharpSCCM, SharpView,
  Snaffler, StickyNotesExtract, Whisker, winPEAS, SharpWebServer, SharpNoPSExec,
  SharpMapExec, SharpKatz, ADCSPwn, ADCollector

## Credits

Created by [0xstaark](https://github.com/0xstaark).

> For authorised security testing and educational use only.
