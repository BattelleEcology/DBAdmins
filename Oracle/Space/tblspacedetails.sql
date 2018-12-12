set linesize 999
col "FILE_NAME" for a40
select
substr(file_name,1,40) as File_Name,
substr(tablespace_name,1,10) as Tablespace_Name,
bytes/1024/1024 as Size_Mb
from dba_data_files
order by tablespace_name, file_name;
select df.tablespace_name "Tablespace",
totalusedspace "Used MB",
(df.totalspace - tu.totalusedspace) "Free MB",
df.totalspace "Total MB",
round(100 * ( (df.totalspace - tu.totalusedspace)/ df.totalspace))
"Pct. Free"
from
(select tablespace_name,
round(sum(bytes) / 1048576) TotalSpace
from dba_data_files
group by tablespace_name) df,
(select round(sum(bytes)/(1024*1024)) totalusedspace, tablespace_name
from dba_segments
group by tablespace_name) tu
where df.tablespace_name = tu.tablespace_name ;
