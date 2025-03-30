# AWS Log Rotation and System Monitoring Setup
This document outlines the steps to set up automated log rotation and system monitoring using AWS S3, cron jobs, and systemd services.

## Prerequisites
* An AWS account with configured credentials.
* A Linux-based system with `apt` package manager.

## Installation and Configuration
1.  **Install AWS CLI:**

    ```bash
    sudo apt install awscli
    ```

2.  **Configure AWS Credentials:**

    ```bash
    aws configure
    ```

    Follow the prompts to enter your AWS Access Key ID, Secret Access Key, default region, and output format.

## Script Creation
1.  **Create Log Rotation Script (`log_rotate.sh`):**

    ```bash
    vim /usr/local/bin/log_rotate.sh
    ```

    Paste the `log_rotate.sh` file content. This script compress the logs into one file and upload to S3 bucket.

    Make the script executable:

    ```bash
    sudo chmod +x /usr/local/bin/log_rotate.sh
    ```

2.  **Create Authentication Monitor Script (`monitor_auth.sh`):**

    ```bash
    vim /usr/local/bin/monitor_auth.sh
    ```

	 Paste the `monitor_auth.sh` file content. This script continuously monitors failed SSH login attempt.

    Make the script executable:

    ```bash
    sudo chmod +x /usr/local/bin/monitor_auth.sh
    ```

3.  **Create CPU Usage Monitor Script (`monitor_cpu_usage.sh`):**

    ```bash
    vim /usr/local/bin/monitor_cpu_usage.sh
    ```

	 Paste the `monitor_cpu_usage.sh` file content. This script continuously monitors if CPU usages exceeds a certain threshold.

    Make the script executable:

    ```bash
    sudo chmod +x /usr/local/bin/monitor_cpu_usage.sh
    ```

## Systemd Service Configuration
1.  **Create Authentication Monitor Service (`auth_monitor.service`):**

    ```bash
    sudo vim /etc/systemd/system/auth_monitor.service
    ```

    Add the `auth_monitor.service` service configuration. Make sure to change user and group name with your own.

2.  **Create CPU Usage Monitor Service (`cpu_usage_monitor.service`):**

    ```bash
    sudo vim /etc/systemd/system/cpu_usage_monitor.service
    ```

    Add the `cpu_usage_monitor.service` service configuration. Make sure to change user and group name with your own.
## AWS S3 Bucket Creation
1.  **Create an S3 Bucket:**

    ```bash
    aws s3 mb s3://log-archive
    ```

    Replace `log-archive` with your desired bucket name. Make sure your bucket name is unique.
## Cron Job Configuration
1.  **Configure Log Rotation Cron Job:**

    ```bash
    crontab -l 2>/dev/null; echo "0 0 * * * /usr/local/bin/log_rotate.sh >> /var/log/cron.log 2>&1" | crontab -
    ```

    This command adds a cron job that runs the `log_rotate.sh` script daily at midnight.

2.  **List Active Cron Jobs:**

    ```bash
    crontab -l
    ```
## Systemd Service Management
1.  **Reload Systemd Daemon:**

    ```bash
    sudo systemctl daemon-reload
    ```

2.  **Enable and Start Services:**

    ```bash
    sudo systemctl enable auth_monitor.service
    sudo systemctl enable cpu_usage_monitor.service
    sudo systemctl start auth_monitor.service
    sudo systemctl start cpu_usage_monitor.service
    ```

## Service Monitoring
1.  **View Authentication Monitor Logs:**

    ```bash
    journalctl -u auth_monitor.service --no-pager --since "5 minutes ago"
    ```

2.  **View CPU Usage Monitor Logs:**

    ```bash
    journalctl -u cpu_usage_monitor.service --no-pager --since "5 minutes ago"
    ```