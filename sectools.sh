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
bashrc_file="${user_home}/.bashrc"
user_name="${SUDO_USER:-$(whoami)}"
LOGFILE="${startdir}/sectools.log"

# Fully non-interactive apt: prevents installs (e.g. docker.io) from hanging
# forever on debconf / needrestart prompts that would be invisible behind the
# spinner. Keeps existing config files on conflict.
APT_GET="sudo DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"

SECTOOLS_VERSION="2.0"

# Runtime flags (overridden by CLI arguments in main()).
ASSUME_YES=0        # -y : don't prompt; use defaults
PRESET_DIR=""       # --dir PATH : download target, skips the directory prompt
DO_UPDATE=0         # --update / -y : run apt update
DO_UPGRADE=0        # --upgrade : run apt upgrade
DRY_RUN=0           # --dry-run : show what would happen, change nothing
ONLY_LIST=""        # --only a,b,c : restrict the tool phase to these tools
SKIP_LIST=""        # --skip a,b,c : exclude these tools from the tool phase

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

# dry_line <name> <note> - a "would do X" line for --dry-run (no counters touched)
dry_line() {
    printf '  %s%s%s  %-*s %s%s%s\n' \
        "$C_CYAN" "$GLYPH_INFO" "$C_RESET" "$NAME_WIDTH" "$1" "$C_CYAN" "${2:-would install}" "$C_RESET"
}

# in_csv <name> <comma,separated,list> - true if name is an exact element
in_csv() {
    local csv=",${2},"
    [[ "$csv" == *",${1},"* ]]
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
        local start=$SECONDS elapsed tsuffix
        printf '\e[?25l'                                   # hide cursor
        while kill -0 "$pid" 2>/dev/null; do
            elapsed=$((SECONDS - start))
            # Show an elapsed timer once a task runs long, so a slow download
            # (e.g. docker) reads as "working" rather than "frozen".
            if [[ $elapsed -ge 2 ]]; then tsuffix=" (${elapsed}s)"; else tsuffix=""; fi
            printf '\r  %s%s%s  %-*s %s%s%s%s' \
                "$C_YELLOW" "${SPIN_FRAMES[i]}" "$C_RESET" \
                "$NAME_WIDTH" "$name" "$C_DIM" "$action" "$tsuffix" "$C_RESET"
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
            ($APT_GET -qq -y install "${missing[@]}" >>"$LOGFILE" 2>&1) & spinner "dependencies" "installing" "ready"
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
run_update()  { ($APT_GET -q update >>"$LOGFILE" 2>&1)    & spinner "apt update"  "refreshing package lists" "updated"; }
run_upgrade() { ($APT_GET -q -y upgrade >>"$LOGFILE" 2>&1) & spinner "apt upgrade" "upgrading packages"      "upgraded"; }

ask_update() {
    local choice
    read -r -p "$(printf '  %s%s%s  Run %ssudo apt update%s now? [y/N] ' "$C_CYAN" "$GLYPH_INFO" "$C_RESET" "$C_BOLD" "$C_RESET")" choice
    case "$choice" in
        [Yy]*) run_update ;;
        *)     skip_line "apt update" "skipped" ;;
    esac
}

ask_upgrade() {
    local choice
    read -r -p "$(printf '  %s%s%s  Run %ssudo apt upgrade%s now? [y/N] ' "$C_CYAN" "$GLYPH_INFO" "$C_RESET" "$C_BOLD" "$C_RESET")" choice
    case "$choice" in
        [Yy]*) run_upgrade ;;
        *)     skip_line "apt upgrade" "skipped" ;;
    esac
}

