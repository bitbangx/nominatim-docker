#!/bin/bash -ex

# if we use a bind mount then the PG directory is empty and we have to create it
if [ ! -f /var/lib/postgresql/14/main/PG_VERSION ]; then
  chown postgres /var/lib/postgresql/14/main
  sudo -u postgres /usr/lib/postgresql/14/bin/initdb -D /var/lib/postgresql/14/main
fi

# temporarily enable unsafe import optimization config
cp /etc/postgresql/14/main/conf.d/postgres-import.conf.disabled /etc/postgresql/14/main/conf.d/postgres-import.conf

sudo service postgresql start && \
sudo -E -u postgres psql postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='nominatim'" | grep -q 1 || sudo -E -u postgres createuser -s nominatim && \
sudo -E -u postgres psql postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='www-data'" | grep -q 1 || sudo -E -u postgres createuser -SDR www-data && \

sudo -E -u postgres psql postgres -tAc "ALTER USER nominatim WITH ENCRYPTED PASSWORD '$NOMINATIM_PASSWORD'" && \
sudo -E -u postgres psql postgres -tAc "ALTER USER \"www-data\" WITH ENCRYPTED PASSWORD '${NOMINATIM_PASSWORD}'" && \

sudo -E -u postgres psql postgres -c "DROP DATABASE IF EXISTS nominatim"

chown -R nominatim:nominatim ${PROJECT_DIR}

cd ${PROJECT_DIR}

sudo -E -u postgres pg_restore -c -U nominatim -d nominatim -v "/tmp/nominatim.tar.gz" -W --no-password

# Sometimes Nominatim marks parent places to be indexed during the initial
# import which leads to '123 entries are not yet indexed' errors in --check-database
# Thus another quick additional index here for the remaining places
sudo -E -u nominatim nominatim index --threads $THREADS

sudo -E -u nominatim nominatim admin --check-database

sudo -E -u nominatim nominatim admin --warm

# gather statistics for query planner to potentially improve query performance
# see, https://github.com/osm-search/Nominatim/issues/1023
# and  https://github.com/osm-search/Nominatim/issues/1139
sudo -E -u nominatim psql -d nominatim -c "ANALYZE VERBOSE"

sudo service postgresql stop

# Remove slightly unsafe postgres config overrides that made the import faster
rm /etc/postgresql/14/main/conf.d/postgres-import.conf
