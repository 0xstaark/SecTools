#!/usr/bin/env bash
#
# SecTools - Pentest tooling bootstrapper
# https://github.com/0xstaark
#
# Installs common offensive-security tools and fetches a curated set of
# scripts/binaries into a working directory of your choice.

###############################################################################
# Terminal capability detection
###############################################################################
# Colours are only emitted to an interactive terminal that supports them, and
# NO_COLOR (https://no-color.org) is honoured.
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != "dumb" ]]; then
    USE_COLOR=1
else
    USE_COLOR=0
fi

if [[ "$USE_COLOR" -eq 1 ]]; then
    C_RESET=$'\e[0m';  C_BOLD=$'\e[1m';  C_DIM=$'\e[2m'
    C_RED=$'\e[38;5;203m'
    C_GREEN=$'\e[38;5;114m'
    C_YELLOW=$'\e[38;5;222m'
    C_CYAN=$'\e[38;5;80m'
    C_GREY=$'\e[38;5;245m'
else
    C_RESET='';  C_BOLD='';  C_DIM=''
    C_RED='';  C_GREEN='';  C_YELLOW='';  C_CYAN='';  C_GREY=''
fi

# Prefer Unicode glyphs when the locale looks UTF-8, otherwise fall back to ASCII.
if [[ "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" == *[Uu][Tt][Ff]* ]]; then
    GLYPH_OK='✔';  GLYPH_ERR='✘';  GLYPH_SKIP='•'
    GLYPH_INFO='›'; GLYPH_WARN='!'; GLYPH_ARROW='»'; GLYPH_DOT='·'
    SPIN_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
