#!/bin/bash
#===========================================================================
# PURPOSE: Run vacuum and analyze
# AUTHOR : JSchroeter
# DATE   : 08/26/2020
#
# INFO: Run analyze and Autobackup
#
#===========================================================================
VERSION=1.0

# Variables MUST EXIST
BASENAME=`basename $0`
BASENAME2=`basename $0 .sh`
CURDIR_NAME=`dirname $0`
CONFIG_FILE="$CURDIR_NAME/${BASENAME2}.cfg"
LOGDIR="/db01/Logs"
LOGFILE="$LOGDIR/${BASENAME2}.log"
STATUS=0
DATE="date +%F-%T"

# LINE
LINE="============================================================"

# psql command
PSQL="/usr/bin/psql"
VACUUMDB="/usr/bin/vacuumdb"

#=========================================
# USAGE() - Display USAGE
#=========================================
USAGE() {
	echo "
		USAGE: $BASENAME [ -d <database> | -l | -s <database> | -h | -v ]

		-d  <database>
		-l  Display databases
		-s  Display vacuum status for <database>
		-h  Display help   
		-v  Display version

"

exit 99

}


#=============================================
# LOGD() - Log all messages to LOGFILE w/ Date
#=============================================
LOGD() {
	echo -e "`$DATE`  $*" >> $LOGFILE
}


#============================================
# LOG() - Log all messages to LOGFILE
#============================================
LOG() {
	echo -e "$*" >> $LOGFILE
}


#============================================
# VACUUM_STATS() - List vacuum stats
#============================================
VACUUM_STATS() {

	DB=$1

	LOGD "VACUUM_STATS()"

	SQL="
	SELECT
		schemaname,
		relname,
		n_live_tup,
		n_dead_tup,
		last_vacuum::timestamp(0),
		last_autovacuum::timestamp(0),
		last_analyze::timestamp(0),
		vacuum_count
	FROM
		pg_stat_user_tables
	ORDER BY
		n_dead_tup DESC, n_live_tup DESC
	"

	echo -e "\nList Database Vacuum Stats:\n"
	$PSQL -d $DB -c "$SQL;"

	LOGD "Completed VACUUM_STATS()"
}


#============================================
# LIST_DB() - List Databases and Information
#============================================
LIST_DB() {
	LOGD "Running LIST_DB()"
	$PSQL -c "SELECT datname, datcollate, datctype, datistemplate, datallowconn, datconnlimit, dattablespace FROM pg_database"
	LOGD "Completed LIST_DB()"
}


#============================================
# CHK_LOG_DIR() - Make sure LOGDIR Exist
#============================================
CHK_LOG_DIR() {

	if [ ! -d "$LOGDIR" ];then
		mkdir -p $LOGDIR
		RC=$?
		if [ "$RC" -eq 0 ];then
			LOGD "Logging directory $LOGDIR did NOT EXIST."
			chmod -R 700 $LOGDIR
		else
			echo "Could not creating $LOGDIR directory: Failed"
			RC=98
			STATUS=FAILED
			echo "ERROR: Could not create $LOGDIR directory. Existing: STATUS=$STATUS (RC=$RC)"
			exit $RC
		fi
	fi
}


#=========================================
# FUNCTION: VACUUM_ANALYZE
#=========================================
VACUUM_ANALYZE() {

	DB=$1

	LOGD "Starting function VACUUM_ANALYZE - database: $DB"
	LOGD "Running VACUUM_STATUS"
	VACUUM_STATS $DB >> $LOGFILE
	LOGD "Running command: $VACUUMDB -d $DB -z"
	$VACUUMDB -d $DB -z >> $LOGFILE
	RC=$?
	VACUUM_STATS $DB >> $LOGFILE
	LOGD "Completed function VACUUM_ANALYZE - Status: $STATUS"
}


#=========================================
# Main Starts Here
#=========================================
if [ $# -lt 1 ];then
	USAGE
	exit 99
fi

# Make sure LOGDIR exist
CHK_LOG_DIR

# Add LINE to LOGFILE
echo "$LINE" >> $LOGFILE
LOGD "Starting $BASENAME"

# Parse command line arugments
while getopts d:ls:hv options;do
	case $options in
		 d) DB=$OPTARG; VACUUM_ANALYZE $DB;;
		 h) USAGE;;
		 l) LIST_DB;;
		 s) VACUUM_STATS $OPTARG;;
		 v) echo $VERSION;;
		 \?) USAGE;;
	esac
done

LOGD "Completed $BASENAME"
