#!/bin/bash
#--------------------------------------------------------------
# PURPOSE: Refresh PostgreSQL Database from Oracle PDR
# AUTHOR : JSchroeter
# DATE   : 04/13/2020
#
# NOTES  : 1.1 - 04/23/2020 Bug Fixes, Add Variables, Config File
#        : 1.2 - 04/27/2020 Update Config File, Clean bugs/dups
#        : 1.3 - 05/03/2020 Add portal.refresh_tables and cleanup
#        : 1.4 - 05/07/2020 Modify script to create "stage" schema in x_portal DB and alter stage schama
#        : 1.5 - 05/08/2020 Two schema design did not work. Modications for two database design.
#
# STEPS  : - Make sure config file exist
#        : - Build stage schema if does not exist
#
# ISSUES : Needs monitoring and Checks
#        : Fix Exits - not terminating script line 150
#
#--------------------------------------------------------------
VERSION="1.5"

#--------------------------------------------------------------
# Variables
#--------------------------------------------------------------
STATUS="SUCCESSFUL"
BASENAME=`basename $0`
DIR=/db01/Jobs/Portal_Sync
LOGDIR="/db01/Logs/Portal_Sync"
LOGFILE="$LOGDIR/`basename $0 sh`log"
LOGFILE_SQL="$LOGDIR/`basename $0 sh`sql"
DATE="date +%F-%T"
LINE="==========================================================================="
MAXLOGSIZE="5000000" # 5MB
HOST=`uname -n | awk -F"." '{print $1}'`
NEW=N

# Environment: Bind to server to make sure not runninng on wrong machine
CONFIG_DIR="$DIR/Config"

# Maximum create table parallel
MAXTABLES=3

# Maximum create indexes parallel
MAXINDEXES=3

# Maximum create references parallel
MAXREFERENCES=3

# Table Defaults
TABLES_FOUND=0
VIEWS_FOUND=0
ZERO_FOUND=0

REPO_HOST="den-mon-1.ci.neoninternal.org"
REPO_DB="postgres"

# psql binary location
PSQL="/usr/pgsql-12/bin/psql"
MYSQL="/usr/bin/mysql"
CREATEDB="/usr/pgsql-12/bin/createdb"

#--------------------------------------------------------------
# Functions
#--------------------------------------------------------------

#==============================================================
# Function LOGD() - Log output to logfile with date prepended
#==============================================================
LOGD() {
	#echo -e "`$DATE`  $*" | tee -a $LOGFILE
	echo -e "`$DATE`  $*" >> $LOGFILE
}


#==============================================================
# Function LOG() - Log output to logfile
#==============================================================
LOG() {
	#echo -e "$*" | tee -a $LOGFILE
	echo -e "$*" >> $LOGFILE
}


#==============================================================
# Function USAGE() - Print usage message
#==============================================================
USAGE() {
	echo "
	USAGE: $BASENAME -d  | -i  | -c | -p | -n | -h | -v

		-d      Development
		-i      Intgration
		-c      Certification
		-p      Production
		-n      NEW (if portal_admin user does not exist)
		-h      Print usage
		-v      Version

	"
	exit 999
}


#==============================================================
# Function CLEAN_LOG() - Cleanup Logfile
#==============================================================
CLEAN_LOG() {
   LOGSIZE=`/bin/ls -l $LOGFILE | /bin/awk '{print $5}'`
   if [ "$LOGSIZE" -gt "$MAXLOGSIZE" ];then
      LOGD "Current logfile size $LOGSIZE, exceeded $MAXLOGSIZE, trim logfile."
      tail -c${MAXLOGSIZE} $LOGFILE > ${LOGFILE}.tmp
      mv ${LOGFILE}.tmp $LOGFILE
      LOGSIZE=`/bin/ls al $LOGFILE | /bin/awk '{print $5}'`
      LOGD "`$DATE` - New logfile size $LOGSIZE"
   fi
}


#==============================================================
# Function CHK_LOGDIR() - Make sure LOGDIR Exist, if not create
#==============================================================
CHK_LOGDIR() {

	LOGD "Starting CHK_LOGDIR()"
	if [ -d "$LOGDIR" ];then
		LOGD "LOGDIR Exist, Continue ..."
	else
		RC=96
		STATUS=FAILED
		MSG="ERROR: $STAGE_DB EXIST. EXIT. STATUS = $STATUS, RC=$RC"
		LOGD "$MSG"
		EMAIL
		exit $RC
	fi
	LOGD "Completed CHK_LOGDIR()"
}


