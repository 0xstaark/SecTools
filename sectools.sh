#!/bin/bash


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
startdir=$(pwd)
user_home=$(eval echo "~$SUDO_USER")
zshrc_file="$user_home/.zshrc"
user_name=${SUDO_USER:-$(whoami)}


echo ""
echo -e ${GREEN}" Created by:"
echo -e " ${RED}   ___              _                     _     "
echo -e " ${YELLOW}  / _ \            | |                   | |    "
echo -e " ${ORANGE} | | | |__  __ ___ | |_  __ _  __ __ ___ | | __ "
echo -e " ${BLUE} | | | |\ \/ // __|| __|/ _\ |/ _\ || __|| |/ / "
echo -e " ${LIGHT_BLUE} | |_| | >  < \__ \| |_| (_| ||(_| || |  |   <  "
echo -e " ${VIOLET}  \___/ /_/\_\|___/ \__|\__,_|\__,_||_|  |_|\_\ "
echo ""
echo -e "${BLUE}https://github.com/0xstaark"${NC}
echo ""


###################################################################################################################
# Directory input with autocomplete
###################################################################################################################
read_directory() {
    local prompt="$1"
    local default="$2"
    local result=""

    # Enable readline completion for directories
    if [[ -n "$BASH_VERSION" ]]; then
        # Save current completion settings
        local old_complete=$(complete -p -D 2>/dev/null || true)

        # Set up directory completion
        bind 'set show-all-if-ambiguous on' 2>/dev/null
        bind 'TAB:complete' 2>/dev/null

        # Use read -e for readline support with tab completion
        read -e -p "$prompt" result

        # Restore settings
        bind 'set show-all-if-ambiguous off' 2>/dev/null
    else
        # Fallback for non-bash shells
        read -p "$prompt" result
    fi

    # Return default if empty
    if [[ -z "$result" ]]; then
        echo "$default"
    else
        echo "$result"
    fi
}


###################################################################################################################
# Check network connection
###################################################################################################################

if ! ping -c 1 8.8.8.8 &> /dev/null; then
    echo -e "${RED}[WAR]${NC} No network connection. Exiting..."
    exit 1
fi


