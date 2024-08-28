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
user_home=$HOME
startdir=$(pwd)


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
# Check network connection
###################################################################################################################

if ! ping -c 1 8.8.8.8 &> /dev/null; then
	echo ${RED}"No network connection. Exiting..."${NC}
	exit 1
fi


###################################################################################################################
# function to check for latest release of a file and download the file from GitHub if needed a newer version is avilable
###################################################################################################################
check_and_download_file() {
    local api_url="$1"
    local file_url="$2"
    local local_file="$3"
    local local_file2="${4:-$local_file}"

    #Finding latest release
    #latest=$(curl -s "$api_url" | grep -i 'browser_download_url' | head -1 | awk '{print $2}' | awk -F "/" '{print $8}')
    #new_url=$(echo "$file_url" | sed "s/\\.\\*/$latest/")

    # Get the time from the GitHub API
    github_time=$(curl -s "$api_url" | grep 'updated_at' | head -1 | sed 's/ //g' | awk -F '"' '{print $4}' | sed 's/T02.*//')

    # Check if the file exists locally
    if [[ -f "$local_file" || -f $local_file2 ]]; then
        # Get the time from the local file
        local_time=$(stat -c "%y" "$local_file" 2>/dev/null | awk '{print $1}')

        # Convert the times to timestamps
        github_timestamp=$(date -d "$github_time" +%s)
        local_timestamp=$(date -d "$local_time" +%s)
	
        # Compare the timestamps to identify the newest file
        if [ "$github_timestamp" -gt "$local_timestamp" ]; then
            # Download the file
            rm -r "$local_file" 2>/dev/null
            wget -q "$file_url" >/dev/null 2>&1
            if [[ -f "$local_file" || -f "$local_file2" ]]; then
                printf "${YELLOW}[INFO] %-15s %s\n" "Downloading:" "$local_file"
            else
                printf "${RED}[WARNING] %-15s %s\n" "Failed to download:" "$local_file"
            fi
        else
            echo -e ${GREEN}"[OK] You already have the newest version of:" ${YELLOW}"$local_file"${NC}
        fi
    else
        # If the file doesn't exist, download it
        wget -q "$file_url" >/dev/null 2>&1
        if [[ -f "$local_file" || -f "$local_file2" ]]; then
            printf "${YELLOW}[INFO] %-15s %s\n" "Downloading:" "$local_file"
        else
            printf "${RED}[WARNING] %-15s %s\n" "Failed to download:" "$local_file"
        fi
    fi
}


###################################################################################################################
# function to check for latest version of a single file, and download if it's a newer version.
###################################################################################################################
single_file_check_and_download_file() {
    local download_url="$1"
    local local_file="$2"


    # Get the time from the GitHub API
    github_time=$(curl -s $download_url | grep 'created_at' | sed 's/ //g' | awk -F '"' '{print $4}' | sed 's/T.*//')

    # Check if file exists
    if [[ -f "$local_file" ]]; then
        # Get the time from the local file
        local_time=$(stat -c "%y" "$local_file" 2>/dev/null | awk '{print $1}')  
    
        # Convert the times to timestamps
        github_timestamp=$(date -d "$github_time" +%s)
        local_timestamp=$(date -d "$local_time" +%s)

        # Compare the timestamps to identify the newest file
        if [ "$github_timestamp" -gt "$local_timestamp" ]; then
            # Download file
    	    wget -q "$download_url" >/dev/null 2>&1
	    if [[ -f $local_file ]]; then
	        printf "${YELLOW}[INFO] %-15s %s\n" "Downloading:" "$local_file"	
	    else
                printf "${RED}[WARNING] %-15s %s\n" "Failed to download:" "$local_file"
            fi
        else 
            echo -e ${GREEN}"[OK] You already have the newest version of:" ${YELLOW}"$local_file"${NC}
        fi
    else
        # If the file doesn't exist, download it
        wget -q "$download_url" >/dev/null 2>&1
        if [[ -f $local_file ]]; then
	    printf "${YELLOW}[INFO] %-15s %s\n" "Downloading:" "$local_file"	
        else
            printf "${RED}[WARNING] %-15s %s\n" "Failed to download:" "$local_file"
        fi
    fi
}


