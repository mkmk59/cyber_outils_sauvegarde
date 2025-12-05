#!/bin/bash
set -e

# Configuration des cles SSH autorisees
if [ -f /home/borg/.ssh/authorized_keys ]; then
    chmod 600 /home/borg/.ssh/authorized_keys
    chown borg:borg /home/borg/.ssh/authorized_keys
    echo "[INFO] Cles SSH configurees"
else
    echo "[WARN] Aucune cle SSH trouvee dans /home/borg/.ssh/authorized_keys"
fi

# Verification des permissions sur le repertoire borg
chown -R borg:borg /var/borg

echo "[INFO] Demarrage du serveur SSH..."
exec "$@"
