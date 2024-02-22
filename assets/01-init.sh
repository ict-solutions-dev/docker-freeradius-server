#!/bin/bash
# Executable process script for FreeRadius docker image:
RADIUS_PATH=/etc/raddb

# Convert all environment variables with names ending in __FILE into the content of
# the file that they point at and use the name without the trailing __FILE.
# This can be used to carry in Docker secrets.
for VAR_NAME in $(env | grep '^[^=]\+__FILE=.\+' | sed -r 's/^([^=]*)__FILE=.*/\1/g'); do
	VAR_NAME_FILE="${VAR_NAME}__FILE"
	if [ "${!VAR_NAME}" ]; then
		echo >&2 "ERROR: Both ${VAR_NAME} and ${VAR_NAME_FILE} are set but are exclusive"
		exit 1
	fi
	VAR_FILENAME="${!VAR_NAME_FILE}"
	echo "Getting secret ${VAR_NAME} from ${VAR_FILENAME}"
	if [ ! -r "${VAR_FILENAME}" ]; then
		echo >&2 "ERROR: ${VAR_FILENAME} does not exist or is not readable"
		exit 1
	fi
	export "${VAR_NAME}"="$(<"${VAR_FILENAME}")"
	unset "${VAR_NAME_FILE}"
done

function init_freeradius {
	# Enable SQL in freeradius
	sed -i 's|driver = "rlm_sql_null"|driver = "rlm_sql_mysql"|' $RADIUS_PATH/mods-available/sql
	sed -i 's|dialect = "sqlite"|dialect = "mysql"|' $RADIUS_PATH/mods-available/sql
	sed -i 's|dialect = ${modules.sql.dialect}|dialect = "mysql"|' $RADIUS_PATH/mods-available/sqlcounter # avoid instantiation error
	sed -i 's|ca_file = "/etc/ssl/certs/my_ca.crt"|#ca_file = "/etc/ssl/certs/my_ca.crt"|' $RADIUS_PATH/mods-available/sql #disable sql encryption
	sed -i 's|certificate_file = "/etc/ssl/certs/private/client.crt"|#certificate_file = "/etc/ssl/certs/private/client.crt"|' $RADIUS_PATH/mods-available/sql #disable sql encryption
	sed -i 's|private_key_file = "/etc/ssl/certs/private/client.key"|#private_key_file = "/etc/ssl/certs/private/client.key"|' $RADIUS_PATH/mods-available/sql #disable sql encryption
	sed -i 's|tls_required = yes|tls_required = no|' $RADIUS_PATH/mods-available/sql #disable sql encryption
	sed -i 's|#\s*read_clients = yes|read_clients = yes|' $RADIUS_PATH/mods-available/sql
	ln -s $RADIUS_PATH/mods-available/sql $RADIUS_PATH/mods-enabled/sql
	ln -s $RADIUS_PATH/mods-available/sqlcounter $RADIUS_PATH/mods-enabled/sqlcounter
	ln -s $RADIUS_PATH/mods-available/sqlippool $RADIUS_PATH/mods-enabled/sqlippool
	sed -i 's|instantiate {|instantiate {\nsql|' $RADIUS_PATH/radiusd.conf # mods-enabled does not ensure the right order

    if [ "$EAP_USE_TUNNELED_REPLY" == true ]; then
        # Enable used tunnel for unifi
        sed -i 's|use_tunneled_reply = no|use_tunneled_reply = yes|' $RADIUS_PATH/mods-available/eap
	fi

    if [ "$STATUS_ENABLE" == true ]; then

        # Enable status in freeadius
        ln -s $RADIUS_PATH/sites-available/status $RADIUS_PATH/sites-enabled/status

        # Get IP of the radius container
        IP=`ifconfig $STATUS_INTERFACE | awk '/inet/{ print $2;} '`

        sed -i '0,/ipaddr = 127.0.0.1/s/ipaddr = 127.0.0.1/ipaddr = '$IP'/' $RADIUS_PATH/sites-available/status
        sed -i '0,/admin/s/admin/'$STATUS_CLIENT'/' $RADIUS_PATH/sites-available/status
        sed -i '0,/ipaddr = 127.0.0.1/s/ipaddr = 127.0.0.1/ipaddr = 0.0.0.0/' $RADIUS_PATH/sites-available/status

        # Optional
        if [ -n "$STATUS_SECRET" ]; then
            sed -i 's|adminsecret|'$STATUS_SECRET'|' $RADIUS_PATH/sites-available/status
        fi

        echo "Setting the status page for client $STATUS_CLIENT has been completed."
	fi

	# Set Database connection
	sed -i 's|^#\s*server = .*|server = "'$MYSQL_HOST'"|' $RADIUS_PATH/mods-available/sql
	sed -i 's|^#\s*port = .*|port = "'$MYSQL_PORT'"|' $RADIUS_PATH/mods-available/sql
	sed -i '1,$s/radius_db.*/radius_db="'$MYSQL_DATABASE'"/g' $RADIUS_PATH/mods-available/sql
	sed -i 's|^#\s*password = .*|password = "'$MYSQL_PASSWORD'"|' $RADIUS_PATH/mods-available/sql
	sed -i 's|^#\s*login = .*|login = "'$MYSQL_USER'"|' $RADIUS_PATH/mods-available/sql

    # Optional
	if [ -n "$DEFAULT_CLIENT_SECRET" ]; then
		sed -i 's|testing123|'$DEFAULT_CLIENT_SECRET'|' $RADIUS_PATH/mods-available/sql
	fi

    # Set to true to use radius with Cisco ASR as BRAS for PPPoE sessions.
	if [ "$PPP_VAN_JACOBSON_TCP_IP" == false ]; then
        sed -i '0,/Framed-Protocol = PPP,/! s/Framed-Protocol = PPP,/Framed-Protocol = PPP/' $RADIUS_PATH/mods-config/files/authorize
		sed -i '0,/Framed-Compression = Van-Jacobson-TCP-IP/s/Framed-Compression = Van-Jacobson-TCP-IP/#Framed-Compression = Van-Jacobson-TCP-IP/' $RADIUS_PATH/mods-config/files/authorize

        echo "Default PPP Van Jacobson TCP/IP Header Compression has been disabled."
	fi

	echo "FreeRadius initialization completed."
}