###############################################################################
# Download helper: git clone
###############################################################################
git_download() {
    local repo_url="$1"
    local repo_name="$2"
    [[ "$DRY_RUN" -eq 1 ]] && { dry_line "$repo_name" "would clone"; return; }
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
    [[ "$DRY_RUN" -eq 1 ]] && { dry_line "$extract_dir" "would download"; return; }
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
    [[ "$DRY_RUN" -eq 1 ]] && { dry_line "$label" "would download"; return; }
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
    [[ "$DRY_RUN" -eq 1 ]] && { dry_line "$filename" "would download"; return; }

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
    [[ "$DRY_RUN" -eq 1 ]] && { dry_line "$local_file" "would download"; return; }
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
    [[ "$DRY_RUN" -eq 1 ]] && { dry_line "$filename" "would download"; return; }

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
# Run a command as the invoking (non-root) user
#
# The script is normally run with sudo, but some tools must be installed into
# the user's own HOME and shell config, not root's. When we are root via sudo,
# drop back to $SUDO_USER (with -H so $HOME is theirs); otherwise run directly.
###############################################################################
run_as_user() {
    if [[ $EUID -eq 0 && -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
        sudo -u "$SUDO_USER" -H bash -c "$1"
    else
        bash -c "$1"
    fi
}

# Give a file back to the invoking user when we are root via sudo, so files we
# write into their HOME (e.g. rc files) are not left owned by root.
chown_user() {
    [[ $EUID -eq 0 && -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]] || return 0
    chown "$SUDO_USER:$(id -gn "$SUDO_USER" 2>/dev/null || echo "$SUDO_USER")" "$1" 2>/dev/null
}

###############################################################################
# fzf - installed in the context of the user (never root), non-interactively
###############################################################################
install_fzf() {
    local target="${user_home}/.fzf"
    # --all runs the installer non-interactively (key bindings + completion +
    # rc update) so it never blocks on prompts behind the spinner.
    run_as_user "rm -rf '$target' && git clone --depth 1 https://github.com/junegunn/fzf.git '$target' && '$target'/install --all"
}

###############################################################################
# ProjectDiscovery Go tools (nuclei, httpx, subfinder) - track the latest
# upstream release, because the distro packages lag noticeably.
#
#   pd_is_latest    <binary> <owner/repo>   (check-command)
#   install_pd_tool <binary> <owner/repo>   (install-command)
###############################################################################

# Highest semver reported by an installed binary, or empty if not installed.
_pd_installed_version() {
    command -v "$1" >/dev/null 2>&1 || return 0
    "$1" -version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

# Latest semver published for owner/repo, or empty if it can't be fetched.
_pd_latest_version() {
    curl -fsSL --connect-timeout 10 --max-time 30 "https://api.github.com/repos/$1/releases/latest" 2>/dev/null \
        | grep -oE '"tag_name":[[:space:]]*"v?[0-9]+\.[0-9]+\.[0-9]+"' \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

# Check-command: true when <binary> is present AND not older than the latest
# release of <owner/repo>, so install_tool only (re)installs when it is missing
# or outdated. A newer/dev build is left alone; an unreachable API is treated as
# "current" so a working install is never churned.
pd_is_latest() {
    local cur latest newest
    cur="$(_pd_installed_version "$1")"
    [[ -n "$cur" ]] || return 1
    latest="$(_pd_latest_version "$2")"
    [[ -n "$latest" ]] || return 0
    newest="$(printf '%s\n%s\n' "$cur" "$latest" | sort -V | tail -1)"
    [[ "$newest" == "$cur" ]]
}

# Install the latest linux_amd64 release of <binary> from <owner/repo> into
# /usr/local/bin, first removing whatever distro package currently owns the
# binary on PATH so no stale duplicate shadows it.
install_pd_tool() {
    local bin="$1" repo="$2" url tmp cur_bin owner
    url="$(curl -fsSL --connect-timeout 10 --max-time 30 "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null \
        | grep -oE "https://[^\"]*${bin}_[^\"]*linux_amd64\\.zip" | head -1)"
    [[ -n "$url" ]] || { echo "could not resolve latest ${bin} linux_amd64 asset"; return 1; }

    cur_bin="$(command -v "$bin" 2>/dev/null || true)"
    if [[ -n "$cur_bin" ]]; then
        owner="$(dpkg -S "$cur_bin" 2>/dev/null | cut -d: -f1)"
        [[ -n "$owner" ]] && sudo apt-get -qq -y remove "$owner" >/dev/null 2>&1 || true
    fi

    tmp="$(mktemp -d)"
    curl -fsSL --max-time 120 "$url" -o "$tmp/${bin}.zip" || { rm -rf "$tmp"; return 1; }
    unzip -o "$tmp/${bin}.zip" -d "$tmp" >/dev/null 2>&1 || { rm -rf "$tmp"; return 1; }
    sudo install -m 0755 "$tmp/$bin" "/usr/local/bin/$bin" || { rm -rf "$tmp"; return 1; }
    rm -rf "$tmp"
    hash -r 2>/dev/null || true
}

###############################################################################
# Phase: install tools
###############################################################################
# -----------------------------------------------------------------------------
# Tool registry
#
#   tool <name> <install-cmd> <check-cmd> [<pre-install-cmd>]
#
# Everything the installer knows lives in this table. Adding a tool is a single
# `tool ...` line below; the installer loop and the menu pick it up automatically.
# -----------------------------------------------------------------------------
T_NAME=(); T_INST=(); T_CHK=(); T_PRE=()
tool() { T_NAME+=("$1"); T_INST+=("$2"); T_CHK+=("$3"); T_PRE+=("${4:-}"); }

define_tools() {
    tool "seclists" \
        "$APT_GET -qq -y install seclists" \
        "[[ -d /usr/share/seclists ]]"

    tool "rustscan" \
        "$APT_GET -qq -y install rustscan >/dev/null 2>&1; if command -v rustscan >/dev/null 2>&1; then true; else deb_url=\$(curl -fsSL --connect-timeout 10 --max-time 30 https://api.github.com/repos/RustScan/RustScan/releases/latest | grep -o 'https://[^\"]*rustscan[^\"]*\\.deb' | head -1); if [[ -z \"\$deb_url\" ]]; then deb_url=\$(curl -fsSL --connect-timeout 10 --max-time 30 https://api.github.com/repos/RustScan/RustScan/releases/latest | grep -o 'https://[^\"]*\\.deb\\.zip' | head -1); fi; if [[ \"\$deb_url\" == *.zip ]]; then wget -q --timeout=60 -O rustscan.deb.zip \"\$deb_url\" && unzip -o rustscan.deb.zip && sudo dpkg -i rustscan*.deb; rm -f rustscan.deb.zip rustscan*.deb; elif [[ -n \"\$deb_url\" ]]; then wget -q --timeout=60 -O rustscan.deb \"\$deb_url\" && sudo dpkg -i rustscan.deb; rm -f rustscan.deb; else false; fi; fi" \
        "command -v rustscan >/dev/null 2>&1"

    tool "wfuzz" \
        "$APT_GET -qq -y install wfuzz" \
        "command -v wfuzz >/dev/null 2>&1"

    tool "ffuf" \
        "$APT_GET -qq -y install ffuf" \
        "command -v ffuf >/dev/null 2>&1"

    tool "gobuster" \
        "$APT_GET -qq -y install gobuster" \
        "command -v gobuster >/dev/null 2>&1"

    tool "feroxbuster" \
        "$APT_GET -qq -y install feroxbuster" \
        "command -v feroxbuster >/dev/null 2>&1"

    tool "certipy-ad" \
        "sudo python3 -m pip install -q --break-system-packages certipy-ad || sudo python3 -m pip install -q certipy-ad" \
        "command -v certipy-ad >/dev/null 2>&1"

    tool "pypykatz" \
        "sudo python3 -m pip install -q --break-system-packages pypykatz || sudo python3 -m pip install -q pypykatz" \
        "command -v pypykatz >/dev/null 2>&1"

    tool "sublime-text" \
        "wget -qO - https://download.sublimetext.com/sublimehq-pub.gpg | gpg --no-default-keyring --keyring ./temp-keyring.gpg --import && gpg --no-default-keyring --keyring ./temp-keyring.gpg --export --output sublime-text.gpg && rm -f temp-keyring.gpg temp-keyring.gpg~ && sudo mkdir -p /usr/local/share/keyrings && sudo mv ./sublime-text.gpg /usr/local/share/keyrings && echo 'deb [signed-by=/usr/local/share/keyrings/sublime-text.gpg] https://download.sublimetext.com/ apt/stable/' | sudo tee /etc/apt/sources.list.d/sublime-text.list && $APT_GET update -qq && $APT_GET install -qq -y sublime-text" \
        "command -v subl >/dev/null 2>&1"

    tool "docker" \
        "$APT_GET -qq -y install docker.io" \
        "command -v docker >/dev/null 2>&1"

    tool "docker-compose" \
        "$APT_GET -qq -y install docker-compose" \
        "command -v docker-compose >/dev/null 2>&1"

    tool "bloodhound-CE" \
        "curl -fsSL https://ghst.ly/getbhce -o /opt/bloodhoundCE/docker-compose.yml" \
        "[[ -f /opt/bloodhoundCE/docker-compose.yml ]]" \
        "sudo mkdir -p /opt/bloodhoundCE"

    # --- Active Directory / network tooling (apt on Kali, pip/gem fallback) ---
    tool "netexec" \
        "$APT_GET -qq -y install netexec || sudo python3 -m pip install -q --break-system-packages netexec || sudo python3 -m pip install -q netexec" \
        "command -v netexec >/dev/null 2>&1 || command -v nxc >/dev/null 2>&1"

    tool "impacket" \
        "$APT_GET -qq -y install impacket-scripts || sudo python3 -m pip install -q --break-system-packages impacket || sudo python3 -m pip install -q impacket" \
        "command -v impacket-secretsdump >/dev/null 2>&1 || command -v secretsdump.py >/dev/null 2>&1"

    tool "responder" \
        "$APT_GET -qq -y install responder" \
        "command -v responder >/dev/null 2>&1"

    tool "mitm6" \
        "$APT_GET -qq -y install mitm6 || sudo python3 -m pip install -q --break-system-packages mitm6 || sudo python3 -m pip install -q mitm6" \
        "command -v mitm6 >/dev/null 2>&1"

    tool "evil-winrm" \
        "$APT_GET -qq -y install evil-winrm || sudo gem install evil-winrm" \
        "command -v evil-winrm >/dev/null 2>&1"

    tool "enum4linux-ng" \
        "$APT_GET -qq -y install enum4linux-ng || sudo python3 -m pip install -q --break-system-packages enum4linux-ng || sudo python3 -m pip install -q enum4linux-ng" \
        "command -v enum4linux-ng >/dev/null 2>&1"

    tool "ldapdomaindump" \
        "$APT_GET -qq -y install ldapdomaindump || sudo python3 -m pip install -q --break-system-packages ldapdomaindump || sudo python3 -m pip install -q ldapdomaindump" \
        "command -v ldapdomaindump >/dev/null 2>&1"

    tool "smbmap" \
        "$APT_GET -qq -y install smbmap || sudo python3 -m pip install -q --break-system-packages smbmap || sudo python3 -m pip install -q smbmap" \
        "command -v smbmap >/dev/null 2>&1"

    # --- Recon / pivoting -----------------------------------------------------
    tool "pipx" \
        "$APT_GET -qq -y install pipx || sudo python3 -m pip install -q --break-system-packages pipx" \
        "command -v pipx >/dev/null 2>&1"

    tool "fzf" \
        "install_fzf" \
        "[[ -x \"${user_home}/.fzf/bin/fzf\" ]] || command -v fzf >/dev/null 2>&1"

    tool "bat" \
        "$APT_GET -qq -y install bat" \
        "command -v batcat >/dev/null 2>&1 || command -v bat >/dev/null 2>&1"

    tool "masscan" \
        "$APT_GET -qq -y install masscan" \
        "command -v masscan >/dev/null 2>&1"

    tool "nuclei" \
        "install_pd_tool nuclei projectdiscovery/nuclei" \
        "pd_is_latest nuclei projectdiscovery/nuclei"

    tool "httpx" \
        "install_pd_tool httpx projectdiscovery/httpx" \
        "pd_is_latest httpx projectdiscovery/httpx"

    tool "subfinder" \
        "install_pd_tool subfinder projectdiscovery/subfinder" \
        "pd_is_latest subfinder projectdiscovery/subfinder"

    tool "coercer" \
        "$APT_GET -qq -y install coercer || sudo python3 -m pip install -q --break-system-packages coercer || sudo python3 -m pip install -q coercer" \
        "command -v coercer >/dev/null 2>&1"

    tool "bloodyAD" \
        "$APT_GET -qq -y install bloodyad || sudo python3 -m pip install -q --break-system-packages bloodyAD || sudo python3 -m pip install -q bloodyAD" \
        "command -v bloodyAD >/dev/null 2>&1"

    tool "ligolo-ng" \
        "$APT_GET -qq -y install ligolo-ng || { lg_url=\$(curl -fsSL --connect-timeout 10 --max-time 30 https://api.github.com/repos/nicocha30/ligolo-ng/releases/latest | grep -o 'https://[^\"]*proxy[^\"]*linux_amd64.tar.gz' | head -1); [ -n \"\$lg_url\" ] && curl -fsSL --max-time 120 \"\$lg_url\" -o /tmp/ligolo.tgz && sudo tar -xzf /tmp/ligolo.tgz -C /usr/local/bin proxy && sudo mv -f /usr/local/bin/proxy /usr/local/bin/ligolo-proxy && rm -f /tmp/ligolo.tgz; }" \
        "command -v ligolo-proxy >/dev/null 2>&1 || command -v ligolo-ng >/dev/null 2>&1"
}

install_tools() {
    [[ ${#T_NAME[@]} -eq 0 ]] && define_tools

    if [[ "$DRY_RUN" -ne 1 && $UID -ne 0 ]]; then
        warn "Installing tools requires elevated privileges."
        sudo -v || { err "sudo authentication failed."; return 1; }
    fi

    local i name
    if [[ "$DRY_RUN" -eq 1 ]]; then
        section "Installing tools (dry run)"
        local want=0 have=0
        for i in "${!T_NAME[@]}"; do
            name="${T_NAME[i]}"
            [[ -n "$ONLY_LIST" ]] && ! in_csv "$name" "$ONLY_LIST" && continue
            [[ -n "$SKIP_LIST" ]] && in_csv "$name" "$SKIP_LIST" && { skip_line "$name" "skipped"; continue; }
            if eval "${T_CHK[i]}" >/dev/null 2>&1; then
                skip_line "$name" "present"; have=$((have + 1))
            else
                dry_line "$name" "would install"; want=$((want + 1))
            fi
        done
        rule
        info "${want} would be installed, ${have} already present"
        return
    fi

    reset_stats
    section "Installing tools"
    for i in "${!T_NAME[@]}"; do
        name="${T_NAME[i]}"
        [[ -n "$ONLY_LIST" ]] && ! in_csv "$name" "$ONLY_LIST" && continue
        [[ -n "$SKIP_LIST" ]] && in_csv "$name" "$SKIP_LIST" && { skip_line "$name" "skipped"; continue; }
        install_tool "$name" "${T_INST[i]}" "${T_CHK[i]}" "${T_PRE[i]}"
    done
    summary
}

###############################################################################
# Phase: download scripts
###############################################################################
# choose_dir <default> - set global `toolsdir`, prompting only when interactive.
# Honours --dir (PRESET_DIR) and -y (ASSUME_YES), and falls back to the default
# when stdin is not a terminal (e.g. piped) so it never blocks.
choose_dir() {
    local default="$1"
    if [[ -n "$PRESET_DIR" ]]; then
        toolsdir="$PRESET_DIR"
    elif [[ "$ASSUME_YES" -eq 1 || ! -t 0 ]]; then
        toolsdir="$default"
    else
        info "Choose a download directory (Tab completion enabled)."
        toolsdir="$(read_directory "$(printf '  %s%s%s  Directory [%s%s%s]: ' "$C_CYAN" "$GLYPH_INFO" "$C_RESET" "$C_BOLD" "$default" "$C_RESET")" "$default")"
    fi
}

download_scripts() {
    choose_dir "/opt/tools"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        reset_stats
        section "Downloading scripts to ${toolsdir} (dry run)"
    else
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
    fi



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


    [[ "$DRY_RUN" -eq 1 ]] || perform_cleanup
    summary
}

###############################################################################
# Phase: download obfuscated payloads
###############################################################################
obfuscated_scripts() {
    choose_dir "${toolsdir:-/opt/tools}"

    if [[ "$DRY_RUN" -ne 1 ]]; then
        if [[ ! -d "$toolsdir" ]]; then
            mkdir -p "$toolsdir" >/dev/null 2>&1 || { err "Cannot create ${C_BOLD}${toolsdir}${C_RESET}"; return 1; }
            info "Created directory: ${C_BOLD}${toolsdir}/obfuscated${C_RESET}"
        else
            info "Using directory: ${C_BOLD}${toolsdir}/obfuscated${C_RESET}"
        fi
    fi

    reset_stats
    section "Downloading obfuscated payloads$([[ "$DRY_RUN" -eq 1 ]] && echo ' (dry run)')"

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

    if [[ "$DRY_RUN" -eq 1 ]]; then
        section "Adding custom shell functions (dry run)"
        dry_line "servtools"       "would add to ~/.zshrc"
        dry_line "extract_ports"   "would add to ~/.zshrc"
        dry_line "bloodhound-ce"   "would add to ~/.zshrc"
        dry_line "cat -> bat alias" "would add to shell rc"
        dry_line "rockyou.txt"     "would extract if present"
        return
    fi

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

    # ----- bloodhound-ce: spin BloodHound CE up/down without the compose line -
    if grep -q 'bloodhound-ce()' "$zshrc_file" 2>/dev/null; then
        skip_line "bloodhound-ce" "already added"
    else
        cat >> "$zshrc_file" 2>/dev/null <<'BHCE'

# Manage BloodHound Community Edition without the long docker compose command.
# Usage: bloodhound-ce [up|down|logs|pull|status]   (default: up)
bloodhound-ce() {
    local compose="/opt/bloodhoundCE/docker-compose.yml"
    if [[ ! -f "$compose" ]]; then
        echo "BloodHound CE not installed ($compose missing). Run sectools.sh --tools first."
        return 1
    fi
    local dc; if docker compose version >/dev/null 2>&1; then dc="docker compose"; else dc="docker-compose"; fi
    local sudo=""; docker info >/dev/null 2>&1 || sudo="sudo"
    case "${1:-up}" in
        up|start)
            echo "[*] Starting BloodHound CE ..."
            $sudo $dc -f "$compose" up -d || return 1
            echo "[+] BloodHound CE: http://localhost:8080  (login: admin)"
            echo "[*] First run only - reveal the initial password with:"
            echo "    bloodhound-ce logs | grep -i 'Initial Password'"
            ;;
        down|stop)   $sudo $dc -f "$compose" down ;;
        logs)        $sudo $dc -f "$compose" logs -f ;;
        pull|update) $sudo $dc -f "$compose" pull ;;
        status|ps)   $sudo $dc -f "$compose" ps ;;
        *)           echo "Usage: bloodhound-ce [up|down|logs|pull|status]" ;;
    esac
}
BHCE
        ok "bloodhound-ce added. Reopen your terminal and run: ${C_BOLD}bloodhound-ce${C_RESET}"
    fi
    chown_user "$zshrc_file"

    # ----- bat: alias cat to bat (batcat on Debian/Kali) in the user shells --
    local rc rc_files=("$zshrc_file")
    [[ -f "$bashrc_file" ]] && rc_files+=("$bashrc_file")
    for rc in "${rc_files[@]}"; do
        if grep -q 'SecTools: bat alias' "$rc" 2>/dev/null; then
            skip_line "cat->bat ($(basename "$rc"))" "already added"
            continue
        fi
        {
            echo ""
            echo "# SecTools: bat alias - use bat as a nicer cat when available"
            echo 'if command -v batcat >/dev/null 2>&1; then alias cat="batcat"'
            echo 'elif command -v bat >/dev/null 2>&1; then alias cat="bat"; fi'
        } >> "$rc" 2>/dev/null && chown_user "$rc" && ok "cat -> bat alias added to ${C_BOLD}$(basename "$rc")${C_RESET}"
    done

    # ----- rockyou wordlist: unzip the Kali-shipped archive if present -------
    local rockyou_gz="/usr/share/wordlists/rockyou.txt.gz"
    local rockyou_txt="/usr/share/wordlists/rockyou.txt"
    if [[ -f "$rockyou_txt" ]]; then
        skip_line "rockyou.txt" "already extracted"
    elif [[ -f "$rockyou_gz" ]]; then
        # SC2024: the log redirect is applied by our shell, not the sudo'd
        # gunzip; that is intended - $LOGFILE lives in the launch dir, not a
        # root-only path - so the redirect works whether or not we are root.
        # shellcheck disable=SC2024
        (sudo gunzip -f "$rockyou_gz" >>"$LOGFILE" 2>&1) & spinner "rockyou.txt" "extracting" "extracted"
    else
        skip_line "rockyou.txt" "not found"
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
    printf '  %s%s%s\n' "$C_DIM" "Select one or more, e.g. 1 3 5 or 1,4" "$C_RESET"

    local choice
    read -r -p "$(printf '\n  %s%s%s  Enter choice(s) [0-5]: ' "$C_CYAN" "$GLYPH_INFO" "$C_RESET")" choice

    # Accept several selections at once (space- or comma-separated).
    local -a tokens picks=()
    read -ra tokens <<< "${choice//,/ }"

    local t
    for t in "${tokens[@]}"; do
        case "$t" in
            0) info "Exiting."; exit 0 ;;
            5) picks=(tools scripts obfuscated functions); break ;;
            1) picks+=(tools) ;;
            2) picks+=(scripts) ;;
            3) picks+=(obfuscated) ;;
            4) picks+=(functions) ;;
            *) warn "Ignoring invalid option: ${t}" ;;
        esac
    done

    if [[ ${#picks[@]} -eq 0 ]]; then
        warn "No valid option selected. Choose one or more numbers between 0 and 5."
        menu_choice
        return
    fi

    # De-duplicate while preserving the order given.
    local p seen=" " ordered=()
    for p in "${picks[@]}"; do
        [[ "$seen" == *" $p "* ]] && continue
        seen+="$p "
        ordered+=("$p")
    done

    for p in "${ordered[@]}"; do
        case "$p" in
            tools)      install_tools ;;
            scripts)    download_scripts ;;
            obfuscated) obfuscated_scripts ;;
            functions)  add_custom_functions ;;
        esac
    done
}

