#!/bin/bash

set -uo pipefail

#Colors
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
RED="\e[31m"
ORANGE="\e[93m"
VIOLET="\e[35m"
LIGHT_BLUE="\e[38;5;39m"
NC="\e[0m"

#Environment variables
startdir="$(pwd)"
user_home="$(eval echo "~${SUDO_USER:-$USER}")"
zshrc_file="${user_home}/.zshrc"
user_name="${SUDO_USER:-$(whoami)}"

# Cached API responses for performance
declare -A api_cache

# Cleanup function for proper exit
cleanup() {
    cd "${startdir}" 2>/dev/null
}
trap cleanup EXIT


echo ""
echo -e "${GREEN} Created by:"
echo -e " ${RED}   ___              _                     _     "
echo -e " ${YELLOW}  / _ \            | |                   | |    "
echo -e " ${ORANGE} | | | |__  __ ___ | |_  __ _  __ __ ___ | | __ "
echo -e " ${BLUE} | | | |\ \/ // __|| __|/ _\ |/ _\ || __|| |/ / "
echo -e " ${LIGHT_BLUE} | |_| | >  < \__ \| |_| (_| ||(_| || |  |   <  "
echo -e " ${VIOLET}  \___/ /_/\_\|___/ \__|\__,_|\__,_||_|  |_|\_\ "
echo ""
echo -e "${BLUE}https://github.com/0xstaark${NC}"
echo ""


###################################################################################################################
# Check network connection
###################################################################################################################

if ! ping -c 1 -W 5 8.8.8.8 &> /dev/null; then
    echo -e "${RED}[WAR]${NC}  No network connection. Exiting..."
    exit 1
fi

###################################################################################################################
# Ask user if they want to update
###################################################################################################################

ask_update() {
    read -p "Do you want to run 'sudo apt update'? (y/n): " choice
    case "$choice" in
        [Yy]* )
            echo -e "${YELLOW}[INFO]${NC} Running 'sudo apt update'..."
            sudo apt -q update >/dev/null 2>&1
            ;;
        [Nn]* )
            echo -e "${YELLOW}[INFO]${NC} Skipping update."
            ;;
        * )
            echo -e "${RED}[WAR]${NC}  Invalid input. Please enter 'y' or 'n'."
            ask_update
            ;;
    esac
}

###################################################################################################################
# Set variables as global
###################################################################################################################

# Function to set the variable
get_script_dir() {
    # Default directory
    toolsdir="/opt/tools"

    # Prompt the user for a custom directory
    echo -e "${YELLOW}[INFO]${NC} Choose directory to download Script to. Example: /opt/tools"
    read -p "$(echo -e "${YELLOW}[INFO]${NC} Enter the directory to use, hit ENTER for default: ${YELLOW}[${toolsdir}]${NC}: ")" userdir

    # If user provides input, use it as the tools directory
    if [[ -n "$userdir" ]]; then
        toolsdir="$userdir"
    fi

    # Check if directory exists
    if [[ -d "$toolsdir" ]]; then
        echo -e "${YELLOW}[INFO]${NC} Using directory: [${BLUE}${toolsdir}${NC}]"
    else
        if ! mkdir -p "$toolsdir" 2>/dev/null; then
            echo ""
            echo -e "${RED}[WAR]${NC} You don't have access to create folders in [${BLUE}${toolsdir}${NC}]. Rerun the script with sudo."
            exit 1
        else
            echo -e "${YELLOW}[INFO]${NC} Created directory: [${BLUE}${toolsdir}${NC}]"
        fi
    fi
}

# Function to get cached API response or fetch new one
get_api_response() {
    local api_url="$1"
    if [[ -z "${api_cache[$api_url]:-}" ]]; then
        api_cache[$api_url]=$(curl -s "$api_url")
    fi
    echo "${api_cache[$api_url]}"
}

###################################################################################################################
# function to check for latest release of a file and download the file from GitHub if needed a newer version is avilable
###################################################################################################################
check_and_download_file() {
    local api_url="$1"
    local file_url="$2"
    local local_file="$3"
    local local_file2="${4:-$local_file}"
    local existing_file=""

    # Get the time from the GitHub API (use cached response)
    local api_response
    api_response=$(get_api_response "$api_url")
    local github_time
    github_time=$(echo "$api_response" | grep 'updated_at' | head -1 | sed 's/ //g' | awk -F '"' '{print $4}' | sed 's/T.*//')

    # Check if the file exists locally (check both possible names)
    if [[ -f "$local_file" ]]; then
        existing_file="$local_file"
    elif [[ -f "$local_file2" ]]; then
        existing_file="$local_file2"
    fi

    if [[ -n "$existing_file" ]]; then
        # Get the time from the local file
        local local_time
        local_time=$(stat -c "%y" "$existing_file" 2>/dev/null | awk '{print $1}')

        # Convert the times to timestamps (with error handling)
        local github_timestamp local_timestamp
        github_timestamp=$(date -d "$github_time" +%s 2>/dev/null || echo 0)
        local_timestamp=$(date -d "$local_time" +%s 2>/dev/null || echo 0)

        # Compare the timestamps to identify the newest file
        if [[ "$github_timestamp" -gt "$local_timestamp" ]]; then
            # Download the file
            rm -f "$existing_file" 2>/dev/null
            if wget -q "$file_url" -O "$local_file" 2>/dev/null; then
                printf "${YELLOW}[INFO]${NC} %-15s %s\n" "Updated:" "$local_file"
            else
                printf "${RED}[WAR]${NC}  %-15s %s\n" "Failed to download:" "$local_file"
            fi
        else
            echo -e "${GREEN}[OK]${NC}   You already have the newest version of: ${YELLOW}$local_file${NC}"
        fi
    else
        # If the file doesn't exist, download it
        if wget -q "$file_url" 2>/dev/null; then
            if [[ -f "$local_file" || -f "$local_file2" ]]; then
                printf "${YELLOW}[INFO]${NC} %-15s %s\n" "Downloading:" "$local_file"
            else
                printf "${RED}[WAR]${NC}  %-15s %s\n" "Failed to download:" "$local_file"
            fi
        else
            printf "${RED}[WAR]${NC}  %-15s %s\n" "Failed to download:" "$local_file"
        fi
    fi
}