#==============================================================
# Function READ_CONFIG() - Read Configuration - set variables
#==============================================================
READ_CONFIG() {

	# Raed Config file based on Parameter passed in getopts.
	# If CONFIG_FILE not found application will exit.

	# Passwed Configuration
	ENVIR=$1
	FILE=$2

	# Temp, need config solution	
	CONFIG_FILE="$CONFIG_DIR/$FILE"

	LOGD "Starting READ_CONFIG()"
	if [ -f "$CONFIG_FILE" ];then
		LOGD "$CONFIG_FILE Exist, Continue ..."

		# Get PDR Database: PDR_DB
		PDR_DB=`awk '/^pdr_database/{print $3}' $CONFIG_FILE`
		LOG "PDR Database = $PDR_DB"

		# Get PDR User: PDR_USER
		PDR_USER=`awk '/^pdr_user/{print $3}' $CONFIG_FILE`
		LOG "PDR user = $PDR_USER"

		# Get PDR Pass: PDR_PASS
		PDR_PASS=`awk '/^pdr_pass/{print $3}' $CONFIG_FILE`
		LOG "PDR pass = *********"

		# Get PORTAL Database: PORTAL_DB
		PORTAL_DB=`awk '/^portal_db/{print $3}' $CONFIG_FILE`
		LOG "Portal Database = $PORTAL_DB"

		# Get PORTAL Admin User: PORTAL_ADMIN
		PORTAL_ADMIN=`awk '/^portal_admin/{print $3}' $CONFIG_FILE`
		LOG "Portal Admin = $PORTAL_ADMIN"

		# Get PORTAL User: PORTAL_USER
		PORTAL_USER=`awk '/^portal_user/{print $3}' $CONFIG_FILE`
		LOG "Portal User = $PORTAL_USER"

		# Get Portal Pass: PORTAL_PASS
		PORTAL_PASS=`awk '/^portal_pass/{print $3}' $CONFIG_FILE`
		LOG "Portal Pass = *********"

		# Get Portal Schema: PORTAL_SCHEMA
		PORTAL_SCHEMA=`awk '/^portal_schema/{print $3}' $CONFIG_FILE`
		LOG "Portal Schema = $PORTAL_SCHEMA"

		# Get Stage Schema: STAGE_DB
		STAGE_DB=`awk '/^stage_db/{print $3}' $CONFIG_FILE`
		LOG "Stage DB = $STAGE_DB"

		# Get SQL_FILE: FDW_TABLES
		FDW_TABLES=`awk '/^fdw_tables/{print $3}' $CONFIG_FILE`
		LOG "FDW_TABLES = $FDW_TABLES"

		# Get Portal Tables: PORTAL_TABLES
		PORTAL_TABLES=`awk '/^portal_tables/{print $3}' $CONFIG_FILE`
		LOG "PORTAL_TABLES = $PORTAL_TABLES"

		# Get Portal INDEXES: PORTAL_INDEXES
		PORTAL_INDEXES=`awk '/^portal_indexes/{print $3}' $CONFIG_FILE`
		LOG "PORTAL_INDEXES = $PORTAL_INDEXES"

		# Get Portal REFERENCES: PORTAL_REFERENCES
		PORTAL_REFERENCES=`awk '/^portal_references/{print $3}' $CONFIG_FILE`
		LOG "PORTAL_REFERENCES = $PORTAL_REFERENCES"

		# Mail list
		MAILIST=`awk '/^mailist/{print $3}' $CONFIG_FILE`
		LOG "MAILIST = $MAILIST"

		# Table count for error checking
		TABLE_COUNT=`awk '/^table_count/{print $3}' $CONFIG_FILE`
		LOG "TABLE_COUNT = $TABLE_COUNT"

		# Table count for error checking
		VIEW_COUNT=`awk '/^view_count/{print $3}' $CONFIG_FILE`
		LOG "VIEW_COUNT = $VIEW_COUNT"

		# Table count for error checking
		ZERO_COUNT=`awk '/^zero_count/{print $3}' $CONFIG_FILE`
		LOG "ZERO_COUNT = $ZERO_COUNT"
	else
		RC=94
		STATUS=FAILED
		MSG="ERROR $CONFIG_FILE DOES NOT EXIST. Exiting (RC=$RC)"
		LOGD "$MSG"
		exit $RC
	fi
	LOGD "Completed READ_CONFIG()"
}


