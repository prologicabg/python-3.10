#!/bin/bash

# AXS_ENV variable is passed by supervisord.
# Look at its config for more info.
if [ -n "${AXS_ENV}" ]; then
  /sbin/axsmarine/${AXS_ENV}.sh >/var/log/axs_env.log 2>&1
  supervisorctl start axs-env-log
fi
rm -Rf /sbin/axsmarine
supervisorctl start graylog-sidecar
supervisorctl start axsmarine-general-log
supervisorctl start axsmarine-audit-log
supervisorctl start supervisord-main-log
supervisorctl start start-python
