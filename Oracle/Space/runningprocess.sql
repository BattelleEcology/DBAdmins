/*To find the current running process on database*/
col sid format 99999 
col p1 format 99999999999999
col p2 format 99999999999999
col event format a35
col state format a20
set pages 200
set lines 200
break on event
compute count of event on event

select inst_id, sid,event,sql_id,state,row_wait_obj# ,FINAL_BLOCKING_SESSION,FINAL_BLOCKING_INSTANCE 
from gv$session 
where event not like '%message%' 
and wait_class<>'Idle' 
order by event;