#==============================================================
# Function CREATE_DB() - Create Database
# - d_portal (should be present)
# - stage    (should not exist)
#==============================================================
CREATE_DB() {

	LOGD "Starting CREATE_DB()"

	# PORTAL_DB should always exist.
	LOGD "Checking if $PORTAL_DB exist: \c"
	DB_NUM=`psql -tc "\l $PORTAL_DB" | grep -c "^ $PORTAL_DB "`
	if [ $DB_NUM -eq 1 ] || [ "$NEW" == "Y" ];then
		LOG "YES"

		# Create $STAGE_DB Database
		LOGD "Checking if $STAGE_DB exist: \c"
		DB_NUM=`$PSQL -lqt | grep -c "^ $STAGE_DB"`
		if [ $DB_NUM -eq 0 ];then
			LOG "No"

			# If this is a new portal instance, portal_admin user might not exist
			NUM_USER=`psql -tc "\du $PORTAL_ADMIN" | grep -c "^ $PORTAL_ADMIN "`
			if [ $NUM_USER -eq 0 ] || [ "$NEW" == "Y" ];then
				LOGD  "Creating user $PORTAL_ADMIN: \c"
				$PSQL -d postgres -c "CREATE USER $PORTAL_ADMIN WITH NOLOGIN" >> $LOGFILE 2>&1
				NUM_USER=`psql -tc "\du $PORTAL_ADMIN" | grep -c "^ $PORTAL_ADMIN "`
				if [ $NUM_USER -eq 1 ];then
					LOG "Created."
				else
					LOG "ERROR"
					RC=68
					STATUS=FAILED
					MSG="ERROR: User $PORTAL_ADMIN DOES NOT EXIST and CREATE FAILED. EMAIL and EXIT. STATUS = $STATUS, RC=$RC"
					LOGD "$MSG"
					EMAIL
					exit $RC
				fi
			fi
			
			# -e echo, -O owner, RC=0 means successful
			LOGD "Running: createdb -e -O $PORTAL_ADMIN $STAGE_DB \"Portal Stage Databaase\""
			$CREATEDB -e -O $PORTAL_ADMIN $STAGE_DB "Portal Stage Databaase" >> $LOGFILE 2>&1
			RC=$?
			LOGD "$CREATEDB return code: $RC"
			if [ $RC -eq 0 ];then
				LOGD "Database $STAGE_DB has been created"

				# If public schema exist, delete.
				LOGD "DROP SCHEMA public;"
				$PSQL -d $STAGE_DB -c "DROP SCHEMA IF EXISTS public" >> $LOGFILE 2>&1
				# Verify public is gone

				# Create Schema $PORTAL_SCHEMA
				LOGD "Creating schema $PORTAL_SCHEMA:"
				$PSQL -U postgres -d $STAGE_DB -c "CREATE SCHEMA $PORTAL_SCHEMA" >> $LOGFILE 2>&1
				# Error checking  ***

				# Update refresh_times table
				LOGD "Creating and updating table ${PORTAL_SCHEMA}.refresh_times:"
				$PSQL -U postgres -d $STAGE_DB -c "CREATE TABLE IF NOT EXISTS ${PORTAL_SCHEMA}.refresh_times (hostname VARCHAR(25) NOT NULL, database VARCHAR(20) NOT NULL, start_time TIMESTAMP(0), rename_portal TIMESTAMP(0), rename_stage_portal TIMESTAMP(0), copy_data TIMESTAMP(0), PRIMARY KEY(hostname,database));" >> $LOGFILE 2>&1
				$PSQL -U postgres -d $STAGE_DB -c "INSERT INTO ${PORTAL_SCHEMA}.refresh_times (hostname, database, start_time) VALUES ('$HOST', '$PORTAL_DB', CURRENT_TIMESTAMP);" >> $LOGFILE 2>&1
			else
				RC=66
				STATUS=FAILED
				MSG="ERROR: Database $STAGE_DB WAS NOT CREATED. EXIT (STATUS=$STATUS, RC=$RC)"
				LOGD "$MSG"
				EMAIL
				exit $RC
			fi
		else
			LOG "Yes"
			RC=64
			STATUS=FAILED
			MSG="ERROR: $STAGE_DB EXIST. EXIT. STATUS = $STATUS, RC=$RC"
			LOGD "$MSG"
			EMAIL
			exit $RC
		fi
		
	else
		# Skip only if NEW=Y
		LOG "No"
		RC=62
		STATUS=FAILED
		MSG="ERROR: $PORTAL_DB DOES NOT EXIST. EXIT. STATUS = $STATUS, RC=$RC"
		LOGD "$MSG"
		EMAIL
		exit $RC
	fi

	LOGD "Completed CREATE_DB()"
}


#==============================================================
# Function CREATE EXT() - CREATE_EXT
# Following Extensions are required
# - oracle_fdw
# - postgis
#==============================================================
CREATE_EXT() {

	LOGD "Starting CREATE_EXT for Database $STAGE_DB"

	EXTENSIONS="oracle_fdw postgis pg_stat_statements"
	for EXT in $EXTENSIONS;do
		LOGD "Creating extension $EXT: \c"
		$PSQL -td $STAGE_DB -c "CREATE EXTENSION $EXT SCHEMA $PORTAL_SCHEMA" >> $LOGFILE 2>&1
		NUM=`$PSQL -td $STAGE_DB -c "\dx $EXT" | grep -c "^ $EXT"` 
		if [ $NUM -eq 1 ];then
			LOG "CREATED"
		else
			LOG "FAILED"
			RC=58
			STATUS=FAILED
			MSG="Extension $EXT FAILED to CREATE in $STAGE_DB: EXIT (STATUS = $STATUS, RC=$RC) !!!"
			LOGD "$MSG"
			EMAIL
			exit $RC
		fi
	done

	LOGD "Completed CREATE_EXT()"
}


