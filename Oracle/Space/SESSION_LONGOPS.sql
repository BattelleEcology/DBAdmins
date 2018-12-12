set linesize 200
SELECT username,sid, serial#,
TO_CHAR(CURRENT_TIMESTAMP,'HH24:MI:SS') AS curr,
TO_CHAR(start_time,'HH24:MI:SS') AS logon,
(sysdate - start_time)*24*60 AS mins
FROM V$SESSION_LONGOPS
WHERE    username is not NULL
AND (SYSDATE - start_time)*24*60 > 1 ;
