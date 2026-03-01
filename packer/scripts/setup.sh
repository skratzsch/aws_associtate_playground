#!/bin/bash
set -euo pipefail

# Force IPv6 for apt (consistent with the rest of the project)
echo 'Acquire::ForceIPv6 "true";' > /etc/apt/apt.conf.d/99force-ipv6

apt-get update
apt-get install -y nginx git acl curl

# Install Node.js LTS via NodeSource
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
apt-get install -y nodejs

# Create app directory owned by ubuntu
mkdir -p /opt/on-the-run-web
chown ubuntu:ubuntu /opt/on-the-run-web

# Clone, install dependencies, and build as ubuntu user
sudo -u ubuntu bash -c "
  git clone https://github.com/skratzsch/on-the-run-web.git /opt/on-the-run-web
  cd /opt/on-the-run-web
  npm ci
  npm run build
"

# systemd service for NextJS
cat > /etc/systemd/system/nextjs.service << 'EOF'
[Unit]
Description=NextJS on-the-run-web
After=network.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/on-the-run-web
ExecStart=/usr/bin/npm start
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
Environment=NODE_ENV=production
Environment=PORT=3000

[Install]
WantedBy=multi-user.target
EOF

# NGINX reverse proxy config
rm -f /etc/nginx/sites-enabled/default

cat > /etc/nginx/sites-available/nextjs << 'EOF'
server {
    listen 80;
    listen [::]:80;
    server_name _;

    location / {
        proxy_pass         http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade $http_upgrade;
        proxy_set_header   Connection 'upgrade';
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_cache_bypass $http_upgrade;
    }
}
EOF

ln -sf /etc/nginx/sites-available/nextjs /etc/nginx/sites-enabled/nextjs

# Enable services — they start automatically on first boot
systemctl daemon-reload
systemctl enable nginx
systemctl enable nextjs
