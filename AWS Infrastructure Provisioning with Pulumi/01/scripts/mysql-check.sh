#!/usr/bin/env bash
: '
This script establishes a TCP connection to a database.

It attempts to connect, retrying for a maximum duration defined by the 'RETRY_INTERVAL' variable.

Exit Codes:
  0: Successful connection established.
  1: Connection failed after all retries.

Retry Logic:
  The script repeatedly attempts to connect until either a successful connection is made or the 'RETRY_INTERVAL' is exceeded.
'

DB_HOST="${DB_PRIVATE_IP}"
DB_PORT=3306
MAX_RETRIES=30
RETRY_INTERVAL=10

function check_mysql() {
    nc -z -w 5 "${DB_HOST}" "${DB_PORT}"
    return $?
}

retry_count=0
for retry_count in $(seq ${MAX_RETRIES}); do
    if check_mysql; then
        echo "Successfully connected to MySQL at ${DB_HOST}:${DB_PORT}"
        exit 0
    fi

    echo "Attempt ${retry_count}/${MAX_RETRIES}: Cannot connect to MySQL at ${DB_HOST}:${DB_PORT}. Retrying in ${RETRY_INTERVAL} seconds..."
    sleep ${RETRY_INTERVAL}
done

echo "Failed to connect to MySQL after ${MAX_RETRIES} attempts"
exit 1