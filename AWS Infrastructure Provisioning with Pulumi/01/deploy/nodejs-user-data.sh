#!/usr/bin/env bash
exec > >(tee /var/log/user-data.log) 2>&1

apt update
apt upgrade -y
apt install -y netcat-openbsd

curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
apt install -y nodejs

mkdir -p /usr/local/bin

echo "DB_PRIVATE_IP={db_private_ip}" >> /etc/environment

cat > /usr/local/bin/check-mysql.sh << 'EOF'
{mysql_check_script}
EOF

chmod +x /usr/local/bin/check-mysql.sh