#==============================================================
# Function BUILD_FDW_TABLES()
# - Create FDW tables in db $STAGE_DB and schema $PORTAL_SCHEMA
#==============================================================
BUILD_FDW_TABLES() {

	if [ -f $LOGFILE_SQL ];then
		mv $LOGFILE_SQL ${LOGFILE_SQL}.prev
	fi

	# FDW_FILE from Configfile
	SQL_DIR="$DIR/SQL"

	LOGD "Starting BUILD_FDW_TABLES()"

	VERSION=`$PSQL -t $PORTAL_DB --command="SELECT version();" | awk '{print $1" "$2}'`
	LOG "Database $PORTAL_DB Version = $VERSION"

	VERSION=`$PSQL -t $STAGE_DB --command="SELECT version();" | awk '{print $1" "$2}'`
	LOG "Database $STAGE_DB Version = $VERSION"

	LOGD "Creating FDW tables in database $STAGE_DB, schema $PORTAL_SCHEMA"
	if [ -f "$SQL_DIR/$FDW_TABLES" ];then
		LOGD "SQL File $FDW_TABLES exist."

		# Create Server FOREIGN DATA WRAPPER oracle_fdw
		LOGD "CREATE SERVER $PDR_DB FOREIGN DATA WRAPPER oracle_fdw OPTIONS (dbserver '$PDR_DB');\""
		LOG  "Running: $PSQL -U postgres -d $STAGE_DB -c \"CREATE SERVER $PDR_DB FOREIGN DATA WRAPPER oracle_fdw OPTIONS (dbserver '$PDR_DB');\""
		$PSQL -U postgres -d $STAGE_DB -c "CREATE SERVER $PDR_DB FOREIGN DATA WRAPPER oracle_fdw OPTIONS (dbserver '$PDR_DB');" >> $LOGFILE 2>&1

		LOGD "GRANT USAGE ON FOREIGN SERVER $PDR_DB to $PORTAL_ADMIN"
		LOG  "Running: $PSQL -U postgres -d $STAGE_DB -c \"GRANT USAGE ON FOREIGN SERVER $PDR_DB to $PORTAL_ADMIN\""
		$PSQL -U postgres -d $STAGE_DB -c "GRANT USAGE ON FOREIGN SERVER $PDR_DB to $PORTAL_ADMIN" >> $LOGFILE 2>&1

		LOGD "CREATE USER MAPPING FOR $PORTAL_ADMIN SERVER $PDR_DB OPTIONS (user '$PDR_USER', password '***********');"
		LOG  "Running: $PSQL -U postgres -d $STAGE_DB -c \"CREATE USER MAPPING FOR $PORTAL_ADMIN SERVER $PDR_DB OPTIONS (user '$PDR_USER', password '***********');\""
		$PSQL -U postgres -d $STAGE_DB -c "CREATE USER MAPPING FOR $PORTAL_ADMIN SERVER $PDR_DB OPTIONS (user '$PDR_USER', password '$PDR_PASS');" >> $LOGFILE 2>&1

		LOGD "GRANT USAGE, CREATE ON SCHEMA $PORTAL_SCHEMA TABLES TO $PORTAL_ADMIN"
		LOG  "Running: $PSQL -U postgres -d $STAGE_DB -c \"GRANT USAGE, CREATE ON SCHEMA $PORTAL_SCHEMA TO $PORTAL_ADMIN;\""
		$PSQL -U postgres -d $STAGE_DB -c "GRANT USAGE, CREATE ON SCHEMA $PORTAL_SCHEMA TO $PORTAL_ADMIN;" >> $LOGFILE 2>&1

		LOGD "Grant Usage on portal to $PORTAL_ADMIN:"
		LOG  "Running: $PSQL -U postgres -d $STAGE_DB -c GRANT USAGE, CREATE ON SCHEMA $PORTAL_SCHEMA to $PORTAL_ADMIN"
		$PSQL -U postgres -d $STAGE_DB -c "GRANT USAGE, CREATE ON SCHEMA $PORTAL_SCHEMA to $PORTAL_ADMIN;" >> $LOGFILE 2>&1

		LOG  "Running: $PSQL -o -U postgres -d $STAGE_DB -f $SQL_DIR/$FDW_TABLES >> $LOGFILE_SQL 2>&1"
		$PSQL -U postgres -d $STAGE_DB -f $SQL_DIR/$FDW_TABLES >> $LOGFILE_SQL 2>&1
		LOGD "Completed Creating FDW tables in ${STAGE_DB}.${STAGE_SCHMEA}"

		LOGD "GRANT SELECT ON ALL TABLES IN SCHEMA $PORTAL_SCHEMA to $PORTAL_ADMIN"
		LOG  "Running: $PSQL -U postgres -d $STAGE_DB -c \"GRANT SELECT ON ALL TABLES IN SCHEMA $PORTAL_SCHEMA to $PORTAL_ADMIN;\""
		$PSQL -U postgres -d $STAGE_DB -c "GRANT SELECT ON ALL TABLES IN SCHEMA $PORTAL_SCHEMA to $PORTAL_ADMIN;" >> $LOGFILE 2>&1
	else
		RC=48
		STATUS=FAILED
		MSG="SQL File $FDW_TABLES DOES NOT EXIST. Exit"
		LOGD "$MSG"
		EMAIL
		exit $RC
	fi

	LOGD "Completed BUILD_FDW_TABLES()"
}