###################################################################################################################
# INSTALING TOOLLS
###################################################################################################################
#Fuction for Installing tools, and then calling the function via the menu
install_tools() {

# Check if user is NOT root
if [[ $UID -ne 0 ]]; then
	echo -e "${YELLOW}[!] To install the tools you need to run with SUDO"${NC}
        # Ensure the user can sudo or exit
        sudo -v || exit 1
fi

echo -e ${GREEN}"-----------------------------------------------------"
echo -e ${GREEN}"[INFO] Installing tools"
echo -e ${GREEN}"-----------------------------------------------------"


#Installing seclists
if [[ $(ls /usr/share | grep seclists) == 'seclists' ]]; then
	printf "${GREEN}[OK]${GREEN} %-15s %s\n" "seclists" "Already installed"

else
	printf "${YELLOW}[INFO]${YELLOW} %-15s %s\n" "Installing" "seclists   ${RED}!This may take a while!${NC}"
	sudo apt-get -qq -y install seclists >/dev/null 2>&1
fi


#Installing Terminator
#if [[ $(which terminator) == '/usr/bin/terminator' ]]; then
#	printf "${GREEN}[OK]${GREEN} %-15s %s\n" "Terminator" "Already installed"
#
#else
#	printf "${YELLOW}[INFO]${YELLOW} %-15s %s\n" "Installing" "Terminator"
#	sudo apt-get -qq -y install terminator >/dev/null 2>&1
#fi


# Intalling batcat
if [[ $(which batcat) == '/usr/bin/batcat' ]]; then
	printf "${GREEN}[OK]${GREEN} %-15s %s\n" "Batcat" "Already installed"

else
	printf "${YELLOW}[INFO]${YELLOW} %-15s %s\n" "Installing" "batcat"
	sudo apt-get -qq -y install bat >/dev/null 2>&1
fi


#Intalling Rustscan
if [[ $(which rustscan) == '/usr/bin/rustscan' ]]; then
	printf "${GREEN}[OK]${GREEN} %-15s %s\n" "Rustscan" "Already installed"

else
	printf "${YELLOW}[INFO]${YELLOW} %-15s %s\n" "Installing" "Rustscan"
	versionnr=$(curl -s https://api.github.com/repos/RustScan/RustScan/releases | grep 'browser_download_url' | head -1 | tr -d " " | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
	sudo wget -q -O rustscan.deb https://github.com/RustScan/RustScan/releases/download/${versionnr}rustscan_${versionnr}_amd64.deb && dpkg -i rustscan.deb >/dev/null 2>&1
	rm rustscan.deb >/dev/null >&1
fi


#Insatlling wfuzz
if [[ $(which wfuzz) == '/usr/bin/wfuzz' ]]; then
	printf "${GREEN}[OK]${GREEN} %-15s %s\n" "wfuzz" "Already installed"

else
	printf "${YELLOW}[INFO]${YELLOW} %-15s %s\n" "Installing" "wfuzz"
	sudo apt-get -q -y install wfuzz >/dev/null 2>&1
fi


#Installing ffuf
if [[ $(which ffuf) == '/usr/bin/ffuf' ]]; then
	printf "${GREEN}[OK]${GREEN} %-15s %s\n" "ffuf" "Already installed"

else
	printf "${YELLOW}[INFO]${YELLOW} %-15s %s\n" "Installing" "ffuf"
	sudo apt-get -q -y install ffuf >/dev/null 2>&1
fi


#Installing Bloodhound
if [[ $(which bloodhound) == '/usr/bin/bloodhound' ]]; then
	printf "${GREEN}[OK]${GREEN} %-15s %s\n" "Bloodhound" "Already installed"

else
	printf "${YELLOW}[INFO]${YELLOW} %-15s %s\n" "Installing" "bloodhound"
	sudo apt-get -q -y install bloodhound >/dev/null 2>&1
fi


#Installing Neo4j
if [[ $(which neo4j) == '/usr/bin/neo4j' ]]; then
	printf "${GREEN}[OK]${GREEN} %-15s %s\n" "Neo4j" "Already installed"

else
	printf "${YELLOW}[INFO]${YELLOW} %-15s %s\n" "Installing" "Neo4j"
	sudo apt-get -qq -y install neo4j >/dev/null 2>&1
fi


#Installing GoBuster
if [[ $(which gobuster) == '/usr/bin/gobuster' ]]; then
	printf "${GREEN}[OK]${GREEN} %-15s %s\n" "GoBuster" "Already installed"

else
	printf "${YELLOW}[INFO]${YELLOW} %-15s %s\n" "Installing" "GoBuster"
	sudo apt-get -q -y install gobuster >/dev/null 2>&1
fi


#Installing feroxbuster
if [[ $(which feroxbuster) == '/usr/bin/feroxbuster' ]]; then
	printf "${GREEN}[OK]${GREEN} %-15s %s\n" "Feroxbuster" "Already installed"

else
	printf "${YELLOW}[INFO]${YELLOW} %-15s %s\n" "Installing" "Feroxbuster"
	sudo apt-get -q -y install feroxbuster >/dev/null 2>&1
fi


#Installing Coercer
if [[ $(which coercer) == '/usr/local/bin/coercer' || $(which coercer) == '/usr/bin/coercer' ]]; then
	printf "${GREEN}[OK]${GREEN} %-15s %s\n" "Coercer" "Already installed"

else
	printf "${YELLOW}[INFO]${YELLOW} %-15s %s\n" "Installing" "Coercer"
	sudo pip3 install -qqq coercer 2>/dev/null
fi


#Installing Certipy-ad
if [[ $(which certipy-ad) == '/usr/local/bin/certipy-ad' || $(which certipy-ad) == '/usr/bin/certipy-ad' ]]; then
	printf "${GREEN}[OK]${GREEN} %-15s %s\n" "Certipy-ad" "Already installed"

else
	printf "${YELLOW}[INFO]${YELLOW} %-15s %s\n" "Installing" "Certipy-ad"
	sudo python3 -m pip install -q certipy-ad 2>/dev/null
fi

#Installing NetExec
#if [[ $(which netexec) == '/root/.local/bin/netexec' || $(which nxc) == '/root/.local/bin/nxc' || $(which netexec) == '/usr/bin/netexec' || $(which nxc) == '/usr/bin/nxc' ]]; then
#	printf "${GREEN}[OK]${GREEN} %-15s %s\n" "NetExec" "Already installed"
#
#else
#	printf "${YELLOW}[INFO]${YELLOW} %-15s %s\n" "Installing" "NetExec"
#	echo -e "${YELLOW} This my take a while${NC}"
#	sudo apt-get -q install -y pipx 2>/dev/null 2>&1
#	pipx --quiet ensurepath 2>/dev/null 2>&1
#	pipx --quiet install git+https://github.com/Pennyw0rth/NetExec 2>/dev/null
#fi

#Installing pypykatz
if [[ $(which pypykatz) == '/usr/local/bin/pypykatz' || $(which pypykatz) == '/usr/bin/pypykatz' ]]; then
	printf "${GREEN}[OK]${GREEN} %-15s %s\n" "pypykatz" "Already installed"

else
	printf "${YELLOW}[INFO]${YELLOW} %-15s %s\n" "Installing" "pypykatz"
	sudo pip -qqq install pypykatz 2>/dev/null
fi

echo -e "${BLUE}[COMPLETE]"${NC}
}


###################################################################################################################
# DONWLOADING SCRIPTS
###################################################################################################################

#Fuction for dowloading scripts, and then calling the function via the menu
download_scripts() {

# Default directory
toolsdir="/opt/tools"

# Prompt the user for a custom directory
echo -e "${YELLOW}[INFO]${NC} Choose directory to download Script to. Example: ${BLUE}[ /opt/tools ]${NC}"
read -p "$(echo -e "${YELLOW}[INFO]${NC} Enter the directory to use, hit ENTER for default: ${YELLOW}[ ${toolsdir} ]${NC}: ")" userdir

# If user provides input, use it as the tools directory
if [[ -n "$userdir" ]]; then
    toolsdir="$userdir"
fi

# Check if directory exists
if [[ -d "$toolsdir" ]]; then
    echo -e ${YELLOW}"[INFO] Using directory: [${BLUE}${toolsdir}${YELLOW}]"
else
    echo -e ${YELLOW}"[INFO] Creating directory: [${BLUE}${toolsdir}${GREEN}${YELLOW}]${NC}"
    mkdir -p "$toolsdir"
fi

# Change to the tools directory
cd "$toolsdir"
echo -e ${GREEN}"-----------------------------------------------------"
echo -e ${GREEN}"[INFO] Downloading Scripts into ${BLUE}[${toolsdir}]"
echo -e ${GREEN}"-----------------------------------------------------"
sleep 1


################
#Latest releases
################

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


#############
#Single files
#############

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


###################
#zip files and .git
###################

#Downloading Microsoft sysinternal PSTools
download_url="https://download.sysinternals.com/files/PSTools.zip"
local_file="PSTools"

# Check if download URL is non-empty
if [[ ! -z "$download_url" ]]; then
    # Check if file exists, if yes, remove it
    if [[ -d "$local_file" ]]; then
        rm -r "$local_file"
    fi
    # Download the file
    printf "${YELLOW}[INFO] %-15s %s\n" "Downloading:" "$local_file"
    wget -q "$download_url" >/dev/null 2>&1
    unzip -q PSTools.zip -d PSTools
    rm PSTools.zip 2>/dev/null
else
    echo -e ${RED}"Failed to download ${YELLOW}$local_file${NC}"
fi


#Downloading AutoRecon and installing requrements.
download_url="https://github.com/Tib3rius/AutoRecon.git"
local_file="AutoRecon"

# Check if download URL is non-empty
if [[ ! -z "$download_url" ]]; then
    # Check if file exists, if yes, remove it
    if [[ -d "$local_file" ]]; then
        rm -r "$local_file"
    fi
    # Download the file
    printf "${YELLOW}[INFO] %-15s %s\n" "Downloading:" "$local_file"
    git clone "$download_url" >/dev/null 2>&1
    pip install -r AutoRecon/requirements.txt >/dev/null 2>&1
else
    echo -e ${RED}"Failed to download ${YELLOW}$local_file${NC}"
fi


#Downloading PassTheCert
download_url="https://github.com/AlmondOffSec/PassTheCert.git"
local_file="passthecert.py"

# Check if download URL is non-empty
if [[ ! -z "$download_url" ]]; then
    # Check if file exists, if yes, remove it
    if [[ -d "$local_file" ]]; then
        rm -r "$local_file"
    fi
    # Download the file
    printf "${YELLOW}[INFO] %-15s %s\n" "Downloading:" "$local_file"
    git clone "$download_url" >/dev/null 2>&1
    cp PassTheCert/Python/passthecert.py .

else
    echo -e ${RED}"Failed to download ${YELLOW}$local_file${NC}"
fi


#Downloading PetitPotam
download_url="https://github.com/topotam/PetitPotam.git"
local_file="PetitPotam.py"

# Check if download URL is non-empty
if [[ ! -z "$download_url" ]]; then
    # Check if file exists, if yes, remove it
    if [[ -d "$local_file" ]]; then
        rm -r "$local_file"
    fi
    # Download the file
    printf "${YELLOW}[INFO] %-15s %s\n" "Downloading:" "$local_file"
    git clone "$download_url" >/dev/null 2>&1
    cp PetitPotam/PetitPotam.py . 

else
    echo -e ${RED}"Failed to download ${YELLOW}$local_file${NC}"
fi


#Downloading SprayingToolkit
download_url="https://github.com/byt3bl33d3r/SprayingToolkit.git"
local_file="SprayingToolkit"

# Check if download URL is non-empty
if [[ ! -z "$download_url" ]]; then
    # Check if file exists, if yes, remove it
    if [[ -d "$local_file" ]]; then
        rm -r "$local_file"
    fi
    # Download the file
    printf "${YELLOW}[INFO] %-15s %s\n" "Downloading:" "$local_file"
    git clone "$download_url" >/dev/null 2>&1
    
else
    echo -e ${RED}"Failed to download ${YELLOW}$local_file${NC}"
fi


###################################################################################################################
# Cleanup and house keeping
###################################################################################################################
echo -e ${BLUE}"[INFO] ${BLUE}Performing cleanup${NC}"
if [ ! -f "mimikatz.exe" ]; then
    unzip mimikatz*.zip >/dev/null 2>&1
    cp x64/mimikatz.exe . >/dev/null 2>&1
    rm mimikatz*.zip 2>/dev/null
fi
#unzip mimikatz*.zip >/dev/null 2>&1

if [ ! -f "SharpHound.exe" ]; then
    unzip SharpHound*.zip >/dev/null 2>&1
    rm -r SharpHound*.zip 2>/dev/null
fi
#unzip SharpHound*.zip >/dev/null 2>&1

#unzip -qq *.zip >/dev/null 2>&1
rm *.zip *.config *.dll *.pdb *.txt *.chm *.idl *.md *.yar >/dev/null 2>&1
rm -r x64 Win32 >/dev/null 2>&1
rm -rf PassTheCert >/dev/null 2>&1
rm -rf PetitPotam >/dev/null 2>&1
cp kerbrute_linux_amd64 /usr/local/bin/kerbrute_linux && chmod +x /usr/local/bin/kerbrute_linux 2>/dev/null
###################################################################################################################
###################################################################################################################


cd ${startdir}
echo -e ${BLUE}"[COMPLETE]"${NC}
echo -e ${GREEN}"---------------------------------------------"


###################################################################################################################
# Custom HTTP server from the tools directory
###################################################################################################################

#Adding custom server to server tools to ~/.bashrc
if [[ $(cat ~/.zshrc | grep -o 'servtools()') == 'servtools()' ]]; then
	echo -e "${GREEN}[OK]${GREEN} servtools already installed"
	echo -e "${YELLOW}[INFO] To use this server, reopen terminal and type ${BLUE}servtools <port>"

else
	echo -e "${YELLOW}[!] Adding a custom server for starting HTTP.server form the tools directory"
	echo -e "${YELLOW}[!] Adding servtools to ${user_home}/.zshrc file}"
	echo "" >> ~/.zshrc 2>/dev/null
	echo "" >> ~/.zshrc 2>/dev/null
	echo "" >> ~/.zshrc 2>/dev/null
	echo "" >> ~/.zshrc 2>/dev/null
	echo "# My personal configuration" >> ~/.zshrc 2>/dev/null
	echo "" >> ~/.zshrc 2>/dev/null
	echo "# Http server function which starts an http server from the /tools folder" >> ~/.zshrc 2>/dev/null
	echo "# Call this function using servtools <port>" >> ~/.zshrc 2>/dev/null
	echo "servtools() {" >> ~/.zshrc 2>/dev/null
	echo '    GREEN="\e[32m"' >> ~/.zshrc 2>/dev/null
	echo '    NC="\e[0m"' >> ~/.zshrc 2>/dev/null
	echo "    PORT=\$1" >> ~/.zshrc 2>/dev/null
	echo '    DIR="mySuperuniqvalue"' >> ~/.zshrc 2>/dev/null
	echo "    IP=\$(ip -4 addr show tun0 | grep -oP \"(?<=inet ).*(?=/)\")" >> ~/.zshrc 2>/dev/null
	echo '    echo -e "${GREEN}Files in directory ${BLUE}[${DIR}]${NC}"' >> ~/.zshrc 2>/dev/null
	echo '    ls ${DIR}' >> ~/.zshrc 2>/dev/null
	echo '    echo -e "${GREEN}-------------------------------------------------------------------------${NC}"' >> ~/.zshrc 2>/dev/null
	echo "    echo -e \"[OK] Starting HTTP server from \${GREEN}[\$DIR]\${NC} on \$PORT\"" >> ~/.zshrc 2>/dev/null
	echo "    echo -e \"[OK] Address: http://\$IP:\$PORT/\"" >> ~/.zshrc 2>/dev/null
	echo "    python3 -m http.server \$PORT --directory \$DIR" >> ~/.zshrc 2>/dev/null
	echo '}' >> ~/.zshrc 2>/dev/null
	echo "" >> ~/.zshrc 2>/dev/null
	echo "" >> ~/.zshrc 2>/dev/null
	echo "# Better cat (batcat)" >> ~/.zshrc 2>/dev/null
	echo "alias cat='batcat'" >> ~/.zshrc 2>/dev/null
	source ~/.zshrc 2>/dev/null
fi
sed -i 's@DIR="mySuperuniqvalue"@DIR="'${toolsdir}'"@' ~/.zshrc
echo ""
echo -e ${BLUE}"[INFO] Please restart your terminal${NC}"
echo -e ${GREEN}"---------------------------------------------"
}


###################################################################################################################
# Menu Function
###################################################################################################################

# Function to display menu and prompt for user's choice.
menu_choice() {
    echo -e "${GREEN}[?]${BLUE} Choose an option:${NC}"
    echo -e "${GREEN}[1]${YELLOW} Install Tools${NC}"
    echo -e "${GREEN}[2]${YELLOW} Download Scripts${NC}"
    echo -e "${GREEN}[3]${YELLOW} All the above${NC}"
    echo -e "${GREEN}[0]${YELLOW} Exit${NC}"
    
    read -p "Enter choice [1-3]: [0] To Exit: " choice
    echo ""
    case $choice in
        1) install_tools ;;
        2) download_scripts ;;
        3) 
            install_tools
            download_scripts
            ;;
        0) 
            echo -e "${GREEN}[OK] Exiting...${NC}"
            exit 0
            ;;
        *) 
            echo -e "${RED}[!] Invalid option. Please choose a number between 0-3.${NC}"
            #menu_choice
            ;;
    esac
}

menu_choice
