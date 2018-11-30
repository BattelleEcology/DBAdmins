#!/bin/bash
#-------------------------------------------------------------------------------
# PURPOSE: List current running jobs fro the V$SESSION_LINGOPS and
#          RMAN backup information from V$RMAN_BACKUP_JOB_DETAILS
# AUTHOR : James Schroeter
# DATE   : 09/02/2018
#
#-------------------------------------------------------------------------------
VERSION="1.0"


sqlplus -s '/ as sysdba' <<EOF

SELECT
	SID,
	SERIAL#,
	CONTEXT,
	SOFAR,
	TOTALWORK, 
	ROUND (SOFAR/TOTALWORK*100, 2) "% COMPLETE"
FROM
	V\$SESSION_LONGOPS
WHERE
	OPNAME LIKE 'RMAN%' AND
	OPNAME NOT LIKE '%aggregate%' AND
	TOTALWORK! = 0 AND
	SOFAR <> TOTALWORK
/

set linesize 500 pagesize 2000
col Hours format 9999.99
col STATUS format a25
col RMAN_BKUP_START_TIME format a25
col RMAN_BKUP_END_TIME format a25

SELECT
	SESSION_KEY,
	INPUT_TYPE,
	STATUS,
	to_char(START_TIME,'mm-dd-yyyy hh24:mi:ss') as RMAN_Bkup_start_time,
	to_char(END_TIME,'mm-dd-yyyy hh24:mi:ss') as RMAN_Bkup_end_time,
	elapsed_seconds/3600 Hours
FROM
	V\$RMAN_BACKUP_JOB_DETAILS
ORDER BY
	session_key
/

EOF