###################################################################################################################
# function to check for latest version of a single file, and download if it's a newer version.
# Uses HTTP Last-Modified header for comparison since raw GitHub URLs don't provide API data
###################################################################################################################
single_file_check_and_download_file() {
    local download_url="$1"
    local local_file="$2"

    # Check if file exists
    if [[ -f "$local_file" ]]; then
        # Get the Last-Modified time from the remote file via HTTP headers
        local remote_time
        remote_time=$(curl -sI "$download_url" 2>/dev/null | grep -i "last-modified" | sed 's/last-modified: //i' | tr -d '\r')

        if [[ -n "$remote_time" ]]; then
            # Get the time from the local file
            local local_time
            local_time=$(stat -c "%y" "$local_file" 2>/dev/null | awk '{print $1}')

            # Convert the times to timestamps
            local remote_timestamp local_timestamp
            remote_timestamp=$(date -d "$remote_time" +%s 2>/dev/null || echo 0)
            local_timestamp=$(date -d "$local_time" +%s 2>/dev/null || echo 0)

            # Compare the timestamps to identify the newest file
            if [[ "$remote_timestamp" -gt "$local_timestamp" ]]; then
                # Download file
                rm -f "$local_file" 2>/dev/null
                if wget -q "$download_url" -O "$local_file" 2>/dev/null && [[ -s "$local_file" ]]; then
                    printf "${YELLOW}[INFO]${NC} %-15s %s\n" "Updated:" "$local_file"
                else
                    printf "${RED}[WAR]${NC}  %-15s %s\n" "Failed to download:" "$local_file"
                fi
            else
                echo -e "${GREEN}[OK]${NC}   You already have the newest version of: ${YELLOW}$local_file${NC}"
            fi
        else
            # Can't get remote time, skip update check
            echo -e "${GREEN}[OK]${NC}   File exists: ${YELLOW}$local_file${NC}"
        fi
    else
        # If the file doesn't exist, download it
        if wget -q "$download_url" -O "$local_file" 2>/dev/null && [[ -s "$local_file" ]]; then
            printf "${YELLOW}[INFO]${NC} %-15s %s\n" "Downloading:" "$local_file"
        else
            rm -f "$local_file" 2>/dev/null  # Remove empty/failed download
            printf "${RED}[WAR]${NC}  %-15s %s\n" "Failed to download:" "$local_file"
        fi
    fi
}


