#!/usr/bin/env bash
# gpg-key-manager.sh: Interactive helper to export and import GPG keys for pass / backups

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

command -v gpg >/dev/null 2>&1 || {
    echo -e "${RED}Error: 'gpg' is not installed or not in PATH.${NC}"
    exit 1
}

select_secret_key() {
    echo -e "\n${BLUE}Available secret keys on this system:${NC}\n"
    gpg --list-secret-keys --keyid-format LONG
    echo ""
    read -r -p "Enter Key ID or Email to use: " KEY_ID
    if [[ -z "$KEY_ID" ]]; then
        echo -e "${RED}Key identifier cannot be empty.${NC}"
        return 1
    fi
}

export_backup() {
    select_secret_key || return 1

    local default_dest="$HOME/gpg-backup-$(date +%F)"
    read -e -p "Target directory for backup [$default_dest]: " target_dir
    target_dir="${target_dir:-$default_dest}"
    target_dir="${target_dir/#\~/$HOME}"

    mkdir -p "$target_dir"
    chmod 700 "$target_dir"

    local pub_file="$target_dir/public-key.asc"
    local priv_file="$target_dir/private-key.asc"
    local trust_file="$target_dir/ownertrust.txt"

    echo -e "\n${YELLOW}1. Exporting public key...${NC}"
    gpg --armor --export "$KEY_ID" > "$pub_file"

    echo -e "${YELLOW}2. Exporting private key (you will be prompted for your passphrase)...${NC}"
    gpg --armor --export-secret-keys "$KEY_ID" > "$priv_file"
    chmod 600 "$priv_file"

    echo -e "${YELLOW}3. Exporting owner trust database...${NC}"
    gpg --export-ownertrust > "$trust_file"

    echo -e "\n${GREEN}Backup completed successfully.${NC}"
    echo "Files saved to: $target_dir"
    echo " - Public key : $pub_file"
    echo " - Private key: $priv_file"
    echo " - Trust DB   : $trust_file"
    echo -e "\n${RED}Important: Move this directory to an offline encrypted drive or USB, then remove it from this machine.${NC}"
}

import_backup() {
    echo -e "\n${BLUE}Import GPG Keys${NC}"
    read -e -p "Enter path to backup directory or private key file: " input_path
    input_path="${input_path/#\~/$HOME}"

    if [[ ! -e "$input_path" ]]; then
        echo -e "${RED}Path does not exist: $input_path${NC}"
        return 1
    fi

    local priv_file=""
    local pub_file=""
    local trust_file=""

    if [[ -d "$input_path" ]]; then
        priv_file="$input_path/private-key.asc"
        pub_file="$input_path/public-key.asc"
        trust_file="$input_path/ownertrust.txt"
    else
        priv_file="$input_path"
    fi

    if [[ -f "$pub_file" ]]; then
        echo -e "${YELLOW}Importing public key...${NC}"
        gpg --import "$pub_file"
    fi

    if [[ -f "$priv_file" ]]; then
        echo -e "${YELLOW}Importing private key...${NC}"
        gpg --import "$priv_file"
    else
        echo -e "${RED}Private key file not found: $priv_file${NC}"
        return 1
    fi

    if [[ -f "$trust_file" ]]; then
        echo -e "${YELLOW}Importing trust database...${NC}"
        gpg --import-ownertrust "$trust_file"
    else
        echo -e "\n${YELLOW}Setting trust level manually:${NC}"
        read -r -p "Enter Key ID/Email to set trust: " imported_id
        if [[ -n "$imported_id" ]]; then
            (echo "5"; echo "y"; echo "quit") | gpg --command-fd 0 --edit-key "$imported_id" trust
        fi
    fi

    echo -e "\n${GREEN}Import complete.${NC}"
    echo -e "${BLUE}Current secret keys:${NC}"
    gpg --list-secret-keys --keyid-format LONG
}

show_menu() {
    echo -e "\n${BLUE}=== GPG Key Backup & Restore Manager ===${NC}"
    echo "1) Export GPG keys & trust database (Full Backup)"
    echo "2) Import GPG keys & restore trust"
    echo "3) List existing secret keys"
    echo "4) Exit"
    read -r -p "Select an option [1-4]: " choice

    case "$choice" in
        1) export_backup ;;
        2) import_backup ;;
        3) gpg --list-secret-keys --keyid-format LONG ;;
        4) exit 0 ;;
        *) echo -e "${RED}Invalid selection.${NC}" ;;
    esac
}

if [[ $# -gt 0 ]]; then
    case "$1" in
        export) export_backup ;;
        import) import_backup ;;
        list)   gpg --list-secret-keys --keyid-format LONG ;;
        *)      echo "Usage: $0 [export|import|list]" ; exit 1 ;;
    esac
else
    while true; do
        show_menu
    done
fi
