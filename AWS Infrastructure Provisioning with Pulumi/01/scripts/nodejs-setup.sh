#!/usr/bin/env bash
exec > >(tee /var/log/nodejs-setup.log) 2>&1

apt install -y netcat-openbsd
apt install npm

curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs

systemctl daemon-reload
systemctl enable mysql-check
systemctl start mysql-check

useradd -r -s /bin/false nodejs
chown nodejs:nodejs /opt/app

cd /opt/app
npm init -y
npm install express mysql2

chown -R nodejs:nodejs /opt/app

systemctl enable nodejs-app
systemctl start nodejs-app