else
    GLYPH_OK='+';  GLYPH_ERR='x';  GLYPH_SKIP='-'
    GLYPH_INFO='>'; GLYPH_WARN='!'; GLYPH_ARROW='>'; GLYPH_DOT='-'
    SPIN_FRAMES=('|' '/' '-' '\')
fi

# Animate the spinner only when attached to an interactive terminal.
if [[ -t 1 && "$USE_COLOR" -eq 1 ]]; then SPIN_ANIMATE=1; else SPIN_ANIMATE=0; fi

# Always restore the cursor on exit/interrupt (the spinner hides it).
restore_cursor() { [[ "$SPIN_ANIMATE" -eq 1 ]] && printf '\e[?25h'; }
trap 'restore_cursor' EXIT
trap 'restore_cursor; echo; exit 130' INT TERM

NAME_WIDTH=30                                   # width of the item column
RULE="$(printf '%.0s─' {1..52})"
[[ "${LC_ALL:-}${LC_CTYPE:-}${LANG:-}" == *[Uu][Tt][Ff]* ]] || RULE="$(printf '%.0s-' {1..52})"

###############################################################################
# Environment
###############################################################################
startdir="$(pwd)"
user_home="$(eval echo "~${SUDO_USER:-$USER}")"
zshrc_file="${user_home}/.zshrc"
user_name="${SUDO_USER:-$(whoami)}"
LOGFILE="${startdir}/sectools.log"

# Per-phase counters (reset at the start of each phase).
STAT_OK=0; STAT_SKIP=0; STAT_FAIL=0
reset_stats() { STAT_OK=0; STAT_SKIP=0; STAT_FAIL=0; }

###############################################################################
# Output helpers
###############################################################################
info()  { printf '  %s%s%s  %s\n' "$C_CYAN"   "$GLYPH_INFO" "$C_RESET" "$*"; }
ok()    { printf '  %s%s%s  %s\n' "$C_GREEN"  "$GLYPH_OK"   "$C_RESET" "$*"; }
warn()  { printf '  %s%s%s  %s\n' "$C_YELLOW" "$GLYPH_WARN" "$C_RESET" "$*"; }
err()   { printf '  %s%s%s  %s\n' "$C_RED"    "$GLYPH_ERR"  "$C_RESET" "$*"; }
rule()  { printf '  %s%s%s\n' "$C_DIM" "$RULE" "$C_RESET"; }

section() {
    printf '\n  %s%s%s %s%s%s\n' "$C_CYAN" "$GLYPH_ARROW" "$C_RESET" "$C_BOLD" "$1" "$C_RESET"
    rule
}

# skip_line <name> [note]  - item already present / nothing to do
skip_line() {
    STAT_SKIP=$((STAT_SKIP + 1))
    printf '  %s%s%s  %-*s %s%s%s\n' \
        "$C_GREY" "$GLYPH_SKIP" "$C_RESET" "$NAME_WIDTH" "$1" "$C_GREY" "${2:-present}" "$C_RESET"
}

# summary  - print the ok / skipped / failed tally for the current phase
summary() {
    rule
    printf '  %s%s %d%s   %s%s %d%s   %s%s %d%s\n\n' \
        "$C_GREEN" "$GLYPH_OK"   "$STAT_OK"   "$C_RESET" \
        "$C_GREY"  "$GLYPH_SKIP" "$STAT_SKIP" "$C_RESET" \
        "$C_RED"   "$GLYPH_ERR"  "$STAT_FAIL" "$C_RESET"
    [[ "$STAT_FAIL" -gt 0 ]] && info "Details for failures logged to ${C_BOLD}${LOGFILE}${C_RESET}"
}

log() { printf '%s  %s\n' "$(date '+%F %T')" "$*" >> "$LOGFILE" 2>/dev/null; }

###############################################################################
# Unified spinner
#
#   ( some_command ) & spinner "<name>" ["<action>"] ["<result>"]
#
#   name    : item label shown in the left column
#   action  : verb shown while running   (default "working")
#   result  : word shown on success      (default "done")
#
# Prints exactly one status line and returns the background job's exit code,
# updating the phase counters. Must be called immediately after `... &`.
###############################################################################
spinner() {
    local pid=$!
    local name="$1"
    local action="${2:-working}"
    local result="${3:-done}"
    local i=0

    if [[ "$SPIN_ANIMATE" -eq 1 ]]; then
        printf '\e[?25l'                                   # hide cursor
        while kill -0 "$pid" 2>/dev/null; do
            printf '\r  %s%s%s  %-*s %s%s%s' \
                "$C_YELLOW" "${SPIN_FRAMES[i]}" "$C_RESET" \
                "$NAME_WIDTH" "$name" "$C_DIM" "$action" "$C_RESET"
            i=$(( (i + 1) % ${#SPIN_FRAMES[@]} ))
            sleep 0.08
        done
        printf '\e[?25h'                                   # show cursor
        printf '\r\e[K'                                    # clear the line
    fi

    wait "$pid"; local code=$?
    if [[ $code -eq 0 ]]; then
        STAT_OK=$((STAT_OK + 1))
        printf '  %s%s%s  %-*s %s%s%s\n' \
            "$C_GREEN" "$GLYPH_OK" "$C_RESET" "$NAME_WIDTH" "$name" "$C_GREEN" "$result" "$C_RESET"
    else
        STAT_FAIL=$((STAT_FAIL + 1))
        printf '  %s%s%s  %-*s %s%s%s\n' \
            "$C_RED" "$GLYPH_ERR" "$C_RESET" "$NAME_WIDTH" "$name" "$C_RED" "failed" "$C_RESET"
    fi
    return $code
}

###############################################################################
# Banner
###############################################################################
print_banner() {
    printf '\n%s%s' "$C_BOLD" "$C_CYAN"
    cat <<'ART'
      ___              _                     _
     / _ \            | |                   | |
    | | | |__  __ ___ | |_  __ _  __ __ ___ | | __
    | | | |\ \/ // __|| __|/ _\ |/ _\ || __|| |/ /
    | |_| | >  < \__ \| |_| (_| ||(_| || |  |   <
     \___/ /_/\_\|___/ \__|\__,_|\__,_||_|  |_|\_\
ART
    printf '%s' "$C_RESET"
    printf '    %sSecTools%s  %s%s offensive tooling bootstrapper%s\n' \
        "$C_BOLD" "$C_RESET" "$C_DIM" "$GLYPH_DOT" "$C_RESET"
    printf '    %shttps://github.com/0xstaark%s\n\n' "$C_CYAN" "$C_RESET"
}

###############################################################################
# Directory input with tab-completion
###############################################################################
read_directory() {
    local prompt="$1"
    local default="$2"
    local result=""

    if [[ -n "$BASH_VERSION" ]]; then
        bind 'set show-all-if-ambiguous on' 2>/dev/null
        bind 'TAB:complete' 2>/dev/null
        read -e -r -p "$prompt" result
        bind 'set show-all-if-ambiguous off' 2>/dev/null
    else
        read -r -p "$prompt" result
    fi

    if [[ -z "$result" ]]; then echo "$default"; else echo "$result"; fi
}

###############################################################################
# Preflight checks
###############################################################################
require_dependencies() {
    local missing=()
    local dep
    for dep in curl wget unzip git; do
        command -v "$dep" >/dev/null 2>&1 || missing+=("$dep")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "Missing required tools: ${C_BOLD}${missing[*]}${C_RESET}"
        if command -v apt-get >/dev/null 2>&1; then
            info "Attempting to install them with apt-get..."
            (sudo apt-get -qq -y install "${missing[@]}" >>"$LOGFILE" 2>&1) & spinner "dependencies" "installing" "ready"
        else
            err "Please install them manually and re-run this script."
            exit 1
        fi
    fi
}

check_network() {
    if command -v curl >/dev/null 2>&1 &&
       curl -fsS --connect-timeout 8 --max-time 15 -o /dev/null https://api.github.com 2>/dev/null; then
        return 0
    fi
    ping -c1 -W2 1.1.1.1 >/dev/null 2>&1 && return 0
    ping -c1 -W2 8.8.8.8 >/dev/null 2>&1 && return 0
    return 1
}

###############################################################################
# Cleanup and housekeeping
###############################################################################
perform_cleanup() {
    (
        cp mimikatz/x64/mimikatz.exe . >/dev/null 2>&1
        mv RunasCS RunasCS.exe >/dev/null 2>&1
        rm -rf x64 Win32 PassTheCert PetitPotam mimikatz >/dev/null 2>&1
        if [[ -n "$toolsdir" && $(stat -c '%U' "$toolsdir" 2>/dev/null) != "$user_name" ]]; then
            chown -R "${user_name}:${user_name}" "$toolsdir" >/dev/null 2>&1
        fi
        true
    ) & spinner "housekeeping" "cleaning up" "done"
    cd "$startdir" 2>/dev/null || true
}

###############################################################################
# System update / upgrade prompts
###############################################################################
ask_update() {
    local choice
    read -r -p "$(printf '  %s%s%s  Run %ssudo apt update%s now? [y/N] ' "$C_CYAN" "$GLYPH_INFO" "$C_RESET" "$C_BOLD" "$C_RESET")" choice
    case "$choice" in
        [Yy]*)
            (sudo apt-get -q update >>"$LOGFILE" 2>&1) & spinner "apt update" "refreshing package lists" "updated"
            ;;
        *)
            skip_line "apt update" "skipped"
            ;;
    esac
}

ask_upgrade() {
    local choice
    read -r -p "$(printf '  %s%s%s  Run %ssudo apt upgrade%s now? [y/N] ' "$C_CYAN" "$GLYPH_INFO" "$C_RESET" "$C_BOLD" "$C_RESET")" choice
    case "$choice" in
        [Yy]*)
            (sudo apt-get -q -y upgrade >>"$LOGFILE" 2>&1) & spinner "apt upgrade" "upgrading packages" "upgraded"
            ;;
        *)
            skip_line "apt upgrade" "skipped"
            ;;
    esac
}

###############################################################################
# Download helper: git clone
###############################################################################
git_download() {
    local repo_url="$1"
    local repo_name="$2"
    rm -rf "$repo_name" 2>/dev/null
    (git clone --depth 1 "$repo_url" "$repo_name" >>"$LOGFILE" 2>&1) & spinner "$repo_name" "cloning" "cloned"
    [[ $? -eq 0 ]] || log "clone failed: $repo_url"
}

###############################################################################
# Download helper: zip archive extracted into a folder
###############################################################################
folder_zip_download() {
    local zip_url="$1"
    local zip_name="$2"
    local extract_dir="${3:-${zip_name%.zip}}"
    rm -rf "$extract_dir" "$zip_name" 2>/dev/null
    (
        curl -fsSL --connect-timeout 10 --max-time 120 "$zip_url" -o "$zip_name" 2>/dev/null &&
        unzip -qo "$zip_name" -d "$extract_dir" >/dev/null 2>&1
        rc=$?
        rm -f "$zip_name"
        exit $rc
    ) & spinner "$extract_dir" "downloading" "ready"
    [[ $? -eq 0 ]] || log "folder zip failed: $zip_url"
}

###############################################################################
# Download helper: single file delivered inside a .zip or .gz
###############################################################################
single_file_zip_gz() {
    local file_url="$1"
    local file_name="$2"
    local label="${file_name%.*}"
    rm -f "$file_name" 2>/dev/null
    (
        curl -fsSL --connect-timeout 10 --max-time 120 "$file_url" -o "$file_name" 2>/dev/null || exit 1
        if [[ "$file_name" == *.gz ]]; then
            gunzip -c "$file_name" > "${file_name%.gz}" 2>/dev/null || exit 1
        elif [[ "$file_name" == *.zip ]]; then
            inner="$(unzip -Z1 "$file_name" 2>/dev/null | head -1)"
            unzip -p "$file_name" "$inner" > "${file_name%.zip}" 2>/dev/null || exit 1
        fi
        rm -f "$file_name"
        exit 0
    ) & spinner "$label" "downloading" "ready"
    [[ $? -eq 0 ]] || { rm -f "$file_name" 2>/dev/null; log "single zip/gz failed: $file_url"; }
}

###############################################################################
# Download helper: pick an asset from the latest GitHub release and fetch it
###############################################################################
api_file_check_and_download_file() {
    local api_url="$1"
    local filename="$2"
    local filter="$3"

    local response file_url
    response="$(curl -fsSL --connect-timeout 10 --max-time 30 "$api_url" 2>/dev/null)"

    if [[ "$filename" =~ \.[a-zA-Z0-9]+$ ]]; then
        file_url="$(echo "$response" | grep -i 'browser_download_url' | grep -i -w "$filter" \
            | grep -i '\.sh\|\.exe\|\.zip' | head -1 | awk -F '"' '{print $4}')"
    else
        file_url="$(echo "$response" | grep -i 'browser_download_url' | grep -i -w "$filter" \
            | head -1 | awk -F '"' '{print $4}')"
    fi

    if [[ -z "$file_url" ]]; then
        skip_line "$filename" "no asset found"
        log "no release asset for $filename via $api_url"
        return
    fi

    if [[ "$file_url" == *.zip ]]; then
        (
            tmp="temp_download.$$.zip"
            curl -fsSL --connect-timeout 10 --max-time 120 "$file_url" -o "$tmp" 2>/dev/null || { rm -f "$tmp"; exit 1; }
            inner="$(unzip -Z1 "$tmp" 2>/dev/null | grep -i "${filename}$" | head -1)"
            [[ -z "$inner" ]] && inner="$(unzip -Z1 "$tmp" 2>/dev/null | grep -i "$filename" | head -1)"
            [[ -z "$inner" ]] && { rm -f "$tmp"; exit 1; }
            unzip -jo "$tmp" "$inner" -d . >/dev/null 2>&1
            base="$(basename "$inner")"
            [[ "$base" != "$filename" && -f "$base" ]] && mv "$base" "$filename" 2>/dev/null
            rm -f "$tmp"
            exit 0
        ) & spinner "$filename" "downloading" "ready"
        [[ $? -eq 0 ]] || log "release zip failed: $file_url"
    else
        (curl -fsSL --connect-timeout 10 --max-time 120 "$file_url" -o "$filename" 2>/dev/null) & spinner "$filename" "downloading" "ready"
        [[ $? -eq 0 ]] || { rm -f "$filename" 2>/dev/null; log "release file failed: $file_url"; }
    fi
}

###############################################################################
# Download helper: single file, refreshed only when the remote copy is newer
###############################################################################
single_file_check_and_download_file() {
    local download_url="$1"
    local local_file="$2"
    local remote_time local_time

    remote_time="$(curl -fsSI --connect-timeout 10 --max-time 15 "$download_url" 2>/dev/null \
        | grep -i 'Last-Modified' | cut -d: -f2- | xargs -I{} date -d {} +%s 2>/dev/null)"

    if [[ -f "$local_file" ]]; then
        local_time="$(stat -c '%Y' "$local_file" 2>/dev/null)"
        if [[ -n "$remote_time" && -n "$local_time" && "$remote_time" -gt "$local_time" ]]; then
            rm -f "$local_file"
            (curl -fsSL --connect-timeout 10 --max-time 120 "$download_url" -o "$local_file" 2>/dev/null) & spinner "$local_file" "updating" "updated"
            [[ $? -eq 0 ]] || { rm -f "$local_file" 2>/dev/null; log "update failed: $download_url"; }
        else
            skip_line "$local_file" "up to date"
        fi
    else
        (curl -fsSL --connect-timeout 10 --max-time 120 "$download_url" -o "$local_file" 2>/dev/null) & spinner "$local_file" "downloading" "ready"
        [[ $? -eq 0 ]] || { rm -f "$local_file" 2>/dev/null; log "download failed: $download_url"; }
    fi
}

###############################################################################
# Download helper: obfuscated payloads (kept in a dedicated sub-folder)
###############################################################################
download_obfuscated_scripts() {
    local download_url="$1"
    local filename="$2"

    if [[ -z "$toolsdir" ]]; then
        err "toolsdir is not set."
        return 1
    fi

    local obftoolsdir="${toolsdir}/obfuscated"
    local local_file="${obftoolsdir}/${filename}"
    mkdir -p "$obftoolsdir" >/dev/null 2>&1 || { err "Could not create ${obftoolsdir}"; return 1; }

    if [[ -f "$local_file" ]]; then
        skip_line "$filename" "already present"
    else
        (curl -fsSL --connect-timeout 10 --max-time 120 "$download_url" -o "$local_file" 2>/dev/null) & spinner "$filename" "downloading" "ready"
        [[ $? -eq 0 ]] || { rm -f "$local_file" 2>/dev/null; log "obfuscated download failed: $download_url"; }
    fi
}

###############################################################################
# Install a single tool
#
#   install_tool <name> <install_cmd> <check_cmd> [<pre_install_cmd>]
###############################################################################
install_tool() {
    local tool_name="$1"
    local install_command="$2"
    local check_command="$3"
    local pre_install_command="$4"

    if eval "$check_command" >/dev/null 2>&1; then
        skip_line "$tool_name" "installed"
        return
    fi

    if [[ -n "$pre_install_command" ]]; then
        if ! eval "$pre_install_command" >>"$LOGFILE" 2>&1; then
            STAT_FAIL=$((STAT_FAIL + 1))
            printf '  %s%s%s  %-*s %s%s%s\n' "$C_RED" "$GLYPH_ERR" "$C_RESET" "$NAME_WIDTH" "$tool_name" "$C_RED" "prep failed" "$C_RESET"
            log "prepare failed: ${tool_name} :: ${pre_install_command}"
            return 1
        fi
    fi

    # Run the install and verify it in the same background job so the spinner's
    # exit code reflects the true outcome.
    ( eval "$install_command" >>"$LOGFILE" 2>&1 && eval "$check_command" >/dev/null 2>&1 ) & spinner "$tool_name" "installing" "installed"
    if [[ $? -ne 0 ]]; then
        log "install failed: ${tool_name} :: ${install_command}"
    fi
}

###############################################################################
# Phase: install tools
###############################################################################
install_tools() {
    if [[ $UID -ne 0 ]]; then
        warn "Installing tools requires elevated privileges."
        sudo -v || { err "sudo authentication failed."; return 1; }
    fi

    reset_stats
    section "Installing tools"

    install_tool "seclists" \
        "sudo apt-get -qq -y install seclists" \
        "[[ -d /usr/share/seclists ]]"

    install_tool "rustscan" \
        "sudo apt-get -qq -y install rustscan >/dev/null 2>&1; if command -v rustscan >/dev/null 2>&1; then true; else deb_url=\$(curl -fsSL --connect-timeout 10 --max-time 30 https://api.github.com/repos/RustScan/RustScan/releases/latest | grep -o 'https://[^\"]*rustscan[^\"]*\\.deb' | head -1); if [[ -z \"\$deb_url\" ]]; then deb_url=\$(curl -fsSL --connect-timeout 10 --max-time 30 https://api.github.com/repos/RustScan/RustScan/releases/latest | grep -o 'https://[^\"]*\\.deb\\.zip' | head -1); fi; if [[ \"\$deb_url\" == *.zip ]]; then wget -q --timeout=60 -O rustscan.deb.zip \"\$deb_url\" && unzip -o rustscan.deb.zip && sudo dpkg -i rustscan*.deb; rm -f rustscan.deb.zip rustscan*.deb; elif [[ -n \"\$deb_url\" ]]; then wget -q --timeout=60 -O rustscan.deb \"\$deb_url\" && sudo dpkg -i rustscan.deb; rm -f rustscan.deb; else false; fi; fi" \
        "command -v rustscan >/dev/null 2>&1"

    install_tool "wfuzz" \
        "sudo apt-get -qq -y install wfuzz" \
        "command -v wfuzz >/dev/null 2>&1"

    install_tool "ffuf" \
        "sudo apt-get -qq -y install ffuf" \
        "command -v ffuf >/dev/null 2>&1"

    install_tool "bloodhound" \
        "sudo apt-get -qq -y install bloodhound" \
        "command -v bloodhound >/dev/null 2>&1"

    install_tool "neo4j" \
        "sudo apt-get -qq -y install neo4j" \
        "command -v neo4j >/dev/null 2>&1"

    install_tool "gobuster" \
        "sudo apt-get -qq -y install gobuster" \
        "command -v gobuster >/dev/null 2>&1"

    install_tool "feroxbuster" \
        "sudo apt-get -qq -y install feroxbuster" \
        "command -v feroxbuster >/dev/null 2>&1"

    install_tool "certipy-ad" \
        "sudo python3 -m pip install -q --break-system-packages certipy-ad || sudo python3 -m pip install -q certipy-ad" \
        "command -v certipy-ad >/dev/null 2>&1"

    install_tool "pypykatz" \
        "sudo python3 -m pip install -q --break-system-packages pypykatz || sudo python3 -m pip install -q pypykatz" \
        "command -v pypykatz >/dev/null 2>&1"

    install_tool "sublime-text" \
        "wget -qO - https://download.sublimetext.com/sublimehq-pub.gpg | gpg --no-default-keyring --keyring ./temp-keyring.gpg --import && gpg --no-default-keyring --keyring ./temp-keyring.gpg --export --output sublime-text.gpg && rm -f temp-keyring.gpg temp-keyring.gpg~ && sudo mkdir -p /usr/local/share/keyrings && sudo mv ./sublime-text.gpg /usr/local/share/keyrings && echo 'deb [signed-by=/usr/local/share/keyrings/sublime-text.gpg] https://download.sublimetext.com/ apt/stable/' | sudo tee /etc/apt/sources.list.d/sublime-text.list && sudo apt-get update -qq && sudo apt-get install -qq -y sublime-text" \
        "command -v subl >/dev/null 2>&1"

    install_tool "docker" \
        "sudo apt-get -qq -y install docker.io" \
        "command -v docker >/dev/null 2>&1"

    install_tool "docker-compose" \
        "sudo apt-get -qq -y install docker-compose" \
        "command -v docker-compose >/dev/null 2>&1"

    install_tool "bloodhound-CE" \
        "curl -fsSL https://ghst.ly/getbhce -o /opt/bloodhoundCE/docker-compose.yml" \
        "[[ -f /opt/bloodhoundCE/docker-compose.yml ]]" \
        "sudo mkdir -p /opt/bloodhoundCE"

    summary
}

###############################################################################
# Phase: download scripts
###############################################################################
download_scripts() {
    toolsdir="/opt/tools"

    info "Choose a directory to download scripts into (Tab completion enabled)."
    toolsdir="$(read_directory "$(printf '  %s%s%s  Directory [%s%s%s]: ' "$C_CYAN" "$GLYPH_INFO" "$C_RESET" "$C_BOLD" "$toolsdir" "$C_RESET")" "$toolsdir")"

    if [[ -d "$toolsdir" ]]; then
        info "Using directory: ${C_BOLD}${toolsdir}${C_RESET}"
    else
        if mkdir -p "$toolsdir" >/dev/null 2>&1; then
            info "Created directory: ${C_BOLD}${toolsdir}${C_RESET}"
        else
            err "No permission to create ${C_BOLD}${toolsdir}${C_RESET}. Re-run with sudo."
            return 1
        fi
    fi

    cd "$toolsdir" || { err "Failed to enter ${toolsdir}"; return 1; }

    reset_stats
    section "Downloading scripts to ${toolsdir}"



#####################################################################################################################
# Latest releases
#####################################################################################################################
#Arguments:
#  1. GitHub API URL: Provides release details (version, download URLs).
#  2. Local Filename: Saves the downloaded file with this name.
#  3. File Filter (optional): Matches the correct file from multiple release assets.

# Usage: api_file_check_and_download_file "API-URL" "local file name" "Filter (Optional)"

# Downloading SharpHound.exe
api_file_check_and_download_file "https://api.github.com/repos/SpecterOps/SharpHound/releases/latest" "SharpHound.exe" "SharpHound"

# Downloading winPEASx64.exe
api_file_check_and_download_file "https://api.github.com/repos/peass-ng/PEASS-ng/releases/latest" "winPEASx64.exe" "winPEASx64"

# Downloading winPEASany.exe
api_file_check_and_download_file "https://api.github.com/repos/peass-ng/PEASS-ng/releases/latest" "winPEASany.exe" "winPEASany"

# Downloading Linpeas.sh
api_file_check_and_download_file "https://api.github.com/repos/peass-ng/PEASS-ng/releases" "linpeas.sh" "linpeas"

# Downloading pspy32
api_file_check_and_download_file "https://api.github.com/repos/DominicBreuker/pspy/releases/latest" "pspy32" "pspy32"

# Downloading pspy64
api_file_check_and_download_file "https://api.github.com/repos/DominicBreuker/pspy/releases/latest" "pspy64" "pspy64"

# Downloading kerbrute_linux_amd64
api_file_check_and_download_file "https://api.github.com/repos/ropnop/kerbrute/releases/latest" "kerbrute_linux_amd64" "kerbrute_linux_amd64"

# Downloading kerbrute_windows_amd64.ex
api_file_check_and_download_file "https://api.github.com/repos/ropnop/kerbrute/releases/latest" "kerbrute_windows_amd64.exe" "kerbrute_windows_amd64.exe"


#####################################################################################################################
# Single files
#####################################################################################################################

#Downloading powercat.ps1
single_file_check_and_download_file "https://github.com/besimorhino/powercat/raw/master/powercat.ps1" "powercat.ps1"


#Downloading Invoke-Mimikatz.ps1
single_file_check_and_download_file "https://github.com/clymb3r/PowerShell/raw/master/Invoke-Mimikatz/Invoke-Mimikatz.ps1" "Invoke-Mimikatz.ps1"


#Downloading Powerview.ps1
single_file_check_and_download_file "https://github.com/PowerShellMafia/PowerSploit/raw/master/Recon/PowerView.ps1" "PowerView.ps1"
    

#Downloading PowerUp.ps1
single_file_check_and_download_file "https://github.com/PowerShellMafia/PowerSploit/raw/master/Privesc/PowerUp.ps1" "PowerUp.ps1"


#Downloading Rubeus.exe
single_file_check_and_download_file "https://github.com/Flangvik/SharpCollection/raw/master/NetFramework_4.7_Any/Rubeus.exe" "Rubeus.exe"


#Downloading Invegih.ps1
single_file_check_and_download_file "https://github.com/Kevin-Robertson/Inveigh/raw/master/Inveigh.ps1" "Inveigh.ps1"


#Downloading nc64.exe
single_file_check_and_download_file "https://github.com/int0x33/nc.exe/raw/master/nc64.exe" "nc64.exe"


#Downloading nc.exe
single_file_check_and_download_file "https://github.com/int0x33/nc.exe/raw/master/nc.exe" "nc.exe"


#Downloading PlumHound.py
single_file_check_and_download_file "https://github.com/PlumHound/PlumHound/raw/master/PlumHound.py" "PlumHound.py"


#Downloading Linux Exploit Suggester
single_file_check_and_download_file "https://github.com/The-Z-Labs/linux-exploit-suggester/raw/master/linux-exploit-suggester.sh" "linux-exploit-suggester.sh"


#Downloading Linux PrivChecker
single_file_check_and_download_file "https://github.com/sleventyeleven/linuxprivchecker/raw/master/linuxprivchecker.py" "linuxprivchecker.py"


#Downloading LinEmnum.sh
single_file_check_and_download_file "https://github.com/rebootuser/LinEnum/raw/master/LinEnum.sh" "LinEnum.sh"


#Downloading Whisker.exe
single_file_check_and_download_file "https://github.com/Flangvik/SharpCollection/raw/master/NetFramework_4.7_Any/Whisker.exe" "Whisker.exe"


#Downloading SharpMapExec.exe
single_file_check_and_download_file "https://github.com/Flangvik/SharpCollection/raw/master/NetFramework_4.7_Any/SharpMapExec.exe" "SharpMapExec.exe"


#Downloading SharpChisel.exe
single_file_check_and_download_file "https://github.com/Flangvik/SharpCollection/raw/master/NetFramework_4.7_Any/SharpChisel.exe" "SharpChisel.exe"


#Downloading Seatbelt.exe
single_file_check_and_download_file "https://github.com/Flangvik/SharpCollection/raw/master/NetFramework_4.7_Any/Seatbelt.exe" "Seatbelt.exe"


#Downloading ADCSPwn.exe
single_file_check_and_download_file "https://github.com/Flangvik/SharpCollection/raw/master/NetFramework_4.7_Any/ADCSPwn.exe" "ADCSPwn.exe"


#Downloading BetterSafetyKatz.exe
single_file_check_and_download_file "https://github.com/Flangvik/SharpCollection/raw/master/NetFramework_4.7_Any/BetterSafetyKatz.exe" "BetterSafetyKatz.exe"


#Downloading PassTheCert.exe
single_file_check_and_download_file "https://github.com/Flangvik/SharpCollection/raw/master/NetFramework_4.7_Any/PassTheCert.exe" "PassTheCert.exe"


#Downloading SharPersist.exe
single_file_check_and_download_file "https://github.com/Flangvik/SharpCollection/raw/master/NetFramework_4.7_x64/SharPersist.exe" "SharPersist.exe"


#Downloading MailSniper.ps1
single_file_check_and_download_file "https://github.com/dafthack/MailSniper/raw/master/MailSniper.ps1" "MailSniper.ps1"


#Downloading ADSearch.exe
single_file_check_and_download_file "https://github.com/Flangvik/SharpCollection/raw/master/NetFramework_4.7_x64/ADSearch.exe" "ADSearch.exe"


#Downloading Invoke-DCOM.ps1
single_file_check_and_download_file "https://github.com/EmpireProject/Empire/raw/master/data/module_source/lateral_movement/Invoke-DCOM.ps1" "Invoke-DCOM.ps1"


#Downloading PowerUpSQL.ps1
single_file_check_and_download_file "https://github.com/NetSPI/PowerUpSQL/raw/master/PowerUpSQL.ps1" "PowerUpSQL.ps1"


#Downloading SharpSCCM.exe
single_file_check_and_download_file "https://github.com/Flangvik/SharpCollection/raw/master/NetFramework_4.7_x64/SharpSCCM.exe" "SharpSCCM.exe"


#Downloading LAPSToolkit.ps1
single_file_check_and_download_file "https://github.com/leoloobeek/LAPSToolkit/raw/master/LAPSToolkit.ps1" "LAPSToolkit.ps1"


#Downloading Certify.exe
single_file_check_and_download_file "https://github.com/Flangvik/SharpCollection/raw/master/NetFramework_4.5_Any/Certify.exe" "Certify.exe"


#Downloading Inveigh.exe
single_file_check_and_download_file "https://github.com/Flangvik/SharpCollection/raw/master/NetFramework_4.5_Any/Inveigh.exe" "Inveigh.exe"


#Downloading Invoke-RunasCs.ps1
single_file_check_and_download_file "https://github.com/antonioCoco/RunasCs/raw/refs/heads/master/Invoke-RunasCs.ps1" "Invoke-RunasCs.ps1"


#Downloading Snaffler.exe
single_file_check_and_download_file "https://github.com/Flangvik/SharpCollection/raw/master/NetFramework_4.7_Any/Snaffler.exe" "Snaffler.exe"



#####################################################################################################################
# GIT Download
#####################################################################################################################

#Downloading AutoRecon
git_download "https://github.com/Tib3rius/AutoRecon.git" "AutoRecon"

#Downloading PassTheCert
git_download "https://github.com/AlmondOffSec/PassTheCert.git" "PassTheCert"

#Downloading PetitPotam
git_download "https://github.com/topotam/PetitPotam.git" "PetitPotam"

#Downloading SprayingToolkit
git_download "https://github.com/byt3bl33d3r/SprayingToolkit.git" "SprayingToolkit"

#Downloading BloodHound.py for Community Edition Bloodhound (CE)
git_download "https://github.com/dirkjanm/BloodHound.py.git" "bloodhound.py"


#####################################################################################################################
# ZIP folder Download
#####################################################################################################################

#Downloading Microsoft sysinternal PSTools
folder_zip_download "https://download.sysinternals.com/files/PSTools.zip" "PSTools.zip" "PSTools"

#Downloading Mimikatz (latest version)
mimikatz_url=$(curl -sL --connect-timeout 10 --max-time 30 "https://api.github.com/repos/gentilkiwi/mimikatz/releases/latest" | grep "browser_download_url.*mimikatz_trunk.zip" | head -1 | awk -F '"' '{print $4}')
if [[ -n "$mimikatz_url" ]]; then
    folder_zip_download "$mimikatz_url" "mimikatz_trunk.zip" "mimikatz"
else
    warn "Could not fetch latest mimikatz version, using fallback"
    folder_zip_download "https://github.com/gentilkiwi/mimikatz/releases/download/2.2.0-20220919/mimikatz_trunk.zip" "mimikatz_trunk.zip" "mimikatz"
fi


#####################################################################################################################
# ZIP or gz single file Download
#####################################################################################################################

#Downloading RunasCs.exe (latest version)
runascs_url=$(curl -sL --connect-timeout 10 --max-time 30 "https://api.github.com/repos/antonioCoco/RunasCs/releases/latest" | grep "browser_download_url.*RunasCs.zip" | head -1 | awk -F '"' '{print $4}')
if [[ -n "$runascs_url" ]]; then
    single_file_zip_gz "$runascs_url" "RunasCS.zip"
else
    warn "Could not fetch latest RunasCs version, using fallback"
    single_file_zip_gz "https://github.com/antonioCoco/RunasCs/releases/download/v1.5/RunasCs.zip" "RunasCS.zip"
fi

#Downloading chisel (latest version)
chisel_url=$(curl -sL --connect-timeout 10 --max-time 30 "https://api.github.com/repos/jpillora/chisel/releases/latest" | grep "browser_download_url.*linux_amd64.gz" | head -1 | awk -F '"' '{print $4}')
chisel_filename=$(basename "$chisel_url" 2>/dev/null)
if [[ -n "$chisel_url" && -n "$chisel_filename" ]]; then
    single_file_zip_gz "$chisel_url" "$chisel_filename"
else
    warn "Could not fetch latest chisel version, using fallback"
    single_file_zip_gz "https://github.com/jpillora/chisel/releases/download/v1.10.1/chisel_1.10.1_linux_amd64.gz" "chisel_1.10.1_linux_amd64.gz"
fi


    perform_cleanup
    summary
}

###############################################################################
# Phase: download obfuscated payloads
###############################################################################
obfuscated_scripts() {
    toolsdir="${toolsdir:-/opt/tools}"

    info "Choose a base directory; an ${C_BOLD}obfuscated${C_RESET} sub-folder will be created inside it."
    toolsdir="$(read_directory "$(printf '  %s%s%s  Directory [%s%s%s]: ' "$C_CYAN" "$GLYPH_INFO" "$C_RESET" "$C_BOLD" "$toolsdir" "$C_RESET")" "$toolsdir")"

    if [[ ! -d "$toolsdir" ]]; then
        mkdir -p "$toolsdir" >/dev/null 2>&1 || { err "Cannot create ${C_BOLD}${toolsdir}${C_RESET}"; return 1; }
        info "Created directory: ${C_BOLD}${toolsdir}/obfuscated${C_RESET}"
    else
        info "Using directory: ${C_BOLD}${toolsdir}/obfuscated${C_RESET}"
    fi

    reset_stats
    section "Downloading obfuscated payloads"

# Downloading Certify.exe._obf.exe
download_obfuscated_scripts "https://raw.githubusercontent.com/Flangvik/ObfuscatedSharpCollection/main/NetFramework_4.7_Any/Certify.exe._obf.exe" "Certify.exe._obf.exe"

# Downloading Rubeus.exe._obf.exe
download_obfuscated_scripts "https://raw.githubusercontent.com/Flangvik/ObfuscatedSharpCollection/main/NetFramework_4.7_Any/Rubeus.exe._obf.exe" "Rubeus.exe._obf.exe"

# Downloading Seatbelt.exe._obf.exe
download_obfuscated_scripts "https://raw.githubusercontent.com/Flangvik/ObfuscatedSharpCollection/main/NetFramework_4.7_Any/Seatbelt.exe._obf.exe" "Seatbelt.exe._obf.exe"

# Downloading SharpEDRChecker.exe._obf.exe
download_obfuscated_scripts "https://raw.githubusercontent.com/Flangvik/ObfuscatedSharpCollection/main/NetFramework_4.7_Any/SharpEDRChecker.exe._obf.exe" "SharpEDRChecker.exe._obf.exe"

# Downloading SharpHound.exe._obf.exe
download_obfuscated_scripts "https://raw.githubusercontent.com/Flangvik/ObfuscatedSharpCollection/main/NetFramework_4.7_Any/SharpHound.exe._obf.exe" "SharpHound.exe._obf.exe"

# Downloading SharpSCCM.exe._obf.exe
download_obfuscated_scripts "https://raw.githubusercontent.com/Flangvik/ObfuscatedSharpCollection/main/NetFramework_4.7_Any/SharpSCCM.exe._obf.exe" "SharpSCCM.exe._obf.exe"

# Downloading SharpView.exe._obf.exe
download_obfuscated_scripts "https://raw.githubusercontent.com/Flangvik/ObfuscatedSharpCollection/main/NetFramework_4.7_Any/SharpView.exe._obf.exe" "SharpView.exe._obf.exe"

# Downloading Snaffler.exe._obf.exe
download_obfuscated_scripts "https://raw.githubusercontent.com/Flangvik/ObfuscatedSharpCollection/main/NetFramework_4.7_Any/Snaffler.exe._obf.exe" "Snaffler.exe._obf.exe"

# Downloading StickyNotesExtract.exe._obf.exe
download_obfuscated_scripts "https://raw.githubusercontent.com/Flangvik/ObfuscatedSharpCollection/main/NetFramework_4.7_Any/StickyNotesExtract.exe._obf.exe" "StickyNotesExtract.exe._obf.exe"

# Downloading Whisker.exe._obf.exe
download_obfuscated_scripts "https://raw.githubusercontent.com/Flangvik/ObfuscatedSharpCollection/main/NetFramework_4.7_Any/Whisker.exe._obf.exe" "Whisker.exe._obf.exe"

# Downloading winPEAS.exe._obf.exe
download_obfuscated_scripts "https://raw.githubusercontent.com/Flangvik/ObfuscatedSharpCollection/main/NetFramework_4.7_Any/winPEAS.exe._obf.exe" "winPEAS.exe._obf.exe"

# Downloading SharpWebServer.exe._obf.exe
download_obfuscated_scripts "https://raw.githubusercontent.com/Flangvik/ObfuscatedSharpCollection/main/NetFramework_4.7_Any/SharpWebServer.exe._obf.exe" "SharpWebServer.exe._obf.exe"

# Downloading SharpNoPSExec.exe._obf.exe
download_obfuscated_scripts "https://raw.githubusercontent.com/Flangvik/ObfuscatedSharpCollection/main/NetFramework_4.7_Any/SharpNoPSExec.exe._obf.exe" "SharpNoPSExec.exe._obf.exe"

# Downloading SharpMapExec.exe._obf.exe
download_obfuscated_scripts "https://raw.githubusercontent.com/Flangvik/ObfuscatedSharpCollection/main/NetFramework_4.7_Any/SharpMapExec.exe._obf.exe" "SharpMapExec.exe._obf.exe"

# Downloading SharpKatz.exe._obf.exe
download_obfuscated_scripts "https://raw.githubusercontent.com/Flangvik/ObfuscatedSharpCollection/main/NetFramework_4.7_Any/SharpKatz.exe._obf.exe" "SharpKatz.exe._obf.exe"

# Downloading ADCSPwn.exe._obf.exe
download_obfuscated_scripts "https://raw.githubusercontent.com/Flangvik/ObfuscatedSharpCollection/main/NetFramework_4.7_Any/ADCSPwn.exe._obf.exe" "ADCSPwn.exe._obf.exe"

# Downloading ADCollector.exe._obf.exe
download_obfuscated_scripts "https://raw.githubusercontent.com/Flangvik/ObfuscatedSharpCollection/main/NetFramework_4.7_Any/ADCollector.exe._obf.exe" "ADCollector.exe._obf.exe"

    summary
}

###############################################################################
# Phase: add custom shell functions to ~/.zshrc
###############################################################################
add_custom_functions() {
    toolsdir="${toolsdir:-/opt/tools}"
    section "Adding custom shell functions"

    # ----- servtools: quick HTTP server from the tools directory -------------
    if grep -q 'servtools()' "$zshrc_file" 2>/dev/null; then
        skip_line "servtools" "already added"
    else
        {
            echo ""
            echo "# ---- SecTools additions ----"
            echo "# HTTP server that serves files from the tools directory."
            echo "# Usage: servtools <port> [--obf]"
            echo "servtools() {"
            echo '    GREEN="\e[32m"'
            echo '    BLUE="\e[34m"'
            echo '    NC="\e[0m"'
            echo "    PORT=\$1"
            echo "    if [[ \$2 == '--obf' ]]; then"
            echo '        DIR="'"${toolsdir}"'/obfuscated"'
            echo "    else"
            echo '        DIR="'"${toolsdir}"'"'
            echo "    fi"
            echo "    IP=\$(ip -4 addr show tun0 2>/dev/null | grep -oP \"(?<=inet ).*(?=/)\")"
            echo '    echo -e "${GREEN}Files in directory ${BLUE}[${DIR}]${NC}"'
            echo '    ls ${DIR}'
            echo '    echo -e "${GREEN}-------------------------------------------------------------------------${NC}"'
            echo "    echo -e \"[OK] Starting HTTP server from \${GREEN}[\$DIR]\${NC} on \$PORT\""
            echo "    echo -e \"[OK] Address: http://\$IP:\$PORT/\""
            echo "    python3 -m http.server \$PORT --directory \$DIR"
            echo "}"
        } >> "$zshrc_file" 2>/dev/null
        ok "servtools added. Reopen your terminal and run: ${C_BOLD}servtools <port> [--obf]${C_RESET}"
    fi

    # ----- extract_ports: comma-separated port list from tool output ---------
    if grep -q 'extract_ports()' "$zshrc_file" 2>/dev/null; then
        skip_line "extract_ports" "already added"
    else
        {
            echo ""
            echo "# Extract ports as a comma-separated list (e.g. from RustScan output)."
            echo "# Usage: extract_ports <file>"
            echo "extract_ports() {"
            echo '    if [[ -z "$1" ]]; then'
            echo '        echo "Usage: extract_ports <filename>"'
            echo '        return 1'
            echo '    fi'
            echo "    awk '{print \$1}' \"\$1\" | grep -o '^[0-9]*' | paste -sd,"
            echo "}"
        } >> "$zshrc_file" 2>/dev/null
        ok "extract_ports added. Reopen your terminal and run: ${C_BOLD}extract_ports <file>${C_RESET}"
    fi
}

###############################################################################
# Menu
###############################################################################
menu_choice() {
    printf '\n  %s%s%s %sWhat would you like to do?%s\n' "$C_CYAN" "$GLYPH_ARROW" "$C_RESET" "$C_BOLD" "$C_RESET"
    printf '    %s1%s  Install tools\n'              "$C_CYAN" "$C_RESET"
    printf '    %s2%s  Download scripts\n'           "$C_CYAN" "$C_RESET"
    printf '    %s3%s  Download obfuscated scripts\n' "$C_CYAN" "$C_RESET"
    printf '    %s4%s  Add custom shell functions\n' "$C_CYAN" "$C_RESET"
    printf '    %s5%s  All of the above\n'           "$C_CYAN" "$C_RESET"
    printf '    %s0%s  Exit\n'                       "$C_CYAN" "$C_RESET"

    local choice
    read -r -p "$(printf '\n  %s%s%s  Enter choice [0-5]: ' "$C_CYAN" "$GLYPH_INFO" "$C_RESET")" choice

    case "$choice" in
        1) install_tools ;;
        2) download_scripts ;;
        3) obfuscated_scripts ;;
        4) add_custom_functions ;;
        5)
            install_tools
            download_scripts
            obfuscated_scripts
            add_custom_functions
            ;;
        0)
            info "Exiting."
            exit 0
            ;;
        *)
            warn "Invalid option. Choose a number between 0 and 5."
            menu_choice
            ;;
    esac
}

###############################################################################
# Main
###############################################################################
main() {
    print_banner

    if ! check_network; then
        err "No network connection. Exiting."
        exit 1
    fi

    require_dependencies

    ask_update
    ask_upgrade
    menu_choice

    printf '\n  %s%s Done.%s\n\n' "$C_GREEN" "$GLYPH_OK" "$C_RESET"
}

main "$@"
