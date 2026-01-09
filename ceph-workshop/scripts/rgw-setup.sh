#!/bin/bash
# =============================================================================
# Script de Configuration RGW (S3/Swift Gateway)
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

STATE_DIR="/var/lib/ceph/state/rgw"

show_help() {
    cat << EOF

Usage: $0 <command> [options]

Commands:
    user create --uid=<uid> --display-name=<name>   Creer un utilisateur S3
    user list                                        Lister les utilisateurs
    user info --uid=<uid>                           Info utilisateur
    user delete --uid=<uid>                         Supprimer un utilisateur
    bucket list                                      Lister les buckets
    bucket stats --bucket=<name>                    Stats d'un bucket
    quota set --uid=<uid> --max-size=<size>         Definir un quota

Examples:
    $0 user create --uid=workshop --display-name="Workshop User"
    $0 user list
    $0 bucket list

EOF
}

generate_key() {
    head -c 20 /dev/urandom | base64 | tr -d '/+=' | head -c 20
}

generate_secret() {
    head -c 40 /dev/urandom | base64 | tr -d '/+=' | head -c 40
}

create_user() {
    local uid=""
    local display_name=""
    local email=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --uid=*) uid="${1#*=}"; shift ;;
            --uid) uid="$2"; shift 2 ;;
            --display-name=*) display_name="${1#*=}"; shift ;;
            --display-name) display_name="$2"; shift 2 ;;
            --email=*) email="${1#*=}"; shift ;;
            --email) email="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    if [ -z "$uid" ] || [ -z "$display_name" ]; then
        echo -e "${RED}Erreur: --uid et --display-name requis${NC}"
        exit 1
    fi

    mkdir -p "$STATE_DIR/users"

    local access_key=$(generate_key)
    local secret_key=$(generate_secret)

    cat > "$STATE_DIR/users/$uid" << EOF
{
    "user_id": "$uid",
    "display_name": "$display_name",
    "email": "${email:-$uid@example.com}",
    "keys": [
        {
            "access_key": "$access_key",
            "secret_key": "$secret_key"
        }
    ],
    "caps": [],
    "max_buckets": 1000,
    "quota": {
        "enabled": false,
        "max_size": -1,
        "max_objects": -1
    }
}
EOF

    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    USER CREATED SUCCESSFULLY                      ║${NC}"
    echo -e "${GREEN}╠═══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  User ID:      $uid"
    echo -e "${GREEN}║${NC}  Display Name: $display_name"
    echo -e "${GREEN}║${NC}  Email:        ${email:-$uid@example.com}"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${YELLOW}Credentials (SAVE THESE!):${NC}"
    echo -e "${GREEN}║${NC}  Access Key:   $access_key"
    echo -e "${GREEN}║${NC}  Secret Key:   $secret_key"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Configuration AWS CLI:"
    echo ""
    echo "  aws configure"
    echo "  AWS Access Key ID: $access_key"
    echo "  AWS Secret Access Key: $secret_key"
    echo ""
    echo "Ou creez ~/.aws/credentials:"
    echo ""
    echo "  [default]"
    echo "  aws_access_key_id = $access_key"
    echo "  aws_secret_access_key = $secret_key"
    echo ""
    echo "Endpoint RGW: http://ceph-rgw:7480"
    echo ""
}

list_users() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                        RGW USERS                                  ║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}"

    if [ -d "$STATE_DIR/users" ] && [ "$(ls -A $STATE_DIR/users 2>/dev/null)" ]; then
        for user in $(ls "$STATE_DIR/users"); do
            echo -e "${CYAN}║${NC}  - $user"
        done
    else
        echo -e "${CYAN}║${NC}  (aucun utilisateur)"
    fi

    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

user_info() {
    local uid=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --uid=*) uid="${1#*=}"; shift ;;
            *) shift ;;
        esac
    done

    if [ -z "$uid" ]; then
        echo -e "${RED}Erreur: --uid requis${NC}"
        exit 1
    fi

    local user_file="$STATE_DIR/users/$uid"

    if [ ! -f "$user_file" ]; then
        echo -e "${RED}Erreur: Utilisateur '$uid' non trouve${NC}"
        exit 1
    fi

    echo ""
    echo -e "${CYAN}User Info: $uid${NC}"
    echo ""
    cat "$user_file" | python3 -m json.tool 2>/dev/null || cat "$user_file"
    echo ""
}

list_buckets() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                        RGW BUCKETS                                ║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  BUCKET                  OWNER        SIZE      OBJECTS"
    echo -e "${CYAN}║${NC}  ────────────────────────────────────────────────────────"

    if [ -d "$STATE_DIR/buckets" ] && [ "$(ls -A $STATE_DIR/buckets 2>/dev/null)" ]; then
        for bucket in $(ls "$STATE_DIR/buckets"); do
            local owner=$(cat "$STATE_DIR/buckets/$bucket/owner" 2>/dev/null || echo "unknown")
            local size=$(cat "$STATE_DIR/buckets/$bucket/size" 2>/dev/null || echo "0")
            local objects=$(cat "$STATE_DIR/buckets/$bucket/objects" 2>/dev/null || echo "0")
            printf "${CYAN}║${NC}  %-24s %-12s %-9s %s\n" "$bucket" "$owner" "$size" "$objects"
        done
    else
        echo -e "${CYAN}║${NC}  (aucun bucket)"
    fi

    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

set_quota() {
    local uid=""
    local max_size=""
    local max_objects=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --uid=*) uid="${1#*=}"; shift ;;
            --max-size=*) max_size="${1#*=}"; shift ;;
            --max-objects=*) max_objects="${1#*=}"; shift ;;
            *) shift ;;
        esac
    done

    if [ -z "$uid" ]; then
        echo -e "${RED}Erreur: --uid requis${NC}"
        exit 1
    fi

    echo -e "${GREEN}Quota configure pour $uid:${NC}"
    [ -n "$max_size" ] && echo "  Max size: $max_size"
    [ -n "$max_objects" ] && echo "  Max objects: $max_objects"
}

# Main
case "${1:-help}" in
    user)
        case "$2" in
            create)
                shift 2
                create_user "$@"
                ;;
            list)
                list_users
                ;;
            info)
                shift 2
                user_info "$@"
                ;;
            *)
                echo -e "${RED}Commande user inconnue: $2${NC}"
                ;;
        esac
        ;;
    bucket)
        case "$2" in
            list)
                list_buckets
                ;;
            *)
                echo -e "${RED}Commande bucket inconnue: $2${NC}"
                ;;
        esac
        ;;
    quota)
        shift
        set_quota "$@"
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo -e "${RED}Commande inconnue: $1${NC}"
        show_help
        exit 1
        ;;
esac