###################################################################################################################
# INSTALLING TOOLS
###################################################################################################################
# Function for Installing tools, and then calling the function via the menu
install_tools() {

    # Check if user is NOT root
    if [[ $UID -ne 0 ]]; then
        echo -e "${YELLOW}[WAR]${NC} To install the tools you need to run with SUDO"
        # Ensure the user can sudo or exit
        sudo -v || exit 1
    fi

    echo -e "${GREEN}-----------------------------------------------------"
    echo -e "${GREEN}[INFO] Installing tools"
    echo -e "${GREEN}-----------------------------------------------------${NC}"

    # Installing seclists
    if [[ -d "/usr/share/seclists" ]]; then
        printf "${GREEN}[OK]${NC}   %-15s %s\n" "seclists" "Already installed"
    else
        printf "${YELLOW}[INFO]${NC} %-15s %s\n" "Installing" "seclists (this may take a while)"
        sudo apt-get -qq -y install seclists >/dev/null 2>&1
    fi

    # Installing batcat
    if command -v batcat &>/dev/null; then
        printf "${GREEN}[OK]${NC}   %-15s %s\n" "Batcat" "Already installed"
    else
        printf "${YELLOW}[INFO]${NC} %-15s %s\n" "Installing" "batcat"
        sudo apt-get -qq -y install bat >/dev/null 2>&1
    fi

    # Installing Rustscan
    if command -v rustscan &>/dev/null; then
        printf "${GREEN}[OK]${NC}   %-15s %s\n" "Rustscan" "Already installed"
    else
        printf "${YELLOW}[INFO]${NC} %-15s %s\n" "Installing" "Rustscan"
        local versionnr
        versionnr=$(curl -s https://api.github.com/repos/RustScan/RustScan/releases/latest | grep -oP '"tag_name":\s*"\K[^"]+' | head -1)
        if [[ -n "$versionnr" ]]; then
            wget -q -O /tmp/rustscan.deb "https://github.com/RustScan/RustScan/releases/download/${versionnr}/rustscan_${versionnr}_amd64.deb" 2>/dev/null
            sudo dpkg -i /tmp/rustscan.deb >/dev/null 2>&1
            rm -f /tmp/rustscan.deb 2>/dev/null
        else
            printf "${RED}[WAR]${NC}  Failed to get Rustscan version\n"
        fi
    fi

    # Installing wfuzz
    if command -v wfuzz &>/dev/null; then
        printf "${GREEN}[OK]${NC}   %-15s %s\n" "wfuzz" "Already installed"
    else
        printf "${YELLOW}[INFO]${NC} %-15s %s\n" "Installing" "wfuzz"
        sudo apt-get -qq -y install wfuzz >/dev/null 2>&1
    fi

    # Installing ffuf
    if command -v ffuf &>/dev/null; then
        printf "${GREEN}[OK]${NC}   %-15s %s\n" "ffuf" "Already installed"
    else
        printf "${YELLOW}[INFO]${NC} %-15s %s\n" "Installing" "ffuf"
        sudo apt-get -qq -y install ffuf >/dev/null 2>&1
    fi

    # Installing Bloodhound
    if command -v bloodhound &>/dev/null; then
        printf "${GREEN}[OK]${NC}   %-15s %s\n" "Bloodhound" "Already installed"
    else
        printf "${YELLOW}[INFO]${NC} %-15s %s\n" "Installing" "bloodhound"
        sudo apt-get -qq -y install bloodhound >/dev/null 2>&1
    fi

    # Installing Neo4j
    if command -v neo4j &>/dev/null; then
        printf "${GREEN}[OK]${NC}   %-15s %s\n" "Neo4j" "Already installed"
    else
        printf "${YELLOW}[INFO]${NC} %-15s %s\n" "Installing" "Neo4j"
        sudo apt-get -qq -y install neo4j >/dev/null 2>&1
    fi

    # Installing GoBuster
    if command -v gobuster &>/dev/null; then
        printf "${GREEN}[OK]${NC}   %-15s %s\n" "GoBuster" "Already installed"
    else
        printf "${YELLOW}[INFO]${NC} %-15s %s\n" "Installing" "GoBuster"
        sudo apt-get -qq -y install gobuster >/dev/null 2>&1
    fi

    # Installing feroxbuster
    if command -v feroxbuster &>/dev/null; then
        printf "${GREEN}[OK]${NC}   %-15s %s\n" "Feroxbuster" "Already installed"
    else
        printf "${YELLOW}[INFO]${NC} %-15s %s\n" "Installing" "Feroxbuster"
        sudo apt-get -qq -y install feroxbuster >/dev/null 2>&1
    fi

    # Installing Coercer
    if command -v coercer &>/dev/null; then
        printf "${GREEN}[OK]${NC}   %-15s %s\n" "Coercer" "Already installed"
    else
        printf "${YELLOW}[INFO]${NC} %-15s %s\n" "Installing" "Coercer"
        sudo pip3 install -q coercer 2>/dev/null
    fi

    # Installing Certipy-ad
    if command -v certipy-ad &>/dev/null || command -v certipy &>/dev/null; then
        printf "${GREEN}[OK]${NC}   %-15s %s\n" "Certipy-ad" "Already installed"
    else
        printf "${YELLOW}[INFO]${NC} %-15s %s\n" "Installing" "Certipy-ad"
        sudo pip3 install -q certipy-ad 2>/dev/null
    fi

    # Installing pypykatz
    if command -v pypykatz &>/dev/null; then
        printf "${GREEN}[OK]${NC}   %-15s %s\n" "pypykatz" "Already installed"
    else
        printf "${YELLOW}[INFO]${NC} %-15s %s\n" "Installing" "pypykatz"
        sudo pip3 install -q pypykatz 2>/dev/null
    fi

    echo ""
    echo -e "${BLUE}[COMPLETE]${NC}"
}


###################################################################################################################
# DOWNLOADING SCRIPTS
###################################################################################################################

# Function for downloading scripts, and then calling the function via the menu
download_scripts() {

    # Change to the tools directory
    cd "$toolsdir" || { echo -e "${RED}[WAR]${NC} Cannot access directory: $toolsdir"; return 1; }
    echo -e "${GREEN}-----------------------------------------------------"
    echo -e "${GREEN}[INFO] Downloading Scripts into ${BLUE}[${toolsdir}]"
    echo -e "${GREEN}-----------------------------------------------------${NC}"
    sleep 1


#####################################################################################################################
#Latest releases
#####################################################################################################################

#Downloading mimikatz
# GitHub API URL for the latest release
api_url="https://api.github.com/repos/gentilkiwi/mimikatz/releases/latest"
file=$(curl -s $api_url | grep -i 'browser_download_url' | tail -1 | awk '{print $2}' | sed 's/"//g')
#latest_release=$(echo $latest | awk -F '/' '{print $1}')
#zip_file_name=$(echo $latest | awk -F '/' '{print $2}' )
#file="https://github.com/gentilkiwi/mimikatz/releases/download/$latest_release/$zip_file_name"
local_file="mimikatz.exe"
local_file2="mimikatz_trunk.zip"
check_and_download_file "$api_url" "$file" "$local_file" "$local_file2"


#Downloading SharpHound.exe
# GitHub API URL for the latest release
api_url="https://api.github.com/repos/BloodHoundAD/SharpHound/releases/latest"
file=$(curl -s $api_url | grep -i 'browser_download_url' | tail -1 | awk '{print $2}' | sed 's/"//g')
#lastest_release=$(echo $latest) | awk -F '/' '{print $1}'
#zip_file_name=$(echo $latest) | awk -F '/' '{print $2}' | sed 's/"$//'
#file="https://github.com/BloodHoundAD/SharpHound/releases/download/$lastest_release/$zip_file_name"
local_file="SharpHound.exe"
local_file2="$(echo $file | awk -F '/' '{print $9}')"
check_and_download_file "$api_url" "$file" "$local_file" "$local_file2"


#Downloading winPEASx64.exe
# GitHub API URL for the latest release
api_url="https://api.github.com/repos/peass-ng/PEASS-ng/releases"
latest=$(curl -s $api_url | grep -i 'browser_download_url' | head -1 | awk '{print $2}' | awk -F "/" '{print $8}')
file="https://github.com/peass-ng/PEASS-ng/releases/download/$latest/winPEASx64.exe"
local_file="winPEASx64.exe"
check_and_download_file "$api_url" "$file" "$local_file"


#Downloading winPEASany.exe
# GitHub API URL for the latest release
api_url="https://api.github.com/repos/peass-ng/PEASS-ng/releases"
latest=$(curl -s $api_url | grep -i 'browser_download_url' | head -1 | awk '{print $2}' | awk -F "/" '{print $8}')
file="https://github.com/peass-ng/PEASS-ng/releases/download/$latest/winPEASany.exe"
local_file="winPEASany.exe"
check_and_download_file "$api_url" "$file" "$local_file"


#Downloading Linpeas.sh
# GitHub API URL for the latest release
api_url="https://api.github.com/repos/peass-ng/PEASS-ng/releases"
latest=$(curl -s $api_url | grep -i 'browser_download_url' | head -1 | awk '{print $2}' | awk -F "/" '{print $8}')
file="https://github.com/peass-ng/PEASS-ng/releases/download/$latest/linpeas.sh"
local_file="linpeas.sh"
check_and_download_file "$api_url" "$file" "$local_file"


#Downloadning pspy32
# GitHub API URL for the latest release
api_url="https://api.github.com/repos/DominicBreuker/pspy/releases/latest"
latest=$(curl -s $api_url | grep -i 'browser_download_url' | tail -1 | awk '{print $2}' | awk -F "/" '{print $8}')
file="https://github.com/DominicBreuker/pspy/releases/download/$latest/pspy32"
local_file="pspy32"
check_and_download_file "$api_url" "$file" "$local_file"


#Downloading pspy64
# GitHub API URL for the latest release
api_url="https://api.github.com/repos/DominicBreuker/pspy/releases/latest"
latest=$(curl -s $api_url | grep -i 'browser_download_url' | tail -1 | awk '{print $2}' | awk -F "/" '{print $8}')
file="https://github.com/DominicBreuker/pspy/releases/download/$latest/pspy64"
local_file="pspy64"
check_and_download_file "$api_url" "$file" "$local_file"


#Downloading Kerbrute
# GitHub API URL for the latest release
api_url="https://api.github.com/repos/ropnop/kerbrute/releases/latest"
latest=$(curl -s $api_url | grep -i 'browser_download_url' | tail -1 | awk '{print $2}' | awk -F "/" '{print $8}')
file="https://github.com/ropnop/kerbrute/releases/download/$latest/kerbrute_linux_amd64"
local_file="kerbrute_linux_amd64"
check_and_download_file "$api_url" "$file" "$local_file"


#Downloading Kerbrute
# GitHub API URL for the latest release
api_url="https://api.github.com/repos/ropnop/kerbrute/releases/latest"
latest=$(curl -s $api_url | grep -i 'browser_download_url' | tail -1 | awk '{print $2}' | awk -F "/" '{print $8}')
file="https://github.com/ropnop/kerbrute/releases/download/$latest/kerbrute_windows_amd64.exe"
local_file="kerbrute_windows_amd64.exe"
check_and_download_file "$api_url" "$file" "$local_file"


#####################################################################################################################
#Single files
#####################################################################################################################


#Downloading powercat.ps1
download_url="https://github.com/besimorhino/powercat/raw/master/powercat.ps1"
local_file="powercat.ps1"
single_file_check_and_download_file "$download_url" "$local_file"


#Downloading Invoke-Mimikatz.ps1
download_url="https://github.com/clymb3r/PowerShell/raw/master/Invoke-Mimikatz/Invoke-Mimikatz.ps1"
local_file="Invoke-Mimikatz.ps1"
single_file_check_and_download_file "$download_url" "$local_file"


#Downloading Powerview.ps1
download_url="https://github.com/PowerShellMafia/PowerSploit/raw/master/Recon/PowerView.ps1"
local_file="PowerView.ps1"
single_file_check_and_download_file "$download_url" "$local_file"
    

#Downloading PowerUp.ps1
download_url="https://github.com/PowerShellMafia/PowerSploit/raw/master/Privesc/PowerUp.ps1"
local_file="PowerUp.ps1"
single_file_check_and_download_file "$download_url" "$local_file"


#Downloading Rubeus.exe
download_url="https://github.com/Flangvik/SharpCollection/raw/master/NetFramework_4.7_Any/Rubeus.exe"
local_file="Rubeus.exe"
single_file_check_and_download_file "$download_url" "$local_file"


#Downloading Invegih.ps1
download_url="https://github.com/Kevin-Robertson/Inveigh/raw/master/Inveigh.ps1"
local_file="Inveigh.ps1"
single_file_check_and_download_file "$download_url" "$local_file"


#Downloading nc64.exe
download_url="https://github.com/int0x33/nc.exe/raw/master/nc64.exe"
local_file="nc64.exe"
single_file_check_and_download_file "$download_url" "$local_file"


#Downloading nc.exe
download_url="https://github.com/int0x33/nc.exe/raw/master/nc.exe"
local_file="nc.exe"
single_file_check_and_download_file "$download_url" "$local_file"


#Downloading PlumHound.py
download_url="https://github.com/PlumHound/PlumHound/raw/master/PlumHound.py"
local_file="PlumHound.py"
single_file_check_and_download_file "$download_url" "$local_file"


#Downloading Linux Exploit Suggester
download_url="https://github.com/The-Z-Labs/linux-exploit-suggester/raw/master/linux-exploit-suggester.sh"
local_file="linux-exploit-suggester.sh"
single_file_check_and_download_file "$download_url" "$local_file"


#Downloading Linux PrivChecker
download_url="https://github.com/sleventyeleven/linuxprivchecker/raw/master/linuxprivchecker.py"
local_file="linuxprivchecker.py"
single_file_check_and_download_file "$download_url" "$local_file"


#Downloading LinEmnum.sh
download_url="https://github.com/rebootuser/LinEnum/raw/master/LinEnum.sh"
local_file="LinEnum.sh"
single_file_check_and_download_file "$download_url" "$local_file"


#Downloading Whisker.exe
download_url="https://github.com/Flangvik/SharpCollection/raw/master/NetFramework_4.7_Any/Whisker.exe"
local_file="Whisker.exe"
single_file_check_and_download_file "$download_url" "$local_file"


#Downloading SharpMapExec.exe
download_url="https://github.com/Flangvik/SharpCollection/raw/master/NetFramework_4.7_Any/SharpMapExec.exe"
local_file="SharpMapExec.exe"
single_file_check_and_download_file "$download_url" "$local_file"


#Downloading SharpChisel.exe
download_url="https://github.com/Flangvik/SharpCollection/raw/master/NetFramework_4.7_Any/SharpChisel.exe"
local_file="SharpChisel.exe"
single_file_check_and_download_file "$download_url" "$local_file"


#Downloading Seatbelt.exe
download_url="https://github.com/Flangvik/SharpCollection/raw/master/NetFramework_4.7_Any/Seatbelt.exe"
local_file="Seatbelt.exe"
single_file_check_and_download_file "$download_url" "$local_file"


#Downloading ADCSPwn.exe
download_url="https://github.com/Flangvik/SharpCollection/raw/master/NetFramework_4.7_Any/ADCSPwn.exe"
local_file="ADCSPwn.exe"
single_file_check_and_download_file "$download_url" "$local_file"


#Downloading BetterSafetyKatz.exe
download_url="https://github.com/Flangvik/SharpCollection/raw/master/NetFramework_4.7_Any/BetterSafetyKatz.exe"
local_file="BetterSafetyKatz.exe"
single_file_check_and_download_file "$download_url" "$local_file"


#Downloading PassTheCert.exe
download_url="https://github.com/Flangvik/SharpCollection/raw/master/NetFramework_4.7_Any/PassTheCert.exe"
local_file="PassTheCert.exe"
single_file_check_and_download_file "$download_url" "$local_file"


#Downloading SharPersist.exe
download_url="https://github.com/Flangvik/SharpCollection/raw/master/NetFramework_4.7_x64/SharPersist.exe"
local_file="SharPersist.exe"
single_file_check_and_download_file "$download_url" "$local_file"


#Downloading MailSniper.ps1
download_url="https://github.com/dafthack/MailSniper/raw/master/MailSniper.ps1"
local_file="MailSniper.ps1"
single_file_check_and_download_file "$download_url" "$local_file"


#Downloading ADSearch.exe
download_url="https://github.com/Flangvik/SharpCollection/raw/master/NetFramework_4.7_x64/ADSearch.exe"
local_file="ADSearch.exe"
single_file_check_and_download_file "$download_url" "$local_file"


#Downloading Invoke-DCOM.ps1
download_url="https://github.com/EmpireProject/Empire/raw/master/data/module_source/lateral_movement/Invoke-DCOM.ps1"
local_file="Invoke-DCOM.ps1"
single_file_check_and_download_file "$download_url" "$local_file"


#Downloading PowerUpSQL.ps1
download_url="https://github.com/NetSPI/PowerUpSQL/raw/master/PowerUpSQL.ps1"
local_file="PowerUpSQL.ps1"
single_file_check_and_download_file "$download_url" "$local_file"


#Downloading SharpSCCM.exe
download_url="https://github.com/Flangvik/SharpCollection/raw/master/NetFramework_4.7_x64/SharpSCCM.exe"
local_file="SharpSCCM.exe"
single_file_check_and_download_file "$download_url" "$local_file"


#Downloading LAPSToolkit.ps1
download_url="https://github.com/leoloobeek/LAPSToolkit/raw/master/LAPSToolkit.ps1"
local_file="LAPSToolkit.ps1"
single_file_check_and_download_file "$download_url" "$local_file"

#Downloading Certify.exe
download_url="https://github.com/Flangvik/SharpCollection/raw/master/NetFramework_4.5_Any/Certify.exe"
local_file="Certify.exe"
single_file_check_and_download_file "$download_url" "$local_file"


#Downloading Inveigh.exe
download_url="https://github.com/Flangvik/SharpCollection/raw/master/NetFramework_4.5_Any/Inveigh.exe"
local_file="Inveigh.exe"
single_file_check_and_download_file "$download_url" "$local_file"


#Downloading RunasCs.exe (from zip release)
if [[ ! -f "RunasCs.exe" ]]; then
    printf "${YELLOW}[INFO]${NC} %-15s %s\n" "Downloading:" "RunasCs.exe"
    local runascs_version
    runascs_version=$(curl -s https://api.github.com/repos/antonioCoco/RunasCs/releases/latest | grep -oP '"tag_name":\s*"\K[^"]+' | head -1)
    if [[ -n "$runascs_version" ]]; then
        wget -q "https://github.com/antonioCoco/RunasCs/releases/download/${runascs_version}/RunasCs.zip" -O RunasCs.zip 2>/dev/null
        if [[ -f "RunasCs.zip" ]]; then
            unzip -o RunasCs.zip >/dev/null 2>&1
            rm -f RunasCs.zip 2>/dev/null
        fi
    fi
else
    echo -e "${GREEN}[OK]${NC}   File exists: ${YELLOW}RunasCs.exe${NC}"
fi


#Downloading Invoke-RunasCs.ps1
download_url="https://github.com/antonioCoco/RunasCs/raw/master/Invoke-RunasCs.ps1"
local_file="Invoke-RunasCs.ps1"
single_file_check_and_download_file "$download_url" "$local_file"


#####################################################################################################################
# Zip files and git repositories
#####################################################################################################################

    # Downloading Microsoft Sysinternals PSTools
    local_file="PSTools"
    if [[ ! -d "$local_file" ]]; then
        printf "${YELLOW}[INFO]${NC} %-15s %s\n" "Downloading:" "$local_file"
        if wget -q "https://download.sysinternals.com/files/PSTools.zip" -O PSTools.zip 2>/dev/null; then
            unzip -q PSTools.zip -d PSTools 2>/dev/null
            rm -f PSTools.zip 2>/dev/null
        else
            echo -e "${RED}[WAR]${NC} Failed to download ${YELLOW}$local_file${NC}"
        fi
    else
        echo -e "${GREEN}[OK]${NC}   Directory exists: ${YELLOW}$local_file${NC}"
    fi


    # Downloading AutoRecon and installing requirements
    local_file="AutoRecon"
    if [[ ! -d "$local_file" ]]; then
        printf "${YELLOW}[INFO]${NC} %-15s %s\n" "Downloading:" "$local_file"
        if git clone --quiet "https://github.com/Tib3rius/AutoRecon.git" 2>/dev/null; then
            pip3 install -q -r AutoRecon/requirements.txt 2>/dev/null
        else
            echo -e "${RED}[WAR]${NC} Failed to clone ${YELLOW}$local_file${NC}"
        fi
    else
        echo -e "${GREEN}[OK]${NC}   Directory exists: ${YELLOW}$local_file${NC}"
    fi


    # Downloading PassTheCert
    local_file="passthecert.py"
    if [[ ! -f "$local_file" ]]; then
        printf "${YELLOW}[INFO]${NC} %-15s %s\n" "Downloading:" "$local_file"
        if git clone --quiet "https://github.com/AlmondOffSec/PassTheCert.git" 2>/dev/null; then
            cp PassTheCert/Python/passthecert.py . 2>/dev/null
        else
            echo -e "${RED}[WAR]${NC} Failed to clone ${YELLOW}PassTheCert${NC}"
        fi
    else
        echo -e "${GREEN}[OK]${NC}   File exists: ${YELLOW}$local_file${NC}"
    fi


    # Downloading PetitPotam
    local_file="PetitPotam.py"
    if [[ ! -f "$local_file" ]]; then
        printf "${YELLOW}[INFO]${NC} %-15s %s\n" "Downloading:" "$local_file"
        if git clone --quiet "https://github.com/topotam/PetitPotam.git" 2>/dev/null; then
            cp PetitPotam/PetitPotam.py . 2>/dev/null
        else
            echo -e "${RED}[WAR]${NC} Failed to clone ${YELLOW}PetitPotam${NC}"
        fi
    else
        echo -e "${GREEN}[OK]${NC}   File exists: ${YELLOW}$local_file${NC}"
    fi


    # Downloading SprayingToolkit
    local_file="SprayingToolkit"
    if [[ ! -d "$local_file" ]]; then
        printf "${YELLOW}[INFO]${NC} %-15s %s\n" "Downloading:" "$local_file"
        if ! git clone --quiet "https://github.com/byt3bl33d3r/SprayingToolkit.git" 2>/dev/null; then
            echo -e "${RED}[WAR]${NC} Failed to clone ${YELLOW}$local_file${NC}"
        fi
    else
        echo -e "${GREEN}[OK]${NC}   Directory exists: ${YELLOW}$local_file${NC}"
    fi


#####################################################################################################################
# Cleanup and house keeping
#####################################################################################################################
    echo -e "${BLUE}[INFO]${NC} Performing cleanup..."

    # Extract mimikatz if needed
    if [[ ! -f "mimikatz.exe" ]] && ls mimikatz*.zip 1>/dev/null 2>&1; then
        unzip -o mimikatz*.zip -d mimikatz_temp >/dev/null 2>&1
        cp mimikatz_temp/x64/mimikatz.exe . 2>/dev/null
        rm -rf mimikatz_temp mimikatz*.zip 2>/dev/null
    fi

    # Extract SharpHound if needed
    if [[ ! -f "SharpHound.exe" ]] && ls SharpHound*.zip 1>/dev/null 2>&1; then
        unzip -o SharpHound*.zip >/dev/null 2>&1
        rm -f SharpHound*.zip 2>/dev/null
    fi

    # Clean up temporary files
    rm -f *.zip *.config *.dll *.pdb *.txt *.chm *.idl *.yar 2>/dev/null
    rm -rf x64 Win32 2>/dev/null
    rm -rf PassTheCert PetitPotam 2>/dev/null

    # Copy kerbrute to /usr/local/bin if it exists
    if [[ -f "kerbrute_linux_amd64" ]]; then
        sudo cp kerbrute_linux_amd64 /usr/local/bin/kerbrute_linux 2>/dev/null
        sudo chmod +x /usr/local/bin/kerbrute_linux 2>/dev/null
    fi

    # Change owner of the toolsdir
    if [[ "$(stat -c '%U' "${toolsdir}")" != "${user_name}" ]]; then
        chown -R "${user_name}:${user_name}" "${toolsdir}" 2>/dev/null
    fi

    # Move back to the directory where the script was run from
    cd "${startdir}" || true
    echo -e "${BLUE}[COMPLETE]${NC}"
    echo ""
}


#####################################################################################################################
# Download obfuscated versions
#####################################################################################################################

download_obfuscated_scripts() {

    obftoolsdir="${toolsdir}/obfuscated"
    # Prompt the user for a custom directory
    echo -e "${YELLOW}[INFO]${NC} Choose directory to download Script to. Example: ${BLUE}[${obftoolsdir}]${NC}"
    read -p "$(echo -e "${YELLOW}[INFO]${NC} Enter the directory to use, hit ENTER for default: ${YELLOW}[${obftoolsdir}]${NC}: ")" userdir

    # If user provides input, use it as the tools directory
    if [[ -n "$userdir" ]]; then
        obftoolsdir="$userdir"
    fi

    # Check if directory exists
    if [[ -d "$obftoolsdir" ]]; then
        echo -e "${YELLOW}[INFO]${NC} Using directory: [${BLUE}${obftoolsdir}${NC}]"
    else
        if ! mkdir -p "$obftoolsdir" 2>/dev/null; then
            echo ""
            echo -e "${RED}[WAR]${NC} You don't have access to create folders in [${BLUE}${obftoolsdir}${NC}]. Rerun the script with sudo."
            exit 1
        else
            echo -e "${YELLOW}[INFO]${NC} Created directory: [${BLUE}${obftoolsdir}${NC}]"
        fi
    fi

    cd "${obftoolsdir}" || { echo -e "${RED}[WAR]${NC} Cannot access directory: $obftoolsdir"; return 1; }
    echo ""
    echo -e "${YELLOW}[INFO]${NC} Downloading Obfuscated scripts from [https://github.com/Flangvik/ObfuscatedSharpCollection]"
    echo ""

    # Downloading Certify.exe._obf.exe
    download_url="https://github.com/Flangvik/ObfuscatedSharpCollection/raw/main/NetFramework_4.7_Any/Certify.exe._obf.exe"
    local_file="Certify.exe._obf.exe"
    single_file_check_and_download_file "$download_url" "$local_file"


    # Downloading Rubeus.exe._obf.exe
    download_url="https://github.com/Flangvik/ObfuscatedSharpCollection/raw/main/NetFramework_4.7_Any/Rubeus.exe._obf.exe"
    local_file="Rubeus.exe._obf.exe"
    single_file_check_and_download_file "$download_url" "$local_file"


    # Downloading Seatbelt.exe._obf.exe
    download_url="https://github.com/Flangvik/ObfuscatedSharpCollection/raw/main/NetFramework_4.7_Any/Seatbelt.exe._obf.exe"
    local_file="Seatbelt.exe._obf.exe"
    single_file_check_and_download_file "$download_url" "$local_file"


    # Downloading SharpEDRChecker.exe._obf.exe
    download_url="https://github.com/Flangvik/ObfuscatedSharpCollection/raw/main/NetFramework_4.7_Any/SharpEDRChecker.exe._obf.exe"
    local_file="SharpEDRChecker.exe._obf.exe"
    single_file_check_and_download_file "$download_url" "$local_file"


    # Downloading SharpHound.exe._obf.exe
    download_url="https://github.com/Flangvik/ObfuscatedSharpCollection/raw/main/NetFramework_4.7_Any/SharpHound.exe._obf.exe"
    local_file="SharpHound.exe._obf.exe"
    single_file_check_and_download_file "$download_url" "$local_file"


    # Downloading SharpSCCM.exe._obf.exe
    download_url="https://github.com/Flangvik/ObfuscatedSharpCollection/raw/main/NetFramework_4.7_Any/SharpSCCM.exe._obf.exe"
    local_file="SharpSCCM.exe._obf.exe"
    single_file_check_and_download_file "$download_url" "$local_file"


    # Downloading SharpView.exe._obf.exe
    download_url="https://github.com/Flangvik/ObfuscatedSharpCollection/raw/main/NetFramework_4.7_Any/SharpView.exe._obf.exe"
    local_file="SharpView.exe._obf.exe"
    single_file_check_and_download_file "$download_url" "$local_file"


    # Downloading Snaffler.exe._obf.exe
    download_url="https://github.com/Flangvik/ObfuscatedSharpCollection/raw/main/NetFramework_4.7_Any/Snaffler.exe._obf.exe"
    local_file="Snaffler.exe._obf.exe"
    single_file_check_and_download_file "$download_url" "$local_file"


    # Downloading StickyNotesExtract.exe._obf.exe
    download_url="https://github.com/Flangvik/ObfuscatedSharpCollection/raw/main/NetFramework_4.7_Any/StickyNotesExtract.exe._obf.exe"
    local_file="StickyNotesExtract.exe._obf.exe"
    single_file_check_and_download_file "$download_url" "$local_file"


    # Downloading Whisker.exe._obf.exe
    download_url="https://github.com/Flangvik/ObfuscatedSharpCollection/raw/main/NetFramework_4.7_Any/Whisker.exe._obf.exe"
    local_file="Whisker.exe._obf.exe"
    single_file_check_and_download_file "$download_url" "$local_file"


    # Downloading winPEAS.exe._obf.exe
    download_url="https://github.com/Flangvik/ObfuscatedSharpCollection/raw/main/NetFramework_4.7_Any/winPEAS.exe._obf.exe"
    local_file="winPEAS.exe._obf.exe"
    single_file_check_and_download_file "$download_url" "$local_file"


    # Downloading SharpWebServer.exe._obf.exe
    download_url="https://github.com/Flangvik/ObfuscatedSharpCollection/raw/main/NetFramework_4.7_Any/SharpWebServer.exe._obf.exe"
    local_file="SharpWebServer.exe._obf.exe"
    single_file_check_and_download_file "$download_url" "$local_file"


    # Downloading SharpNoPSExec.exe._obf.exe
    download_url="https://github.com/Flangvik/ObfuscatedSharpCollection/raw/main/NetFramework_4.7_Any/SharpNoPSExec.exe._obf.exe"
    local_file="SharpNoPSExec.exe._obf.exe"
    single_file_check_and_download_file "$download_url" "$local_file"


    # Downloading SharpMapExec.exe._obf.exe
    download_url="https://github.com/Flangvik/ObfuscatedSharpCollection/raw/main/NetFramework_4.7_Any/SharpMapExec.exe._obf.exe"
    local_file="SharpMapExec.exe._obf.exe"
    single_file_check_and_download_file "$download_url" "$local_file"


    # Downloading SharpKatz.exe._obf.exe
    download_url="https://github.com/Flangvik/ObfuscatedSharpCollection/raw/main/NetFramework_4.7_Any/SharpKatz.exe._obf.exe"
    local_file="SharpKatz.exe._obf.exe"
    single_file_check_and_download_file "$download_url" "$local_file"


    # Downloading ADCSPwn.exe._obf.exe
    download_url="https://github.com/Flangvik/ObfuscatedSharpCollection/raw/main/NetFramework_4.7_Any/ADCSPwn.exe._obf.exe"
    local_file="ADCSPwn.exe._obf.exe"
    single_file_check_and_download_file "$download_url" "$local_file"


    # Downloading ADCollector.exe._obf.exe
    download_url="https://github.com/Flangvik/ObfuscatedSharpCollection/raw/main/NetFramework_4.7_Any/ADCollector.exe._obf.exe"
    local_file="ADCollector.exe._obf.exe"
    single_file_check_and_download_file "$download_url" "$local_file"


    # Change owner of the toolsdir
    if [[ "$(stat -c '%U' "${obftoolsdir}")" != "${user_name}" ]]; then
        chown -R "${user_name}:${user_name}" "${obftoolsdir}" 2>/dev/null
    fi

    # Move back to the directory where the script was run from
    cd "${startdir}" || true
    echo -e "${BLUE}[COMPLETE]${NC}"
    echo ""
}


###################################################################################################################
# Function for installing custom webserver from the tools directory and adding a simple function for extracting ports
# from rustscan output. Adding alias for batcat
###################################################################################################################
add_custom_functions() {
    echo -e "${YELLOW}[INFO]${NC} Adding functions to the .zshrc file"
    echo ""

    # Check if zshrc file exists
    if [[ ! -f "$zshrc_file" ]]; then
        echo -e "${RED}[WAR]${NC} File $zshrc_file does not exist. Creating it..."
        touch "$zshrc_file" 2>/dev/null
    fi

    # Custom HTTP server from the tools directory
    if grep -q 'servtools()' "$zshrc_file" 2>/dev/null; then
        echo -e "${GREEN}[OK]${NC}   servtools already installed"
        echo -e "${YELLOW}[INFO]${NC} To use this server, reopen terminal and type ${BLUE}servtools <port>${NC}"
        echo ""
    else
        echo -e "${YELLOW}[INFO]${NC} Adding a custom server for starting HTTP server from ${toolsdir} directory"
        echo -e "${YELLOW}[INFO]${NC} Adding servtools to ${user_home}/.zshrc file"
        cat >> "$zshrc_file" 2>/dev/null << 'SERVTOOLS_EOF'


# My personal configuration

# Http server function which starts an http server from the /tools folder
# Call this function using servtools <port> [--obf]
servtools() {
    GREEN="\e[32m"
    BLUE="\e[34m"
    NC="\e[0m"
    PORT=$1
    if [[ $2 == '--obf' ]]; then
SERVTOOLS_EOF
        echo "        DIR=\"${toolsdir}/obfuscated\"" >> "$zshrc_file" 2>/dev/null
        cat >> "$zshrc_file" 2>/dev/null << 'SERVTOOLS_EOF2'
    else
SERVTOOLS_EOF2
        echo "        DIR=\"${toolsdir}\"" >> "$zshrc_file" 2>/dev/null
        cat >> "$zshrc_file" 2>/dev/null << 'SERVTOOLS_EOF3'
    fi
    IP=$(ip -4 addr show tun0 2>/dev/null | grep -oP "(?<=inet ).*(?=/)" || echo "127.0.0.1")
    echo -e "${GREEN}Files in directory ${BLUE}[${DIR}]${NC}"
    ls "${DIR}"
    echo -e "${GREEN}-------------------------------------------------------------------------${NC}"
    echo -e "[OK] Starting HTTP server from ${GREEN}[${DIR}]${NC} on ${PORT}"
    echo -e "[OK] Address: http://${IP}:${PORT}/"
    python3 -m http.server "$PORT" --directory "$DIR"
}

SERVTOOLS_EOF3

        echo -e "${YELLOW}[INFO]${NC} To use this server, reopen the terminal and type ${BLUE}servtools <port> [--obf]${NC}"
        echo ""
    fi


    # Add alias for batcat
    if grep -q 'alias cat=' "$zshrc_file" 2>/dev/null; then
        echo -e "${GREEN}[OK]${NC}   Alias for batcat is already added."
    else
        echo -e "${YELLOW}[INFO]${NC} Adding alias for batcat to ${user_home}/.zshrc file"
        cat >> "$zshrc_file" 2>/dev/null << 'EOF'
# Better cat (batcat)
alias cat='batcat'
EOF
    fi

    # Add Function to extract ports as a comma-separated list
    if grep -q 'extract_ports()' "$zshrc_file" 2>/dev/null; then
        echo -e "${GREEN}[OK]${NC}   Function to extract ports is already installed"
        echo -e "${YELLOW}[INFO]${NC} To use it, reopen terminal and type ${BLUE}extract_ports <file.txt>${NC}"
    else
        echo -e "${YELLOW}[INFO]${NC} Adding the function extract_ports to ${zshrc_file}"
        cat >> "$zshrc_file" 2>/dev/null << 'EOF'

# Function to extract ports as a comma-separated list
extract_ports() {
    if [[ -z "$1" ]]; then
        echo "Usage: extract_ports <filename>"
        return 1
    fi
    awk '{print $1}' "$1" | grep -o '^[0-9]*' | paste -sd,
}
EOF
        echo -e "${YELLOW}[INFO]${NC} Function extract_ports added successfully. Reopen the terminal to use it."
    fi

    echo ""
    echo -e "${BLUE}[COMPLETE]${NC}"
}


###################################################################################################################
# Menu Function
###################################################################################################################

# Function to display menu and prompt for user's choice.
menu_choice() {
    echo -e "${GREEN}[?]${BLUE} Choose an option:${NC}"
    echo -e "${GREEN}[1]${NC} Install Tools"
    echo -e "${GREEN}[2]${NC} Download Scripts"
    echo -e "${GREEN}[3]${NC} Download Obfuscated Scripts"
    echo -e "${GREEN}[4]${NC} Add Custom functions"
    echo -e "${GREEN}[5]${NC} All the above"
    echo -e "${GREEN}[0]${NC} Exit"

    read -p "Enter choice [0-5]: " choice
    echo ""
    case $choice in
        1) install_tools ;;
        2) download_scripts ;;
        3) download_obfuscated_scripts ;;
        4) add_custom_functions ;;
        5)
            install_tools
            download_scripts
            download_obfuscated_scripts
            add_custom_functions
            ;;
        0)
            echo -e "${YELLOW}[INFO]${NC} Exiting..."
            exit 0
            ;;
        *)
            echo -e "${RED}[WAR]${NC} Invalid option. Please choose a number between 0-5."
            menu_choice
            ;;
    esac
}

# Main execution
ask_update
get_script_dir
menu_choice
