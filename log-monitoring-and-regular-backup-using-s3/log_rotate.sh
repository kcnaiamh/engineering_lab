#!/usr/bin/env bash

LOGS=("auth_monitor" "cpu_usage_monitor")
ARCHIVE_DIR="/tmp/logs_archive"
BUCKET="s3://kc-log-archive" # your bucket name

mkdir -p "${ARCHIVE_DIR}"

for log in "${LOGS[@]}"; do
    if [[ -f "/tmp/${log}.log" ]]; then
        mv "/tmp/${log}.log" "${ARCHIVE_DIR}/${log}_$(date +%F-%H%M%S).log"
        touch "${log}.log"
    fi
done

echo "Logs rotated and archived in ${ARCHIVE_DIR}"

archive_file="archive-$(date +%F-%H%M%S).tar.gz"

cd /tmp

tar -czf ${archive_file} -C ${ARCHIVE_DIR} .

aws s3 cp ${archive_file} ${BUCKET}

rm -f "${ARCHIVE_DIR}"/*.log
rm -f ${archive_file}
