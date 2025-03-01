#!/bin/bash

THRESHOLD=70  # CPU usage percentage to trigger alert
OUTPUT_FILE="/tmp/cpu_usage_monitor.log"

echo "Monitoring CPU usage. Threshold set at ${THRESHOLD}%"

while true; do
    # Get the average CPU usage (user + system)
    CPU_USAGE=$(mpstat 1 5 | awk '/Average:/ {print 100 - $NF}')

    # Round the value to an integer
    CPU_USAGE_INT=${CPU_USAGE%.*}
    # echo "DBUG: ${CPU_USAGE_INT}"

    if (( "${CPU_USAGE_INT}" > "${THRESHOLD}" )); then
        MESSAGE="$(date +'%d/%m/%Y %H:%M:%S') - ALERT: CPU usage is at ${CPU_USAGE_INT}%!"
        echo "${MESSAGE}" | tee -a "${OUTPUT_FILE}"
    fi
done