#==============================================================
# Function PORTAL_TABLES() - Load Data from FDW Database
# - Load tables into stage database, portal schema
#==============================================================
PORTAL_TABLES() {

	# Portal Tables
	PORTAL_TABLES="$CONFIG_DIR/$PORTAL_TABLES"

	LOGD "Starting PORTAL_TABLES()"

	if [ -f "$PORTAL_TABLES" ];then
		LOGD "The file $PORTAL_TABLES exist."

		# Call CREATE_TABLE Function
		NUM_TABLES=0
		for TABLE in `cat $PORTAL_TABLES`;do

			# Only Allow MAX tables to be created at once
			LOGD "Current number of table builds = $NUM_TABLES (MAX = $MAXTABLES)"
			while [ $NUM_TABLES -ge $MAXTABLES ];do
				NUM_TABLES=`ps -ef | grep -v grep | grep "CREATE TABLE" | grep -ic psql`
				LOGD "Current number of tables being created = $NUM_TABLES"
				sleep 10
			done

			# Call Table Create Function in Backgroud
			CREATE_TABLE $TABLE &

			# Wait to check for table operations
			sleep 3

			# Calculate number of table operations
			NUM_TABLES=`ps -ef | grep -v grep | grep "CREATE TABLE" | grep -ic psql`
		done
		
		LOGD "Update ${PORTAL_SCHEMA}.refresh_times with copy_data timestamp"
		$PSQL -U postgres -d $STAGE_DB -c "INSERT INTO ${PORTAL_SCHEMA}.refresh_times (hostname, database, copy_data) VALUES ('$HOST', '$PORTAL_DB', CURRENT_TIMESTAMP) ON CONFLICT (hostname, database) DO UPDATE SET copy_data = EXCLUDED.copy_data;" >> $LOGFILE 2>&1

	else
		RC=38
		STATUS=FAILED
		MSG="The file $PORTAL_TABLES DOES NOT EXIST. EXIT (RC=$RC)"
		LOGD "$MSG"
		EMAIL
		exit $RC
	fi

	# Wait for CREATE_TABLE function to finish
	wait

	LOGD "Completed PORTAL_TABLES()"
}


#==============================================================
# Function CREATE_TABLE() - Create Tables
#==============================================================
CREATE_TABLE() {

	TABLE=$1

	LOGD "Starting CREATE_TABLES() - $TABLE"
	LOG  "CREATE TABLE $TABLE AS (SELECT * FROM ${PORTAL_SCHEMA}.${TABLE}_FDW);"
	$PSQL -U postgres -d $STAGE_DB -c "set role to $PORTAL_ADMIN;CREATE TABLE ${PORTAL_SCHEMA}.${TABLE} AS (SELECT * FROM ${PORTAL_SCHEMA}.${TABLE}_FDW);" >> $LOGFILE 2>&1

	# DROP FDW Table
	LOGD "Running: $PSQL -U postgres -d $STAGE_DB -c \"set role to $PORTAL_ADMIN;DROP FOREIGN TABLE ${PORTAL_SCHEMA}.${TABLE}_FDW);\""
	$PSQL -U postgres -d $STAGE_DB -c "set role to $PORTAL_ADMIN; DROP FOREIGN TABLE ${PORTAL_SCHEMA}.${TABLE}_FDW;" >> $LOGFILE 2>&1
	LOGD "Completed CREATE_PORTAL() - $TABLE"
}


#==============================================================
# Function PORTAL_INDEXES() - Create Indexes
#==============================================================
PORTAL_INDEXES() {

	SQL_DIR="$DIR/SQL"
	PORTAL_INDEXES="$SQL_DIR/$PORTAL_INDEXES"

	LOGD "Starting PORTAL_INDEXES()"
	if [ -f "$PORTAL_INDEXES" ];then
		LOGD "Executing $PORTAL_INDEXES"
		$PSQL -U postgres -d $STAGE_DB -f $PORTAL_INDEXES >> $LOGFILE_SQL 2>&1
		# Found # of indexes needed ***
	else
		RC=28
		STATUS=FAILED
		MSG="ERROR: COULD NOT FIND file: $PORTAL_INDEXES"
		LOGD "$MSG"
		EMAIL
		exit $RC
	fi
	LOGD "Completed PORTAL_INDEXES()"
}


#==============================================================
# Function PORTAL_REFERENCES() - Create References
#==============================================================
PORTAL_REFERENCES() {

	SQL_DIR="$DIR/SQL"
	PORTAL_REFERENCES="$SQL_DIR/$PORTAL_REFERENCES"

	LOGD "Starting PORTAL_REFERENCES()"
	if [ -f $PORTAL_REFERENCES ];then
		LOGD "Executing $PORTAL_REFERENCES"
		$PSQL -U postgres -d $PORTAL_DB -f $PORTAL_REFERENCES >> $LOGFILE
	else
		RC=26
		STATUS=FAILED
		MSG="ERROR: COULD NOT FIND file: $PORTAL_REFERENCES"
		LOGD "$MSG"
		EMAIL
		exit $RC
	fi
	LOGD "Completed PORTAL_REFERENCES()"
}


#==============================================================
# Function RUN_VACUUM_ANALYZE() - Check if already running
#==============================================================
RUN_VACUUM_ANALYZE() {

	LOGD "Starting RUN_VACUUM_ANALYZE()"
	# If vacuum neceesary?
	$PSQL -t -d $STAGE_DB -c "VACUUM ANALYZE;" >> $LOGFILE
	#$PSQL -t -d $STAGE_DB -c "vacuumdb --all --analyze-only;" >> $LOGFILE
	LOGD "Completed RUN_VACUUM_ANALYZE()"
}


#==============================================================
# Function CK_RUNNING() - Check if already running
#==============================================================
CK_RUNNING() {

	LOGD "Starting RUNNING()"
	RUNS=`ps -ef | grep -v grep | grep -c pg_sync_portal.sh`
	if [ $RUNS -gt 2 ];then
		STATUS=FAILED
		RC=91
		LOGD "$BASENAME already running. Exiting (STATUS = $STATUS, RC=$RC)"
		exit $RC
	fi
	LOGD "Completed RUNNING()"
}


