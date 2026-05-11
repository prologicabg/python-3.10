# Official AXS Python 3.10 docker image

#### How to use this image

This docker image contains Python 3.10.11. Python script can be run when you edit this file **/sbin/start-python.sh** and change **start_python=/path/to/file/here** with path to where your python script is located.

**Example:** If you python script is located in /data/python_app/app.py then /sbin/start-python.sh it should look like this:
```
#!/bin/bash
start_python=/data/python_app/app.py
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
```
You can also change the count number to lower or higher so if you want, for example, the docker container to be terminated when the python script is exited for some reason more than 10 times /sbin/start-python.sh - it should look like this:

```
#!/bin/bash
start_python=/data/python_app/app.py
count=0

while [[ "$count" -lt 10 ]]
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
```
#### Logs
Logs from the script are writen in /var/log/axsmarine-general.log
