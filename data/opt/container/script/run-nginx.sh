#!/bin/bash

function createServerConf () {
     local headers_clear=""
     local server_config=/etc/nginx/host/servers/${1}.conf

     cp /opt/container/template/server.conf.template /etc/nginx/host/servers/${1}.conf
     fileSubstitute ${server_config} NGINX_PROXY_READ_TIMEOUT ${NGINX_PROXY_READ_TIMEOUT}
     fileSubstitute ${server_config} NGINX_RESOLVER ${NGINX_RESOLVER}
     fileSubstitute ${server_config} nginx_hosts ${1}
     fileSubstitute ${server_config} nginx_units `echo ${1} | sed "s/,/ /g"`

     if [ -f /etc/ssl/dhparam.pem ]
     then
          sed -i "s/#ssl_dhparam/ssl_dhparam/g" ${server_config}
     fi

     # For NGINX_HEADERS_REMOVE, strip whitespace and split on commas.  Then massage the values a bit to fit the format
     # of more_clear_headers.

     for header in `echo ${NGINX_HEADERS_REMOVE} | xargs | tr "," "\n"`
     do
          headers_clear="${headers_clear} '"`echo ${header} | xargs`"'"
     done

     if [ ! -z "${headers_clear}" ]
     then
          sed -i "s/\${headers_clear}/${headers_clear}/g" ${server_config}
          sed -i "s/#more_clear_headers/more_clear_headers/g" ${server_config}
     fi

     # Include any extra configuration for the virtual host if available.

     if [ -f /etc/nginx/extra/${1}.extra.conf ]
     then
          cp /etc/nginx/extra/${1}.extra.conf ${server_config}.extra

          sed -i "s/#include/include/g" ${server_config}
     fi
}

function fileSubstitute () {
     sed -i "s/\${"${2}"}/"${3}"/g" ${1}
}

function nginxConfSubstitute () {
     fileSubstitute /etc/nginx/nginx.conf ${1} ${2}
}

function numUnitsLaunched () {
     local launchedDir=/etc/nginx/host/units/__launched__

     if [ ! -d ${launchedDir} ]
     then
          mkdir -p ${launchedDir}
     fi

     ls ${launchedDir} | wc -w
}

function numUnitsStarted () {
     local startedDir=/etc/nginx/host/units/__started__

     if [ ! -d ${startedDir} ]
     then
          mkdir -p ${startedDir}
     fi

     ls ${startedDir} | wc -w
}

# Insert a brief pause to give us time for all the units to launch.

echo "[info] waiting ${NGINX_UNIT_WAIT} second(s) for units to launch"
sleep ${NGINX_UNIT_WAIT}

mkdir -p /etc/nginx/host/servers
mkdir -p /var/www/letsencrypt-well-known

# Fix /etc/nginx/nginx.conf.

cp /opt/container/template/nginx.conf.template /etc/nginx/nginx.conf
nginxConfSubstitute NGINX_GZIP ${NGINX_GZIP}
nginxConfSubstitute NGINX_KEEPALIVE_TIMEOUT ${NGINX_KEEPALIVE_TIMEOUT}
nginxConfSubstitute NGINX_TYPES_HASH_MAX_SIZE ${NGINX_TYPES_HASH_MAX_SIZE}
nginxConfSubstitute NGINX_WORKER_PROCESSES ${NGINX_WORKER_PROCESSES}
nginxConfSubstitute NGINX_WORKER_CONNECTIONS ${NGINX_WORKER_CONNECTIONS}

# Wait for units to start (i.e., to have their unit configuration files available).

while [ `numUnitsStarted` -lt `numUnitsLaunched` ]
do
     sleep 0.2

     echo "[info] waiting for unit(s) to start"
done

echo "[info] started "`numUnitsStarted`" unit(s)"

rm -rf /etc/nginx/host/units/__launched__
rm -rf /etc/nginx/host/units/__started__

# Create a server configuration for each unit.

for unit in `ls /etc/nginx/host/units 2> /dev/null`
do
     createServerConf ${unit}
done

# Start cron for automated certificate renewal.

crond

/usr/share/nginx/sbin/nginx -g "daemon off;"