#==============================================================
# Function RENAME_DB() - Rename Database
#                      - Need to verify database is safe to 
#==============================================================
RENAME_DB() {

	# Copy database if need to revert back
	PORTAL_SAVED="${PORTAL_DB}_saved"

	LOGD "Starting RENAME_DB()"

	LOGD "Verifying database $STAGE_DB exist and valid before renaming to database $PORTAL_DB."
	DB_NUM=`psql -tc "\l $STAGE_DB" | grep -c "^ $STAGE_DB "`
	if [ $DB_NUM -eq 1 ];then
		LOGD "Database $STAGE_DB exist."
		# Verify $STAGE_DB is valid
		VERIFY
		RENAME_STATUS=$?	

		# If RENAME_STATUS = 0 $STAGE_DB found valid
		if [ $RENAME_STATUS -eq 0 ];then
		
			LOGD "Renaming database $PORTAL_DB to $PORTAL_SAVED"
			LOG "Running: $PSQL -td postgres -c \"ALTER DATABASE $PORTAL_DB RENAME TO $PORTAL_SAVED;\""

			#----------------------------------------------------------------------------------
			# Before rename, need to make sure there are no connections, if so kill them
			#----------------------------------------------------------------------------------

			SQL_ACTIVE="
			SELECT
				count(*)
			FROM
				pg_stat_activity
			WHERE
				datname = '$PORTAL_DB' AND
				usename <> 'postgres' AND
				state <> 'idle'
			"

			SQL_KILL="
			SELECT
				pg_terminate_backend(pg_stat_activity.pid)
			FROM
				pg_stat_activity
			WHERE
				datname = '$PORTAL_DB' AND
				usename <> 'postgresql'
			"

			# How many times to check before killing
			LOOP=3
			WAITED=0

			# Check for active sessions before killing
			NUM_ACTIVE=`psql -Atd $PORTAL_DB -c "$SQL_ACTIVE"` >> $LOGFILE 2>&1

			if [ $NUM_ACTIVE -gt 0 ];then
				# Start loop to allow active session to start
				until [ $LOOP -eq 0 ];do
					LOGD "Sleeping"
					sleep 2
					NUM_ACTIVE=`psql -Atd $PORTAL_DB -c "$SQL_ACTIVE"` >> $LOGFILE 2>&1
					if [ $NUM_ACTIVE -eq 0 ];then
						LOGD "Active Sessions, sleep (number of tries: $WAITED)"
						break
					fi
					((LOOP=LOOP-1))
					((WAITED=WAITED+1))
				done
			fi

			LOGD "Killing Session, kill (number of loops: $WAITED)"
			$PSQL -d postgres -c "$SQL_KILL" >> $LOGFILE 2>&1
			LOGD "Sessions Killed"

			#----------------------------------------------------------------------------------
			# Completed Kill sessions
			#----------------------------------------------------------------------------------

			$PSQL -td postgres -c "ALTER DATABASE $PORTAL_DB RENAME TO $PORTAL_SAVED;" >> $LOGFILE 2>&1

			LOGD "Update ${PORTAL_SCHEMA}.refresh_times with copy_data timestamp"
			$PSQL -U postgres -d $STAGE_DB -c "INSERT INTO ${PORTAL_SCHEMA}.refresh_times (hostname, database, rename_portal) VALUES ('$HOST', '$PORTAL_DB', CURRENT_TIMESTAMP) ON CONFLICT (hostname, database) DO UPDATE SET rename_portal = EXCLUDED.rename_portal;" >> $LOGFILE 2>&1

			# Need to update $STAGE_DB before rename
			LOGD "Update ${PORTAL_SCHEMA}.refresh_times with rename_stage_portal timestamp"
			$PSQL -U postgres -d $STAGE_DB -c "INSERT INTO ${PORTAL_SCHEMA}.refresh_times (hostname, database, rename_stage_portal) VALUES ('$HOST', '$PORTAL_DB', CURRENT_TIMESTAMP) ON CONFLICT (hostname, database) DO UPDATE SET rename_stage_portal = EXCLUDED.rename_stage_portal;" >> $LOGFILE 2>&1

			# Calling Function to $STAGE_DB
			GRANT_PORTAL

			LOGD "Renaming database $STAGE_DB to $PORTAL_DB"
			LOG "Running: $PSQL -td postgres -c \"ALTER DATABASE $STAGE_DB RENAME TO $PORTAL_DB;\""
			$PSQL -td postgres -c "ALTER DATABASE $STAGE_DB RENAME TO $PORTAL_DB;" >> $LOGFILE 2>&1

			DB_NUM=`psql -tc "\l $PORTAL_DB" | grep -c "^ $PORTAL_DB "`
			if [ $DB_NUM -eq 1 ];then
				LOGD "Database $PORTAL_DB has been refreshed."
				# More error checking

				LOGD "Dropping database $PORTAL_SAVED"
				LOG "Running: $PSQL -tc \"DROP DATABASE $PORTAL_SAVED;\""
				$PSQL -td postgres -c "DROP DATABASE $PORTAL_SAVED;" >> $LOGFILE 2>&1
				DB_NUM=`psql -tc "\l $PORTAL_SAVED" | grep -c "^ $PORTAL_SAVED "`
				if [ $DB_NUM -eq 0 ];then
					LOGD "Database $PORTAL_SAVED has been dropped"
				else
					RC=78
					STATUS=FAILED
					MSG="ERROR: $PORTAL_SAVED DID NOT GET DELETED.. STATUS = $STATUS, RC=$RC"
					LOGD "$MSG"
					EMAIL
					exit $RC
				fi
			else
				RC=76
				STATUS=FAILED
				MSG="ERROR: $PORTAL_DB DOES NOT EXIST. EXIT. STATUS = $STATUS, RC=$RC"
				LOGD "$MSG"
				EMAIL
				exit $RC
			fi
		else
			RC=74
			STATUS=FAILED
			MSG="ERROR: $STAGE_DB FAILED Validation. Check number of tables, views and rows. EXIT. STATUS = $STATUS, RC=$RC"
			LOGD "$MSG"
			EMAIL
			exit $RC
		fi
	else
		RC=72
		STATUS=FAILED
		MSG="ERROR: $STAGE_DB DOES NOT EXIST. EXIT. STATUS = $STATUS, RC=$RC"
		LOGD "$MSG"
		EMAIL
		exit $RC
	fi
}


