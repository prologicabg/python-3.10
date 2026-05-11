#!/bin/bash
start_python=/path/to/file/here
count=0

while [[ "$count" -lt 20 ]]
do
  count=$((count+1))
  echo "Starting application..."
  gosu axsmarine python "$start_python"
done

if [ -f "$start_python" ]; then
  echo "Application is exited more than $count times. The container is terminated!"
  /usr/bin/supervisorctl shutdown
else
  sleep 2
  exit 1
fi