###############################################################################
# Usage / help
###############################################################################
disable_color() {
    USE_COLOR=0; SPIN_ANIMATE=0
    C_RESET=''; C_BOLD=''; C_DIM=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_CYAN=''; C_GREY=''
}

usage() {
    cat <<EOF

  ${C_BOLD}SecTools${C_RESET} ${C_DIM}v${SECTOOLS_VERSION}${C_RESET} - offensive tooling bootstrapper

  ${C_BOLD}USAGE${C_RESET}
    sudo ./sectools.sh [options]

    With no options an interactive menu is shown.

  ${C_BOLD}ACTIONS${C_RESET} (combine freely; they run in the order given)
    --tools           Install tools
    --scripts         Download scripts
    --obfuscated      Download obfuscated scripts
    --functions       Add custom shell functions to ~/.zshrc
    --all             All of the above

  ${C_BOLD}OPTIONS${C_RESET}
    --dir PATH        Download target (default /opt/tools); skips the prompt
    --only a,b,c      Tool phase: install only these tools
    --skip a,b,c      Tool phase: skip these tools
    --dry-run         Show what would happen; change nothing
    --list            List the tool inventory and exit
    --update          Run 'apt update' before the actions
    --upgrade         Run 'apt upgrade' before the actions
    -y, --yes         Non-interactive: assume defaults and run 'apt update'
    --no-color        Disable colours and the spinner animation
    -h, --help        Show this help and exit
    -V, --version     Show version and exit

  ${C_BOLD}EXAMPLES${C_RESET}
    sudo ./sectools.sh --all -y
    sudo ./sectools.sh --tools --only netexec,impacket,bloodhound
    sudo ./sectools.sh --tools --skip docker,docker-compose
    sudo ./sectools.sh --all --dry-run
    sudo ./sectools.sh --scripts --dir /opt/tools -y

EOF
}

