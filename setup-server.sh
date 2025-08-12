#!/bin/bash
# setup-server.sh - Configuration initiale du serveur VPS

echo "🚀 Configuration du serveur Pixel War HUB du RP"
echo "============================================="

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 1. Mise à jour du système
log_info "Mise à jour du système..."
apt update && apt upgrade -y
log_success "Système mis à jour"

# 2. Installation des paquets essentiels
log_info "Installation des paquets essentiels..."
apt install -y curl wget git nano htop unzip ufw fail2ban nginx certbot python3-certbot-nginx

# 3. Installation de Node.js 18+
log_info "Installation de Node.js..."
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
apt install -y nodejs
node_version=$(node --version)
log_success "Node.js installé: $node_version"

# 4. Installation de PostgreSQL
log_info "Installation de PostgreSQL..."
apt install -y postgresql postgresql-contrib
systemctl start postgresql
systemctl enable postgresql
log_success "PostgreSQL installé et démarré"

# 5. Installation de Redis
log_info "Installation de Redis..."
apt install -y redis-server
systemctl start redis-server
systemctl enable redis-server
log_success "Redis installé et démarré"

# 6. Installation de PM2 (gestionnaire de processus Node.js)
log_info "Installation de PM2..."
npm install -g pm2
log_success "PM2 installé"

# 7. Configuration du firewall
log_info "Configuration du firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
log_success "Firewall configuré"

# 8. Configuration de Fail2Ban
log_info "Configuration de Fail2Ban..."
cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
backend = %(sshd_backend)s

[nginx-http-auth]
enabled = true

[nginx-noscript]
enabled = true

[nginx-badbots]
enabled = true

[nginx-noproxy]
enabled = true
EOF

systemctl restart fail2ban
log_success "Fail2Ban configuré"

# 9. Création d'un utilisateur non-root
log_info "Création de l'utilisateur 'pixelwar'..."
adduser --disabled-password --gecos "" pixelwar
usermod -aG sudo pixelwar
log_success "Utilisateur 'pixelwar' créé"

# 10. Configuration des clés SSH (optionnel mais recommandé)
log_info "Configuration des dossiers SSH..."
mkdir -p /home/pixelwar/.ssh
chmod 700 /home/pixelwar/.ssh
chown pixelwar:pixelwar /home/pixelwar/.ssh

# 11. Configuration PostgreSQL
log_info "Configuration de PostgreSQL..."
sudo -u postgres psql << EOF
CREATE DATABASE pixelwar_db;
CREATE USER pixelwar_user WITH PASSWORD 'MotDePasseSecurise123';
GRANT ALL PRIVILEGES ON DATABASE pixelwar_db TO pixelwar_user;
\q
EOF
log_success "Base de données PostgreSQL configurée"

# 12. Optimisation système
log_info "Optimisation du système..."

# Augmenter les limites de fichiers ouverts
echo "* soft nofile 65536" >> /etc/security/limits.conf
echo "* hard nofile 65536" >> /etc/security/limits.conf

# Optimisation réseau
cat >> /etc/sysctl.conf << EOF

# Optimisations réseau pour Node.js
net.core.somaxconn = 65536
net.ipv4.tcp_max_syn_backlog = 65536
net.core.netdev_max_backlog = 5000
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 120
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl = 10
EOF

sysctl -p
log_success "Système optimisé"

# 13. Configuration Nginx de base
log_info "Configuration de Nginx..."
cat > /etc/nginx/sites-available/default << 'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    
    root /var/www/html;
    index index.html index.htm index.nginx-debian.html;
    
    server_name _;
    
    location / {
        try_files $uri $uri/ =404;
    }
}
EOF

nginx -t && systemctl restart nginx
log_success "Nginx configuré"

# 14. Création des dossiers de travail
log_info "Création des dossiers de travail..."
mkdir -p /home/pixelwar/app
mkdir -p /home/pixelwar/backups
mkdir -p /home/pixelwar/logs
chown -R pixelwar:pixelwar /home/pixelwar/
log_success "Dossiers créés"

# 15. Installation des outils de monitoring
log_info "Installation des outils de monitoring..."
apt install -y htop iotop nethogs ncdu
log_success "Outils de monitoring installés"

# 16. Configuration des sauvegardes automatiques
log_info "Configuration des sauvegardes..."
cat > /home/pixelwar/backup.sh << 'EOF'
#!/bin/bash
# Script de sauvegarde automatique

BACKUP_DIR="/home/pixelwar/backups"
DATE=$(date +%Y%m%d_%H%M%S)

# Sauvegarde de la base de données
pg_dump -h localhost -U pixelwar_user pixelwar_db > "$BACKUP_DIR/db_backup_$DATE.sql"

# Sauvegarde des fichiers application
tar -czf "$BACKUP_DIR/app_backup_$DATE.tar.gz" /home/pixelwar/app/

# Nettoyage des anciennes sauvegardes (garder 7 jours)
find "$BACKUP_DIR" -name "*.sql" -mtime +7 -delete
find "$BACKUP_DIR" -name "*.tar.gz" -mtime +7 -delete

echo "Sauvegarde terminée: $DATE"
EOF

chmod +x /home/pixelwar/backup.sh
chown pixelwar:pixelwar /home/pixelwar/backup.sh

# Ajouter au cron pour sauvegarde quotidienne à 3h du matin
(crontab -l -u pixelwar 2>/dev/null; echo "0 3 * * * /home/pixelwar/backup.sh") | crontab -u pixelwar -
log_success "Sauvegardes automatiques configurées"

# 17. Configuration des logs
log_info "Configuration des logs..."
mkdir -p /var/log/pixelwar
chown pixelwar:pixelwar /var/log/pixelwar

# Rotation des logs
cat > /etc/logrotate.d/pixelwar << EOF
/var/log/pixelwar/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    copytruncate
    su pixelwar pixelwar
}
EOF

log_success "Logs configurés"

# 18. Informations finales
echo ""
echo "============================================="
log_success "Configuration du serveur terminée !"
echo "============================================="
echo ""
echo "📋 Informations importantes :"
echo "• Utilisateur créé : pixelwar"
echo "• Base de données : pixelwar_db"
echo "• Utilisateur DB : pixelwar_user"
echo "• Dossier app : /home/pixelwar/app"
echo "• Logs : /var/log/pixelwar"
echo "• Sauvegardes : /home/pixelwar/backups"
echo ""
echo "🔐 Prochaines étapes :"
echo "1. Configurer les clés SSH"
echo "2. Changer les mots de passe par défaut"
echo "3. Acheter et configurer le nom de domaine"
echo "4. Déployer l'application Pixel War"
echo ""
echo "🚀 Votre serveur est prêt pour le déploiement !"