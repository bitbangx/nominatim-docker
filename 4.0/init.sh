#!/bin/bash -ex

# if we use a bind mount then the PG directory is empty and we have to create it
if [ ! -f /var/lib/postgresql/12/main/PG_VERSION ]; then
  chown postgres /var/lib/postgresql/12/main
  sudo -u postgres /usr/lib/postgresql/12/bin/initdb -D /var/lib/postgresql/12/main
fi

sudo service postgresql start && \
sudo -E -u postgres psql postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='nominatim'" | grep -q 1 || sudo -E -u postgres createuser -s nominatim && \
sudo -E -u postgres psql postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='www-data'" | grep -q 1 || sudo -E -u postgres createuser -SDR www-data && \

sudo -E -u postgres psql postgres -tAc "ALTER USER nominatim WITH ENCRYPTED PASSWORD '$NOMINATIM_PASSWORD'" && \
sudo -E -u postgres psql postgres -tAc "ALTER USER \"www-data\" WITH ENCRYPTED PASSWORD '${NOMINATIM_PASSWORD}'" && \

sudo -E -u postgres psql postgres -c "DROP DATABASE IF EXISTS nominatim"
sudo -E -u postgres psql postgres -c "CREATE DATABASE nominatim"

chown -R nominatim:nominatim ${PROJECT_DIR}

cd ${PROJECT_DIR}

tar -xzvf /tmp/nominatim.tar.gz
mv aso /tmp/nominatim.sql

sudo -E -u postgres PGPASSWORD=${NOMINATIM_PASSWORD} psql -U nominatim -h 127.0.0.1 < /tmp/nominatim.sql
sudo -E -u postgres PGPASSWORD=${NOMINATIM_PASSWORD} psql -U nominatim -h 127.0.0.1 < /tmp/init.sql

rm /tmp/nominatim.sql
rm /tmp/init.sql

mkdir ${PROJECT_DIR}/tokenizer
cp /tmp/tokenizer.php ${PROJECT_DIR}/tokenizer/tokenizer.php

sudo -E -u nominatim nominatim admin --check-database

# gather statistics for query planner to potentially improve query performance
# see, https://github.com/osm-search/Nominatim/issues/1023
# and  https://github.com/osm-search/Nominatim/issues/1139
sudo -E -u nominatim psql -d nominatim -c "ANALYZE VERBOSE"

sudo service postgresql stop

# Remove slightly unsafe postgres config overrides that made the import faster
rm /etc/postgresql/12/main/conf.d/postgres-import.conf


# nominatim needs the tokenizer configuration in the project directory to start up
# but when you start the container with an already imported DB then you don't have this config.
# that's why we save it in /var/lib/postgresql and copy it back if we need it.
# this is of course a terrible hack but there is hope that 4.1 provides a way to restore this
# configuration cleanly.
# More reading: https://github.com/mediagis/nominatim-docker/pull/274/
cp -r ${PROJECT_DIR}/tokenizer /var/lib/postgresql/12/main