#==============================================================
# Function VERIFY() - Check before database renamed
#==============================================================
VERIFY() {

	# Set to success, 0 = success
	VERIFY_STATUS=0

	# Verify stage database is valid before renaming
	LOGD "Starting VERIFY()"

	#------------------------------------------------
	# Checks: table count, 
	#------------------------------------------------

	# Verify Table Count
	TABLES_FOUND=`$PSQL -Atd $STAGE_DB -c "SELECT count(*) FROM pg_stat_user_tables;"`
	LOGD "Number of tables found        : $TABLES_FOUND"
	LOGD "Number of tables configured   : $TABLE_COUNT"
	# If TRUE, NOT VALID
	if [ $TABLES_FOUND -ne $TABLE_COUNT ];then
		VERIFY_STATUS=1
	fi

	# Verify View Count
	VIEWS_FOUND=`$PSQL -Atd $STAGE_DB -c "SELECT count(*) FROM pg_views WHERE SCHEMANAME = 'portal';"`
	LOGD "Number of views found         : $VIEWS_FOUND"
	LOGD "Number of views configured    : $VIEW_COUNT"
	# If TRUE, NOT VALID
	if [ $VIEWS_FOUND -ne $VIEW_COUNT ];then
		VERIFY_STATUS=1
	fi

	# Verify Row Count
	ZERO_FOUND=`$PSQL -Atd $STAGE_DB -c "SELECT count(*) FROM pg_stat_user_tables WHERE n_live_tup = 0;"`
	LOGD "Number of zero rows found     : $ZERO_FOUND"
	LOGD "Number of zero rows configured: $ZERO_COUNT"
	# If TRUE, NOT VALID
	if [ $ZERO_FOUND -ne $ZERO_COUNT ];then
		VERIFY_STATUS=1
	fi

	LOGD "Verification: \c"
	if [ $VERIFY_STATUS -eq 0 ];then
		LOG "PASSED"
	else
		LOG "FAILED"
	fi
	
	LOGD "Complete VERIFY()"
	return $VERIFY_STATUS
}


#==============================================================
# Function GRANT_PORTAL() - Create role and grant
#==============================================================
GRANT_PORTAL() {

	# Create x_portal_rl and grant to x_portal
	LOGD "Starting GRANT_PORTAL()"

	LOGD "Refreshing role $STAGE_DB"
	$PSQL -d $STAGE_DB -c "CREATE ROLE ${PORTAL_USER}_rl NOLOGIN;" >> $LOGFILE 2>&1
	#$PSQL -d $STAGE_DB -c "COMMENT ON ROLE IS \\'Role for user ${PORTAL_USER}\\';" >> $LOGFILE 2>&1
	$PSQL -d $STAGE_DB -c "GRANT CONNECT ON DATABASE ${STAGE_DB} TO ${PORTAL_USER}_rl;" >> $LOGFILE 2>&1
	$PSQL -d $STAGE_DB -c "GRANT USAGE ON SCHEMA ${PORTAL_SCHEMA} to ${PORTAL_USER}_rl;" >> $LOGFILE 2>&1
	$PSQL -d $STAGE_DB -c "GRANT SELECT ON ALL TABLES IN SCHEMA $PORTAL_SCHEMA to ${PORTAL_USER}_rl;" >> $LOGFILE 2>&1
	#$PSQL -d $STAGE_DB -c "ALTER ROLE ${PORTAL_USER}_rl SET search_path = ${PORTAL_SCHEMA};" >> $LOGFILE 2>&1
	$PSQL -d postgres -c "CREATE USER $PORTAL_USER" >> $LOGFILE 2>&1
	$PSQL -d $STAGE_DB -c "GRANT ${PORTAL_USER}_rl to $PORTAL_USER;" >> $LOGFILE 2>&1

	LOGD "Completed GRANT_PORTAL()"
}

