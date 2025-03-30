#!/usr/bin/env bash

LOG_FILE="/var/log/auth.log"
OUTPUT_FILE="/tmp/auth_monitor.log"

echo "Monitoring ${LOG_FILE} for failed login attempts..."

tail -F "${LOG_FILE}" | while read line; do
    if echo "${line}" | grep -qE "Failed password.*ssh"; then
        echo "$(date +'%d/%m/%Y %H:%M:%S') - ALERT: Failed SSH login attempt detected! - $(echo ${line} | cut -d ' ' -f9,11)" | tee -a "${OUTPUT_FILE}"
    fi
done