###################################################################################################################
# Define spinner function for Download
###################################################################################################################
spinner() {
    local pid=$!  # Get the PID of the last background process
    local delay=0.1
    local spinstr='|/-\'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${YELLOW}[INFO]${NC} Downloading   %-31s [%c]" "$1" "${spinstr:i:1}"
        i=$(( (i + 1) % ${#spinstr} ))
        sleep $delay
    done
    printf "\r${GREEN}[OK]${NC}   Downloaded   %-31s ${GREEN}[DONE]${NC}\n" "$1"
}


###################################################################################################################
# Define spinner function for cleanup
###################################################################################################################
spinner2() {
    local pid=$!  # Get the PID of the last background process
    local delay=0.1
    local spinstr='|/-\'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${BLUE}[INFO]${NC} Cleanup...                                  [%c]" "${spinstr:i:1}"
        i=$(( (i + 1) % ${#spinstr} ))
        sleep $delay
    done
}


###################################################################################################################
# Define spinner function for update and upgrade
###################################################################################################################
spinner3() {
    local pid=$!  # Get the PID of the last background process
    local delay=0.1
    local spinstr='|/-\'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${YELLOW}[INFO]${NC} %-40s [%c]" "$1" "${spinstr:i:1}"
        i=$(( (i + 1) % ${#spinstr} ))
        sleep $delay
    done
}


###################################################################################################################
# Define spinner function for Tool install
###################################################################################################################
spinner4() {
    local pid=$!  # Get the PID of the last background process
    local delay=0.1
    local spinstr='|/-\'
    local i=0
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${YELLOW}[INFO]${NC} Installing   %-31s [%c]" "$1" "${spinstr:i:1}"
        i=$(( (i + 1) % ${#spinstr} ))
        sleep $delay
    done
}


#####################################################################################################################
# Cleanup and house keeping
#####################################################################################################################
perform_cleanup() {
    # Start spinner and cleanup
    printf "${BLUE}[INFO]${NC} Performing cleanup...   "

    {
        # Perform cleanup operations
        cp mimikatz/x64/mimikatz.exe . >/dev/null 2>&1
        mv RunasCS RunasCS.exe >/dev/null 2>&1
        rm -rf x64 Win32 PassTheCert PetitPotam mimikatz >/dev/null 2>&1

        # Adjust ownership of tools directory if needed
        [[ $(stat -c '%U' "${toolsdir}") != "${user_name}" ]] && chown -R "${user_name}:${user_name}" "${toolsdir}" >/dev/null 2>&1

        # Return to the original directory
        cd "${startdir}"
    } & spinner2  # Spinner runs alongside the cleanup block

    # Overwrite the spinner with the final aligned message
    wait  # Wait for the cleanup to finish
    echo ""
    printf "\r${BLUE}[INFO]${NC} Cleanup...   %-31s ${BLUE}[COMPLETE]${NC}\n" ""
}


###################################################################################################################
# Ask user if they want to update
###################################################################################################################
ask_update() {
    # Display the initial prompt
    printf "\r${YELLOW}[INFO]${NC} Do you want to run 'sudo apt update'? (y/n): "
    read -r choice

    case "$choice" in
        [Yy]* )
            tput cuu1  # Move the cursor up one line
            tput el    # Clear the entire line
            # Overwrite the prompt line and show the spinner
            printf "\r${BLUE}[INFO]${NC} Updating System                           "

            # Run the update command in the background with a spinner
            (
                sudo apt -q update -y >/dev/null 2>&1
            ) & spinner3 "Updating System"

            # Overwrite the spinner with the [COMPLETE] message
            printf "\r${BLUE}[INFO]${NC} Updating System                           ${BLUE}[COMPLETE]${NC}\n"
             ;;
        [Nn]* )
            # Overwrite the prompt line with the skip message
            printf "\r${RED}[INFO]${NC} Skipping update.                          \n"
            ;;
        * )
            # Overwrite the prompt line with an invalid input warning
            printf "\r${RED}[WAR]${NC} Invalid input. Please enter 'y' or 'n'.    \n"
            ;;
    esac
}

###################################################################################################################
# Ask user if they want to upgrade
###################################################################################################################
ask_upgrade() {
    read -p "$(echo -e "${YELLOW}[INFO]${NC} Do you want to run 'sudo apt upgrade'? (y/n): ")" choice

    case "$choice" in
        [Yy]* )
            tput cuu1  # Move the cursor up one line
            tput el    # Clear the entire line
            # Initial line with spinner
            printf "${BLUE}[INFO]${NC} Upgrading System                "

            # Run the upgrade command in the background with the spinner
            (
                sudo apt -q upgrade -y >/dev/null 2>&1
            ) & spinner3 "Upgrading System"

            # Overwrite the spinner line with the [COMPLETE] message
            printf "\r${BLUE}[INFO]${NC} Upgrading System                          ${BLUE}[COMPLETE]${NC}\n"
            ;;
        [Nn]* )
            echo -e "${RED}[INFO]${NC} Skipping upgrade."
            ;;
        * )
            echo -e "${RED}[WAR]${NC} Invalid input. Please enter 'y' or 'n'."
            ;;
    esac
}


###################################################################################################################
# Error handling
###################################################################################################################
handle_error() {
    local tool_name="$1"
    local failed_command="$2"

    echo -e "${RED}[ERROR]${NC} An error occurred while installing ${YELLOW}${tool_name}${NC}."
    echo -e "${RED}[ERROR]${NC} Command: ${YELLOW}${failed_command}${NC}"
    echo -e "${RED}[ERROR]${NC} Possible causes:"
    echo -e "  1. Network issues (check your internet connection)."
    echo -e "  2. Repository problems (try running 'sudo apt update')."
    echo -e "  3. Missing dependencies (check logs or output)."
    echo -e "  4. Insufficient permissions (ensure you are using sudo)."
    echo -e "${RED}[INFO]${NC} Skipping ${tool_name} and continuing with the next tool."
    
    # Optionally log errors to a file
    echo "$(date) - Failed to install ${tool_name} with command: ${failed_command}" >> install_errors.log
}


###################################################################################################################
# Function to handle Git repository downloads
###################################################################################################################
git_download() {
    local repo_url="$1"
    local repo_name="$2"

    if [[ -d "$repo_name" ]]; then
        #printf "${YELLOW}[INFO]${NC} Removing existing %-31s\n" "$repo_name"
        rm -rf "$repo_name"
    fi

    printf "${YELLOW}[INFO]${NC} Cloning       %-31s " "$repo_name"
    (git clone "$repo_url" >/dev/null 2>&1) & spinner "$repo_name"
}


###################################################################################################################
# Function to handle ZIP repository downloads
###################################################################################################################
folder_zip_download() {
    local zip_url="$1"
    local zip_name="$2"
    local extract_dir="${3:-${zip_name%.zip}}"  # Default directory derived from zip name

    # Ensure previous directories and zip files are cleaned up
    if [[ -d "$extract_dir" || -f "$zip_name" ]]; then
        rm -rf "$extract_dir" "$zip_name"
    fi

    # Download the zip file
    (curl -sL "$zip_url" -o "$zip_name" >/dev/null 2>&1) & spinner "$extract_dir"

    # Extract the zip file into the specified directory
    unzip -qo "$zip_name" -d "$extract_dir" >/dev/null 2>&1

    # Clean up the zip file after extraction
    rm -f "$zip_name"
}


###################################################################################################################
# Function to handle single file which are ZIP
###################################################################################################################
single_file_zip_gz() {
    local file_url="$1"
    local file_name="$2"

    # Ensure previous files are cleaned up
    if [[ -f "$file_name" ]]; then
        rm -f "$file_name"
    fi

    # Download the archive file
    (curl -sL "$file_url" -o "$file_name" >/dev/null 2>&1) & spinner "$file_name"

    # Determine file type and extract accordingly
    if [[ "$file_name" == *.gz ]]; then
        # For .gz files, extract as a single file
        gunzip -c "$file_name" > "${file_name%.gz}"
        #printf "\r${GREEN}[OK]${NC} Extracted ${file_name} as ${file_name%.gz}\n"
    elif [[ "$file_name" == *.zip ]]; then
        # For .zip files, extract the single file (assumes only one file inside)
        local extracted_file=$(unzip -Z1 "$file_name" | head -1)
        unzip -p "$file_name" "$extracted_file" > "${file_name%.zip}"
        #printf "\r${GREEN}[OK]${NC} Extracted ${file_name} as ${file_name%.zip}\n"
    else
        printf "\r${YELLOW}[WARNING]${NC} Unsupported file format: ${file_name}\n"
    fi

    # Clean up the downloaded archive file
    rm -f "$file_name"
}


###################################################################################################################
# function to check for latest release of a file and download the file from GitHub if needed a newer version is avilable
###################################################################################################################
# Main Function (Now One Line per Download)
api_file_check_and_download_file() {
    local api_url="$1"
    local filename="$2"
    local filter="$3"

    # Get release information from GitHub API
    local response=$(curl -s "$api_url")

    # Determine if the filename has an extension
    local file_url=""
    if [[ "$filename" =~ \.[a-zA-Z0-9]+$ ]]; then
        # Filename has an extension — use stricter match
        file_url=$(echo "$response" | \
            grep -i 'browser_download_url' | \
            grep -i -w "$filter" | \
            grep -i '\.sh\|\.exe\|\.zip' | \
            head -1 | \
            awk -F '"' '{print $4}')
    else
        # No extension in filename — match more loosely
        file_url=$(echo "$response" | \
            grep -i 'browser_download_url' | \
            grep -i -w "$filter" | \
            head -1 | \
            awk -F '"' '{print $4}')
    fi

    # Extract remote timestamp (optional logic for freshness checking)
    local remote_time=$(echo "$response" | grep -i '"updated_at"' | head -1 | awk -F '"' '{print $4}')
    local remote_timestamp=$(date -d "$remote_time" +%s 2>/dev/null)

    # If no matching file was found, warn and return
    if [[ -z "$file_url" ]]; then
        printf "\r${YELLOW}[WARNING]${NC} Could not find download URL for ${filename}\n"
        return
    fi

    # Download with spinner (Direct or ZIP)
    if [[ "$file_url" == *.zip ]]; then
        local temp_zip="temp_download.zip"
        (curl -sL "$file_url" -o "$temp_zip" >/dev/null 2>&1) & spinner "$filename"

        # Wait for download to complete
        wait

        # List zip contents and find the file (handles subdirectories)
        local extracted_file=$(unzip -Z1 "$temp_zip" 2>/dev/null | grep -i "${filename}$" | head -1)

        # If exact match not found, try partial match
        if [[ -z "$extracted_file" ]]; then
            extracted_file=$(unzip -Z1 "$temp_zip" 2>/dev/null | grep -i "$filename" | head -1)
        fi

        if [[ -z "$extracted_file" ]]; then
            printf "\r${YELLOW}[WARNING]${NC} ${filename} not found in ZIP archive.\n"
            rm -f "$temp_zip"
            return
        fi

        # Extract file (junk paths to flatten directory structure)
        unzip -jo "$temp_zip" "$extracted_file" -d . >/dev/null 2>&1

        # Get the basename in case file was in a subdirectory
        local extracted_basename=$(basename "$extracted_file")

        # Rename to target filename if different
        if [[ "$extracted_basename" != "$filename" && -f "$extracted_basename" ]]; then
            mv "$extracted_basename" "$filename" 2>/dev/null || true
        fi

        rm -f "$temp_zip"

    else
        (curl -sL "$file_url" -o "$filename" >/dev/null 2>&1) & spinner "$filename"
    fi
}


###################################################################################################################
# function to check for latest version of a single file, and download if it's a newer version.
###################################################################################################################
single_file_check_and_download_file() {
    local download_url="$1"
    local local_file="$2"

    # Fetch the `Last-Modified` timestamp from the remote file
    local remote_time=$(curl -sI "$download_url" | grep -i "Last-Modified" | cut -d: -f2- | xargs -I{} date -d {} +%s 2>/dev/null)

    if [[ -f "$local_file" ]]; then
        # Get local file's modification time
        local local_time=$(stat -c "%Y" "$local_file")

        # Compare timestamps
        if [[ "$remote_time" -gt "$local_time" ]]; then
            printf "${YELLOW}[INFO]${NC} Updating      %-31s (Newer version found)\n" "$local_file"
            rm -f "$local_file"  # Remove old file
            printf "${YELLOW}[INFO]${NC} Downloading   %-31s " "$local_file"
            (curl -sL "$download_url" -o "$local_file" >/dev/null 2>&1) & spinner "$local_file"
        else
            printf "${BLUE}[SKIP]${NC} Found        %-31s ${BLUE}[Up-to-Date]${NC}\n" "$local_file"
        fi
    else
        # If file doesn't exist, download it
        printf "${YELLOW}[INFO]${NC} Downloading   %-31s " "$local_file"
        (curl -sL "$download_url" -o "$local_file" >/dev/null 2>&1) & spinner "$local_file"
    fi
}


###################################################################################################################
# Function to download obfuscated scripts from GitHub
###################################################################################################################
download_obfuscated_scripts() {
    local download_url="$1"
    local filename="$2"

    # Require toolsdir to be set already
    if [[ -z "$toolsdir" ]]; then
        echo -e "${RED}[ERROR]${NC} toolsdir is not set."
        return 1
    fi

    local obftoolsdir="${toolsdir}/obfuscated"
    local local_file="${obftoolsdir}/${filename}"

    mkdir -p "$obftoolsdir" >/dev/null 2>&1 || {
        echo -e "${RED}[ERROR]${NC} Could not create directory: ${obftoolsdir}"
        return 1
    }

    if [[ -f "$local_file" ]]; then
        printf "${BLUE}[SKIP]${NC} Found        %-31s ${BLUE}[Already Exists]${NC}\n" "$filename"
    else
        printf "${YELLOW}[INFO]${NC} Downloading   %-31s " "$filename"
        (curl -sL "$download_url" -o "$local_file" >/dev/null 2>&1) & spinner "$filename"
    fi
}


###################################################################################################################
# Tools install function
###################################################################################################################
# Function for installing tools, and then calling the function via the menu
install_tools() {
    # Check if user is NOT root
    if [[ $UID -ne 0 ]]; then
        echo -e "${YELLOW}[WAR]${NC} To install the tools you need to run with SUDO"
        # Ensure the user can sudo or exit
        sudo -v || exit 1
    fi

    echo -e "${GREEN}-------------------------------------------------------${NC}"
    echo -e "${GREEN}[INFO] Installing tools${NC}"
    echo -e "${GREEN}-------------------------------------------------------${NC}"

    # Function to handle tool installation with spinner
install_tool() {
    local tool_name="$1"         # Name of the tool
    local install_command="$2"  # Command to install the tool
    local check_command="$3"    # Command to check if the tool is already installed
    local pre_install_command="$4"  # Optional pre-installation command

    # Start the process on a single line
    printf "\r${YELLOW}[INFO]${NC} Processing   %-31s " "$tool_name"

    # Check if the tool is already installed
    if eval "$check_command"; then
        printf "\r${BLUE}[SKIP]${NC} Found      %-31s ${BLUE}[Installed]${NC}\n" "$tool_name"
        return
    fi

    # Run the pre-installation command if provided
    if [[ -n "$pre_install_command" ]]; then
        printf "\r${YELLOW}[INFO]${NC} Preparing   %-31s " "$tool_name"
        if ! eval "$pre_install_command" >/dev/null 2>&1; then
            printf "\r${RED}[ERROR]${NC} Failed to prepare %-31s ${RED}[FAILED]${NC}\n" "$tool_name"
            echo -e "${RED}[ERROR]${NC} Pre-install command: ${YELLOW}${pre_install_command}${NC}"
            echo "$(date) - Failed to prepare ${tool_name} with pre-install command: ${pre_install_command}" >> install_errors.log
            return 1
        fi
    fi

    # Update status to downloading
    printf "\r${YELLOW}[INFO]${NC} Downloading %-31s " "$tool_name"
    if ! eval "$install_command" >/dev/null 2>&1; then
        printf "\r${RED}[ERROR]${NC} Failed to download %-31s ${RED}[FAILED]${NC}\n" "$tool_name"
        echo -e "${RED}[ERROR]${NC} Command used: ${YELLOW}${install_command}${NC}"
        echo "$(date) - Failed to download ${tool_name} with command: ${install_command}" >> install_errors.log
        return 1
    fi

    # Check if the tool was successfully installed
    if eval "$check_command"; then
        printf "\r${GREEN}[OK]${NC}     Installed  %-31s ${GREEN}[DONE]${NC}\n" "$tool_name"
    else
        printf "\r${RED}[ERROR]${NC} Failed to install %-31s ${RED}[FAILED]${NC}\n" "$tool_name"
        echo "$(date) - Failed to install ${tool_name} with command: ${install_command}" >> install_errors.log
    fi
}


    # Tool installation logic
    install_tool "seclists" \
        "sudo apt-get -qq -y install seclists" \
        "[[ \$(ls /usr/share | grep seclists) == 'seclists' ]]"

    #install_tool "batcat" \
        #"sudo apt-get -qq -y install bat" \
        #"[[ \$(which batcat) == '/usr/bin/batcat' ]]"

    install_tool "rustscan" \
        "deb_url=\$(curl -s https://api.github.com/repos/RustScan/RustScan/releases/latest | grep 'browser_download_url.*amd64.deb' | head -1 | awk -F '\"' '{print \$4}'); if [[ -n \"\$deb_url\" ]]; then sudo wget -q -O rustscan.deb \"\$deb_url\" && sudo dpkg -i rustscan.deb && rm -f rustscan.deb; else echo 'Failed to get RustScan URL' && exit 1; fi" \
        "[[ -x /usr/bin/rustscan ]] || command -v rustscan &>/dev/null"

    install_tool "wfuzz" \
        "sudo apt-get -qq -y install wfuzz" \
        "[[ \$(which wfuzz) == '/usr/bin/wfuzz' ]]"

    install_tool "ffuf" \
        "sudo apt-get -qq -y install ffuf" \
        "[[ \$(which ffuf) == '/usr/bin/ffuf' ]]"

    install_tool "bloodhound" \
        "sudo apt-get -qq -y install bloodhound" \
        "[[ \$(which bloodhound) == '/usr/bin/bloodhound' ]]"

    install_tool "neo4j" \
        "sudo apt-get -qq -y install neo4j" \
        "[[ \$(which neo4j) == '/usr/bin/neo4j' ]]"

    install_tool "gobuster" \
        "sudo apt-get -qq -y install gobuster" \
        "[[ \$(which gobuster) == '/usr/bin/gobuster' ]]"

    install_tool "feroxbuster" \
        "sudo apt-get -qq -y install feroxbuster" \
        "[[ \$(which feroxbuster) == '/usr/bin/feroxbuster' ]]"

    install_tool "certipy-ad" \
        "sudo python3 -m pip install -qq certipy-ad" \
        "[[ \$(which certipy-ad) == '/usr/local/bin/certipy-ad' || \$(which certipy-ad) == '/usr/bin/certipy-ad' ]]"

    install_tool "pypykatz" \
        "sudo python3 -m pip install -qqq pypykatz" \
        "[[ \$(which pypykatz) == '/usr/local/bin/pypykatz' || \$(which pypykatz) == '/usr/bin/pypykatz' ]]"

    install_tool "sublime-text" \
        "sudo wget -qO - https://download.sublimetext.com/sublimehq-pub.gpg | gpg --no-default-keyring --keyring ./temp-keyring.gpg --import && sudo gpg --no-default-keyring --keyring ./temp-keyring.gpg --export --output sublime-text.gpg && sudo rm temp-keyring.gpg temp-keyring.gpg~ && sudo mkdir -p /usr/local/share/keyrings && sudo mv ./sublime-text.gpg /usr/local/share/keyrings && echo 'deb [signed-by=/usr/local/share/keyrings/sublime-text.gpg] https://download.sublimetext.com/ apt/stable/' | sudo tee /etc/apt/sources.list.d/sublime-text.list && sudo apt-get update -qq && sudo apt-get install -qq -y sublime-text" \
        "[[ \$(which subl) == '/usr/bin/subl' ]]"

    install_tool "docker" \
        "sudo apt-get -qq -y install docker.io" \
        "[[ \$(which docker) == '/usr/bin/docker' ]]"

    install_tool "docker-compose" \
        "sudo apt-get -qq -y install docker-compose" \
        "[[ \$(which docker-compose) == '/usr/bin/docker-compose' ]]"
        
    install_tool "bloodhound-CE" \
        "curl -L https://ghst.ly/getbhce -o /opt/bloodhoundCE/docker-compose.yml" \
        "[[ -d /opt/bloodhoundCE && -f /opt/bloodhoundCE/docker-compose.yml ]]" \
        "mkdir -p /opt/bloodhoundCE"
        

    echo ""
    echo -e "${BLUE}[COMPLETE]${NC} All tools installed successfully!"

}

###################################################################################################################
# DOWNLOADING SCRIPTS
###################################################################################################################

# Function for downloading scripts, and then calling the function via the menu
download_scripts() {

# Tools directory
toolsdir="/opt/tools"

# Prompt the user for a custom directory with autocomplete
echo -e "${YELLOW}[INFO]${NC} Choose directory to download Script to. Example: /opt/tools"
echo -e "${YELLOW}[INFO]${NC} ${BLUE}(Tab completion enabled)${NC}"
toolsdir=$(read_directory "$(echo -e "${YELLOW}[INFO]${NC} Enter directory [${YELLOW}${toolsdir}${NC}]: ")" "$toolsdir")

# Check if directory exists
if [[ -d "$toolsdir" ]]; then
    echo -e "${YELLOW}[INFO]${NC} Using directory: [${BLUE}${toolsdir}${YELLOW}]"
else
    mkdir -p "$toolsdir" >/dev/null 2>&1
    # Check if the command succeeded
    if [[ $? -ne 0 ]]; then
        echo ""
        echo -e "${RED}[WAR]${NC} You don't have access to create folders in [${BLUE}${toolsdir}${NC}]. Rerun the script with sudo."
        exit 1
    else
        echo -e "${YELLOW}[INFO]${NC} Created directory: [${BLUE}${toolsdir}${NC}]"
    fi
fi

# Change to the tools directory
cd "$toolsdir"
echo -e "${GREEN}-------------------------------------------------------"
echo -e "${GREEN}[INFO] Downloading Scripts to ${BLUE}[${toolsdir}]${NC}"
echo -e "${GREEN}-------------------------------------------------------${NC}"
sleep 1


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
mimikatz_url=$(curl -s "https://api.github.com/repos/gentilkiwi/mimikatz/releases/latest" | grep "browser_download_url.*mimikatz_trunk.zip" | head -1 | awk -F '"' '{print $4}')
if [[ -n "$mimikatz_url" ]]; then
    folder_zip_download "$mimikatz_url" "mimikatz_trunk.zip" "mimikatz"
else
    printf "${YELLOW}[WARNING]${NC} Could not fetch latest mimikatz version, using fallback\n"
    folder_zip_download "https://github.com/gentilkiwi/mimikatz/releases/download/2.2.0-20220919/mimikatz_trunk.zip" "mimikatz_trunk.zip" "mimikatz"
fi


#####################################################################################################################
# ZIP or gz single file Download
#####################################################################################################################

#Downloading RunasCs.exe (latest version)
runascs_url=$(curl -s "https://api.github.com/repos/antonioCoco/RunasCs/releases/latest" | grep "browser_download_url.*RunasCs.zip" | head -1 | awk -F '"' '{print $4}')
if [[ -n "$runascs_url" ]]; then
    single_file_zip_gz "$runascs_url" "RunasCS.zip"
else
    printf "${YELLOW}[WARNING]${NC} Could not fetch latest RunasCs version, using fallback\n"
    single_file_zip_gz "https://github.com/antonioCoco/RunasCs/releases/download/v1.5/RunasCs.zip" "RunasCS.zip"
fi

#Downloading chisel (latest version)
chisel_url=$(curl -s "https://api.github.com/repos/jpillora/chisel/releases/latest" | grep "browser_download_url.*linux_amd64.gz" | head -1 | awk -F '"' '{print $4}')
chisel_filename=$(basename "$chisel_url" 2>/dev/null)
if [[ -n "$chisel_url" && -n "$chisel_filename" ]]; then
    single_file_zip_gz "$chisel_url" "$chisel_filename"
else
    printf "${YELLOW}[WARNING]${NC} Could not fetch latest chisel version, using fallback\n"
    single_file_zip_gz "https://github.com/jpillora/chisel/releases/download/v1.10.1/chisel_1.10.1_linux_amd64.gz" "chisel_1.10.1_linux_amd64.gz"
fi



# Clean up
perform_cleanup

}


#####################################################################################################################
# Download obfuscated versions
#####################################################################################################################
obfuscated_scripts() {
    # Default base directory
    toolsdir="/opt/tools"

    echo -e "${YELLOW}[INFO]${NC} Choose download directory. An ${BLUE}[Obfuscated]${NC} folder will be created here"
    echo -e "${YELLOW}[INFO]${NC} ${BLUE}(Tab completion enabled)${NC}"
    toolsdir=$(read_directory "$(echo -e "${YELLOW}[INFO]${NC} Enter directory [${YELLOW}${toolsdir}${NC}]: ")" "$toolsdir")

    # Just ensure the directory exists
    if [[ ! -d "$toolsdir" ]]; then
        mkdir -p "$toolsdir" >/dev/null 2>&1 || {
            echo -e "${RED}[WAR]${NC} Cannot create directory: ${RED}[${toolsdir}]${NC}"
            exit 1
        }
        echo -e "${YELLOW}[INFO]${NC} Created directory: ${BLUE}[${toolsdir}/obfuscated]${NC}"
    else
        echo -e "${YELLOW}[INFO]${NC} Using directory: ${BLUE}[${toolsdir}/obfuscated]${NC}"
    fi


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

echo ""
echo -e "${BLUE}[COMPLETE]${NC} Obfuscated scripts downloaded successfully!"
echo ""

}


###################################################################################################################
# Function for installing custom webserver from the tools directory and adding a simple function for extracting ports
# from rustscan output
###################################################################################################################
add_custom_functions() {
    echo -e "${YELLOW}[INFO]${NC} Adding functions to the .zshrc file"
    echo ""
    # Custom HTTP server from the tools directory
    # Adding custom server to server tools to ~/.bashrc
    if grep -q 'servtools()' "$zshrc_file" 2>/dev/null; then
        echo -e "${GREEN}[OK]${NC} servtools already installed"
        echo -e "${YELLOW}[INFO]${NC} To use this server, reopen terminal and type ${BLUE}servtools <port>"
        echo ""
    else
        echo -e "${YELLOW}[!] Adding a custom server for starting HTTP server from ${toolsdir} directory"
        echo -e "${YELLOW}[!] Adding servtools to ${user_home}/.zshrc file}"
        echo "" >> "$zshrc_file" 2>/dev/null
        echo "" >> "$zshrc_file" 2>/dev/null
        echo "" >> "$zshrc_file" 2>/dev/null
        echo "" >> "$zshrc_file" 2>/dev/null
        echo "# My personal configuration" >> "$zshrc_file" 2>/dev/null
        echo "" >> "$zshrc_file" 2>/dev/null
        echo "# Http server function which starts an http server from the /tools folder" >> "$zshrc_file" 2>/dev/null
        echo "# Call this function using servtools <port> [--obf]" >> "$zshrc_file" 2>/dev/null
        echo "servtools() {" >> "$zshrc_file" 2>/dev/null
        echo '    GREEN="\e[32m"' >> "$zshrc_file" 2>/dev/null
        echo '    NC="\e[0m"' >> "$zshrc_file" 2>/dev/null
        echo "    PORT=\$1" >> "$zshrc_file" 2>/dev/null
        echo "    if [[ \$2 == '--obf' ]]; then" >> "$zshrc_file" 2>/dev/null
        echo '        DIR="'${toolsdir}'/obfuscated"' >> "$zshrc_file" 2>/dev/null
        echo "    else" >> "$zshrc_file" 2>/dev/null
        echo '        DIR="'${toolsdir}'"' >> "$zshrc_file" 2>/dev/null
        echo "    fi" >> "$zshrc_file" 2>/dev/null
        echo "    IP=\$(ip -4 addr show tun0 | grep -oP \"(?<=inet ).*(?=/)\")" >> "$zshrc_file" 2>/dev/null
        echo '    echo -e "${GREEN}Files in directory ${BLUE}[${DIR}]${NC}"' >> "$zshrc_file" 2>/dev/null
        echo '    ls ${DIR}' >> "$zshrc_file" 2>/dev/null
        echo '    echo -e "${GREEN}-------------------------------------------------------------------------${NC}"' >> "$zshrc_file" 2>/dev/null
        echo "    echo -e \"[OK] Starting HTTP server from \${GREEN}[\$DIR]\${NC} on \$PORT\"" >> "$zshrc_file" 2>/dev/null
        echo "    echo -e \"[OK] Address: http://\$IP:\$PORT/\"" >> "$zshrc_file" 2>/dev/null
        echo "    python3 -m http.server \$PORT --directory \$DIR" >> "$zshrc_file" 2>/dev/null
        echo '}' >> "$zshrc_file" 2>/dev/null
        echo "" >> "$zshrc_file" 2>/dev/null
        echo "" >> "$zshrc_file" 2>/dev/null

        echo -e "${YELLOW}[INFO]${NC} To use this server, reopen the terminal and type ${BLUE}servtools <port> [--obf]"
        echo ""
        source "$zshrc_file" 2>/dev/null
    fi


    # Add alias for batcat
    #if [[ $(cat "$zshrc_file" | grep -o 'alias cat') == 'alias cat' ]]; then
    #    echo -e "${GREEN}[OK]${NC} Alias for batcat is already added."
    #else
    #    echo -e "${YELLOW}[INFO]${NC} Adding alias for batcat to ${user_home}/.zshrc file}"
    #    echo "# Better cat (batcat)" >> "$zshrc_file" 2>/dev/null
    #    echo "alias cat='batcat'" >> "$zshrc_file" 2>/dev/null
        source "$zshrc_file" 2>/dev/null
    #fi

# Add Function to extract ports as a comma-separated list
    if grep -q 'extract_ports()' "$zshrc_file" 2>/dev/null; then
        echo -e "${GREEN}[OK]${NC} Function to extract ports is already installed"
        echo -e "${YELLOW}[INFO]${NC} To use it, reopen terminal and type ${BLUE}extract_ports <file.txt>${NC}"
    else
        echo "" >> "$zshrc_file" 2>/dev/null
        echo "" >> "$zshrc_file" 2>/dev/null
        echo -e "${YELLOW}[INFO]${NC} Adding the function extract_ports to ${zshrc_file}"
        echo "# Function to extract ports as a comma-separated list" >> "$zshrc_file" 2>/dev/null
        echo "extract_ports() {" >> "$zshrc_file" 2>/dev/null
        echo '    if [[ -z "$1" ]]; then' >> "$zshrc_file" 2>/dev/null
        echo '        echo "Usage: extract_ports <filename>"' >> "$zshrc_file" 2>/dev/null
        echo '        return 1' >> "$zshrc_file" 2>/dev/null
        echo '    fi' >> "$zshrc_file" 2>/dev/null
        echo '    awk '"'"'{print $1}'"'"' "$1" | grep -o '"'"'^[0-9]*'"'"' | paste -sd,' >> "$zshrc_file" 2>/dev/null
        echo "}" >> "$zshrc_file" 2>/dev/null
        echo "" >> "$zshrc_file" 2>/dev/null
        echo -e "${YELLOW}[INFO]${NC} Function extract_ports added successfully. Reopen the terminal to use it."
    fi

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
    echo -e "${GREEN}[4]${NC} Add Custom function"
    echo -e "${GREEN}[5]${NC} All the above"
    echo -e "${GREEN}[0]${NC} Exit"
    
    # Prompt for input
    printf "\r${YELLOW}[INFO]${NC} Enter choice [1-5]: [0] To Exit: "
    read -r choice
    
        
    echo ""
    case $choice in
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
            echo -e "${YELLOW}[INFO]${NC} Exiting..."
            exit 0
            ;;
        *)
            echo -e "${RED}[WAR]${NC} Invalid option. Please choose a number between 0-5."
            #menu_choice
            ;;

    esac
}
ask_update
ask_upgrade
menu_choice