# list_inventory - print the tool registry and exit (no network, no install)
list_inventory() {
    [[ ${#T_NAME[@]} -eq 0 ]] && define_tools
    printf '\n  %s%s%s %s%s%s\n' "$C_CYAN" "$GLYPH_ARROW" "$C_RESET" "$C_BOLD" "Tools (${#T_NAME[@]})" "$C_RESET"
    rule
    local i
    for i in "${!T_NAME[@]}"; do
        printf '    %s%s%s %s\n' "$C_CYAN" "$GLYPH_SKIP" "$C_RESET" "${T_NAME[i]}"
    done
    rule
    info "Filter with ${C_BOLD}--only${C_RESET} / ${C_BOLD}--skip${C_RESET}; preview with ${C_BOLD}--dry-run${C_RESET}."
    info "Scripts and obfuscated payloads are fetched by ${C_BOLD}--scripts${C_RESET} / ${C_BOLD}--obfuscated${C_RESET}."
    echo
}

###############################################################################
# Main
###############################################################################
main() {
    local actions=() do_list=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --tools)       actions+=(tools) ;;
            --scripts)     actions+=(scripts) ;;
            --obfuscated)  actions+=(obfuscated) ;;
            --functions)   actions+=(functions) ;;
            --all)         actions+=(tools scripts obfuscated functions) ;;
            --dir)         shift; PRESET_DIR="${1:-}"; [[ -z "$PRESET_DIR" ]] && { err "--dir requires a path"; exit 2; } ;;
            --dir=*)       PRESET_DIR="${1#*=}" ;;
            --only)        shift; ONLY_LIST="${1:-}"; [[ -z "$ONLY_LIST" ]] && { err "--only requires a comma-separated list"; exit 2; } ;;
            --only=*)      ONLY_LIST="${1#*=}" ;;
            --skip)        shift; SKIP_LIST="${1:-}"; [[ -z "$SKIP_LIST" ]] && { err "--skip requires a comma-separated list"; exit 2; } ;;
            --skip=*)      SKIP_LIST="${1#*=}" ;;
            --dry-run)     DRY_RUN=1 ;;
            --list)        do_list=1 ;;
            --update)      DO_UPDATE=1 ;;
            --upgrade)     DO_UPGRADE=1 ;;
            -y|--yes)      ASSUME_YES=1; DO_UPDATE=1 ;;
            --no-color)    disable_color ;;
            -h|--help)     usage; exit 0 ;;
            -V|--version)  echo "sectools ${SECTOOLS_VERSION}"; exit 0 ;;
            --)            shift; break ;;
            *)             err "Unknown option: $1"; usage; exit 2 ;;
        esac
        shift
    done

    if [[ "$do_list" -eq 1 ]]; then
        list_inventory
        exit 0
    fi

    print_banner

    # A dry run makes no changes, so it needs neither network nor privileges;
    # still verify connectivity for real runs.
    if [[ "$DRY_RUN" -ne 1 ]] && ! check_network; then
        err "No network connection. Exiting."
        exit 1
    fi

    [[ "$DRY_RUN" -eq 1 ]] || require_dependencies

    if [[ ${#actions[@]} -gt 0 ]]; then
        # Non-interactive run driven by flags.
        [[ "$DRY_RUN" -ne 1 && "$DO_UPDATE"  -eq 1 ]] && run_update
        [[ "$DRY_RUN" -ne 1 && "$DO_UPGRADE" -eq 1 ]] && run_upgrade
        local a
        for a in "${actions[@]}"; do
            case "$a" in
                tools)      install_tools ;;
                scripts)    download_scripts ;;
                obfuscated) obfuscated_scripts ;;
                functions)  add_custom_functions ;;
            esac
        done
    elif [[ ! -t 0 ]]; then
        err "No TTY for the interactive menu. Pass an action such as --all (see --help)."
        exit 2
    else
        ask_update
        ask_upgrade
        menu_choice
    fi

    printf '\n  %s%s Done.%s\n\n' "$C_GREEN" "$GLYPH_OK" "$C_RESET"
}

main "$@"
