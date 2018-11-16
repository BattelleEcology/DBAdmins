#!/bin/bash
#-------------------------------------------------------------------------------
# PURPOSE: List information about the FRA
#             - Size
#             - Destination
#             - Contents
# AUTHOR : James Schroeter
# DATE   : 09/09/2018
#
#-------------------------------------------------------------------------------
VERSION="1.0"


sqlplus -s '/ as sysdba' <<EOF
SET LINES 100;

-- Destination and Size
show parameter db_recovery_file_dest;

-- Size, used, Reclaimable
SELECT
        ROUND((a.space_limit / 1024 / 1024 / 1024), 2) AS FLASH_IN_GB,
        ROUND((a.space_used / 1024 / 1024 / 1024), 2) AS FLASH_USED_IN_GB,
        ROUND((a.space_reclaimable / 1024 / 1024 / 1024), 2) AS FLASH_RECLAIMABLE_GB,
        SUM(b.percent_space_used)  AS PERCENT_OF_SPACE_USED
FROM
        v\$recovery_file_dest a,
        v\$flash_recovery_area_usage b
GROUP BY
        space_limit,
        space_used ,
        space_reclaimable
/

-- Show contents of FRA, what is using FRA
SELECT * FROM V\$RECOVERY_AREA_USAGE
/

-- show parameter log_archive_dest
-- /
EOF