function init_database {
	mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" < $RADIUS_PATH/mods-config/sql/main/mysql/schema.sql
	mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" < $RADIUS_PATH/mods-config/sql/ippool/mysql/schema.sql

	# Insert a client for the current subnet
	IP=`ifconfig eth0 | awk '/inet/{ print $2;} '` # does also work: $IP=`hostname -I | awk '{print $1}'`
	NM=`ifconfig eth0 | awk '/netmask/{ print $4;} '`
	CIDR=`ipcalc $IP $NM | awk '/Network/{ print $2;} '`
	SECRET=testing123
	if [ -n "$DEFAULT_CLIENT_SECRET" ]; then
		SECRET=$DEFAULT_CLIENT_SECRET
	fi
	echo "Adding client for $CIDR with default secret $SECRET"
	mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" -e "INSERT INTO nas (nasname,shortname,type,ports,secret,server,community,description) VALUES ('$CIDR','DOCKER NET','other',0,'$SECRET',NULL,'','')"

	echo "Database initialization for FreeRadius completed."
}

echo "Starting FreeRadius..."

# wait for MySQL-Server to be ready
while ! mysqladmin ping -h"$MYSQL_HOST" --silent; do
	echo "Waiting for mysql ($MYSQL_HOST)..."
	sleep 20
done

INIT_LOCK=/internal_data/.init_done
if test -f "$INIT_LOCK"; then
	echo "Init lock file exists, skipping initial setup."
else
	init_freeradius
	date > $INIT_LOCK
fi

if [ "$MYSQL_INIT" == true ]; then
    MYSQL_LOCK=/data/.MYSQL_init_done
    if test -f "$MYSQL_LOCK"; then
        echo "Database lock file exists, skipping initial setup of mysql database."
    else
        init_database
        date > $MYSQL_LOCK
    fi
else
    echo "Database exists, skipping initial setup of mysql database."
fi

# this if will check if the first argument is a flag
# but only works if all arguments require a hyphenated flag
# -v; -SL; -f arg; etc will work, but not arg1 arg2
if [ "$#" -eq 0 ] || [ "${1#-}" != "$1" ]; then
    set -- freeradius "$@"
fi

# check for the expected command
if [ "$1" = 'freeradius' ]; then
    shift
    exec freeradius -f "$@"
fi

# many people are likely to call "radiusd" as well, so allow that
if [ "$1" = 'radiusd' ]; then
    shift
    exec freeradius -f "$@"
fi

# else default to run whatever the user wanted like "bash" or "sh"
exec "$@"