#==============================================================
# Function EMAIL() - Send Email Results
#==============================================================
EMAIL() {

	# Get refresh_times
	REFRESH_TIMES=`$PSQL -Atd $PORTAL_DB -c "SELECT * FROM ${PORTAL_SCHEMA}.refresh_times;"`

	HOSTNAME=`echo $REFRESH_TIMES  | awk -F"|" '{print $1}'`
	DATABASE=`echo $REFRESH_TIMES  | awk -F"|" '{print $2}'`
	STARTTIME=`echo $REFRESH_TIMES | awk -F"|" '{print $3}'`
	RENAME_PORTAL=`echo $REFRESH_TIMES       | awk -F"|" '{print $4}'`
	RENAME_STAGE_PORTAL=`echo $REFRESH_TIMES | awk -F"|" '{print $5}'`
	COPY_DATA=`echo $REFRESH_TIMES | awk -F"|" '{print $6}'`

	# Spaces to format Outlook
	MSG="HOSTNAME                             $HOSTNAME\n"	
	MSG+="DATABASE                              $DATABASE\n"	
	MSG+="STARTTIME                             $STARTTIME\n"	
	MSG+="RENAME_PORTAL                 $RENAME_PORTAL\n"	
	MSG+="RENAME_STAGE_PORTAL   $RENAME_STAGE_PORTAL\n"
	MSG+="COPY_DATA                           $COPY_DATA\n"
	MSG+="TABLES_FOUND                       $TABLES_FOUND\n"
	MSG+="VIEWS_FOUND                        $VIEWS_FOUND\n"
	MSG+="ZERO_FOUND                          $ZERO_FOUND\n"
	
	SUBJECT="$PORTAL_DB has been refreshed STATUS = $STATUS, RC=$RC"
	echo -e "$MSG" | mailx -s "$HOST - $SUBJECT" $MAILIST

	# Update Remote/Montiring Backup Table
	# LOGD "Updating postgres.pgs_portal_refresh table:"
	# Get refresh_times
	if [ $RC -ne 0 ];then
		LOG "$MYSQL -h $REPO_HOST -D $REPO_DB -e \"INSERT INTO pgs_portal_refresh VALUES ('$HOSTNAME', '$DATABASE', NULL, NULL, NULL, NULL, NOW(),'$STATUS');\" >> $LOGFILE 2>&1"
		$MYSQL -h $REPO_HOST -D $REPO_DB -e "INSERT INTO pgs_portal_refresh VALUES ('$HOSTNAME', '$DATABASE', NULL, NULL, NULL, NULL, NOW(),'$STATUS');" >> $LOGFILE 2>&1
	else
		LOG "$MYSQL -h $REPO_HOST -D $REPO_DB -e \"INSERT INTO pgs_portal_refresh VALUES ('$HOSTNAME', '$DATABASE', '$STARTTIME', '$RENAME_PORTAL', '$RENAME_STAGE_PORTAL', '$COPY_DATA', NOW(), '$STATUS');\" >> $LOGFILE 2>&1"
		$MYSQL -h $REPO_HOST -D $REPO_DB -e "INSERT INTO pgs_portal_refresh VALUES ('$HOSTNAME', '$DATABASE', '$STARTTIME', '$RENAME_PORTAL', '$RENAME_STAGE_PORTAL', '$COPY_DATA', NOW(), '$STATUS');" >> $LOGFILE 2>&1
	fi
}

#==============================================================
# Main Starts Here
#==============================================================
# If LOGDIR does not exist, create
if [ ! -d "$LOGDIR" ];then
	mkdir -p $LOGDIR
fi

echo "$LINE" >> $LOGFILE
LOGD "Starting $BASENAME"

# If no options, print USAGE
if [ "$#" -eq 0 ];then
	USAGE
	# Probably will never get here
	RC=99
	LOGD "No options supplied. Exit $RC"
	STATUS=FAILED
	exit $RC
fi

# Quit if already running
CK_RUNNING

# Read Command Line Parameter File
# d = Development, i = Intergrantion, c = certification and p = production
while getopts dicpnthv opt ;do
        case $opt in
           d ) ENVIR="Developmnet";   CONFIGFILE=dev_portal.cfg;;
           i ) ENVIR="Integration";   CONFIGFILE=int_portal.cfg;;
           c ) ENVIR="Certification"; CONFIGFILE=cert_portal.cfg;;
           p ) ENVIR="Production";    CONFIGFILE=prod_portal.cfg;;
           t ) ENVIR="Testing";       CONFIGFILE=test_portal.cfg;;
           n ) NEW=Y;;
           v ) echo "VERSION=$VERSION";;
           h ) USAGE ; LOGD "exit 98" eixt 98;;
          \? ) USAGE ; LOGD "exit 97" eixt 97;;
        esac
done

# Make sure LOGDIR exist
CHK_LOGDIR

# Read Configuration and Get environment
READ_CONFIG $ENVIR $CONFIGFILE

# Check if $PORTAL_DB Exist, If not either new systems or something is wrong
# Make sure $STAGE_DB got cleaned up
CREATE_DB

# Create Extensions, required
CREATE_EXT

# PORTAL_STAGE_DB defined from READ_CONFIG
BUILD_FDW_TABLES

# Load Data into PostgreSQL Target Database from command line parameter
PORTAL_TABLES

# Create Indexes
PORTAL_INDEXES

# Create References
PORTAL_REFERENCES

# Analyze/Vacuum Database
# Needs to be on stage only ***
RUN_VACUUM_ANALYZE

# Rename Database once everything has been confirmed
RENAME_DB

# Grants? Before RENAME_DB or After
# Code Here Maybe

# Email Final
EMAIL

LOGD "Completed $BASENAME"
CLEAN_LOG
exit $RC
