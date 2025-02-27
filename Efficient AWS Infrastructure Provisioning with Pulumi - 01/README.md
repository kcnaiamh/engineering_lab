Efficient AWS Infrastructure Provisioning with Pulumi: Deploying Node.js Application with systemd Service Chaining and MySQL Health Check
---
Lets spin up a fresh Linux VM and run the following command to make the environment ready.

```
sudo apt update
```

```
sudo apt install unzip
sudo apt install python3.12-venv
```

---
Now install AWS CLI: ([source](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html))

```
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" 2>/dev/null
unzip awscliv2.zip
sudo ./aws/install
```

Configure AWS CLI by running the following command and giving appropriate credentials.
```
aws configure
```

> [!Todo]
> Log into your AWS account and get the access key. Then export it.

---

Now install Pulumi: ([source](https://www.pulumi.com/docs/iac/download-install/))

```
curl -fsSL https://get.pulumi.com | sh
```

Export pulumi path
```
export PATH=$PATH:/home/naim/.pulumi/bin
```

Authenticate your pulumi account with temporary token
```
pulumi login
```

```
mkdir -p ~/kc-service-infra
cd ~/kc-service-infra
```

Create a new pulumi project
```
pulumi new
```

Now select `aws-python` template

---

Create an AWS Key Pair

```shell
cd ~/.ssh/
aws ec2 create-key-pair --key-name db-cluster --output text --query 'KeyMaterial' > db-cluster.id_rsa
chmod 400 db-cluster.id_rsa
```

This will save the private key as `db-cluster.id_rsa` in the `~/.ssh/` directory and restrict its permissions.

---

Write your infrastructure provisioning code in `__main__.py` file. The code is in `pulumi_aws_nodejs_db.py` file.



As we have used request module, we need to install it.

```
pip install requests
```

```
pip freeze > requirements.txt
```


Now privision the infrastructure
```
pulumi up --yes
```

---
As we have already created the config file, we can SSH into the DB server through the Node.js server:

```
ssh db-server
```

Change the hostname of the DB server to `db-server` to make it easier to identify.

```
sudo hostnamectl set-hostname db-server
```

```
sudo apt update
sudo apt install mysql-server
```

Configure MySQL to allow remote connections

```
sudo vim /etc/mysql/mysql.conf.d/mysqld.cnf
```

Find the line `bind-address = 127.0.0.1` and change it to:

```
bind-address = 0.0.0.0
```

```
sudo mysql
```

We need to create a database and user for the application.

```sql
CREATE DATABASE app_db;
CREATE USER 'app_user'@'%' IDENTIFIED BY 'your_secure_password';
GRANT ALL PRIVILEGES ON app_db.* TO 'app_user'@'%';
FLUSH PRIVILEGES;
exit;
```

```
sudo systemctl restart mysql
sudo systemctl status mysql
```

---
```
ssh nodejs-server
```

We need to create a directory for the application and set up a no shell user for the application.

```
sudo mkdir -p /opt/app
sudo useradd -r -s /bin/false nodejs
sudo chown nodejs:nodejs /opt/app
```

We need to create the Node.js application.

```
cd /opt/app
sudo wget https://raw.githubusercontent.com/kcnaiamh/devops_homelab/refs/heads/dev/kc-poc-pulumi/src/app.js -O server.js
sudo vim server.js
```

Replace `<PRIVATE IP OF DB SERVER>` with your DB server's private IP and `your_secure_password` with the password you created in the previous step.

We need to initialize npm and install the dependencies.

```
sudo apt install npm
cd /opt/app
sudo npm init -y
sudo npm install express mysql2
```

Make sure to change the owner of the directory to the nodejs user.

```
sudo chown -R nodejs:nodejs /opt/app
```

---

Create a systemd service for the MySQL check script

```
sudo wget https://raw.githubusercontent.com/kcnaiamh/devops_homelab/refs/heads/dev/kc-poc-pulumi/deploy/mysql-check.service -O /etc/systemd/system/mysql-check.service
```

We need to reload and restart the systemd services. First reload the daemon and then stop and start the services.

```
sudo systemctl daemon-reload
sudo systemctl start mysql-check
```

Let's see the logs

```
sudo journalctl -u mysql-check -f
```

We can see that the MySQL check script is running and the MySQL is up and running.

---

We need to create a systemd service for the Node.js application.

```
sudo  wget https://raw.githubusercontent.com/kcnaiamh/devops_homelab/refs/heads/dev/kc-poc-pulumi/deploy/nodejs-app.service -O /etc/systemd/system/nodejs-app.service
```

Now, let's start the Node.js application:

```
sudo systemctl start nodejs-app
sudo systemctl enable nodejs-app
sudo systemctl status nodejs-app
```

We can see that the Node.js application is running on port 3000. We can access it using the public IP of the Node.js server.

```
curl http://<PUBLIC IP>:3000
```


---
Destroy all resources
```
pulumi destroy --yes
```

Delete stack
```
pulumi stack rm
```
