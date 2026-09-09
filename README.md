# SecTools

A single interactive script that bootstraps a pentest workstation: it installs
common offensive-security tools from apt/pip, pulls a curated set of scripts and
binaries into a working directory of your choice, and adds a couple of handy
shell helpers.

## Usage

```
wget -q https://github.com/0xstaark/SecTools/raw/refs/heads/main/sectools.sh
chmod +x sectools.sh
sudo ./sectools.sh
```

On launch you can optionally run `apt update` / `apt upgrade`, then pick from the
menu:

| Option | Action |
| ------ | ------ |
| 1 | Install tools |
| 2 | Download scripts |
| 3 | Download obfuscated scripts |
| 4 | Add custom shell functions |
| 5 | All of the above |
| 0 | Exit |

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
