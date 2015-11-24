






-------------------------------------------------------------------------------beginning of the query - anything above this is background information or for testing --------------------------------------


WITH  TEMP   AS    (

-------- the WITH subquery does most of the work
SELECT  

dev.id  AS  deviceid ,  dev.serial_number  AS  serialnumber  ,    dev.account_id  AS   accountid , acct.name  AS   accountname ,   acct.brand_id AS  brandid ,   ab.host  AS  brandname ,   dev.device_type_id AS  devicetypeid ,

dt.name   AS  devicetypename  ,

dnp.name  AS   device_network_provider_name ,

CASE   network.network_active WHEN  1  THEN  'true'  WHEN 0  THEN  'false'  ELSE NULL END  AS  networkactive ,   network.renewal_date AS  networkrenewaldate   ,

fl.minstartdate,   fl.maxstartdate   ,   

CASE  WHEN  DATEDIFF(DAY,  fl.maxstartdate,  (CURRENT_DATE - 2)) >= 7 THEN  1 
      WHEN  DATEDIFF(DAY,  fl.maxstartdate,  (CURRENT_DATE - 2)) <  7 THEN  0 
      ELSE NULL END AS  not_reporting                                               ,

DATEADD(DAY,    -7,    fl.maxstartdate)   AS  date_7_days_prior                     ,
DATEADD(DAY,     7,    fl.maxstartdate)   AS  date_7_days_after                     ,

devevent.daystamp ,      
devevent.eventtypecode  AS   event_type_code                                        ,   

CASE   devevent.eventtypecode   WHEN 'AUTO_LOC'   THEN 1
                                WHEN 'RESET'      THEN 2
                                WHEN 'EXT_PWR_LOW'  THEN 3
                                ELSE NULL  END   AS   "eventpriority"               ,
                              
devevent.eventtypecount  


-------------- it takes these 6 tables to replace tmp_accountdevice
FROM    device.device  dev  INNER JOIN  device.account acct  ON   dev.account_id  =   acct.id  --------------- tested at 100% no worries
                            INNER JOIN  device.app_brand  ab    ON  acct.brand_id  =  ab.id      ------------- INNER JOIN is OK here - app_brand is missing id "N" but this whole query is only about brand 62 
                            INNER JOIN  device.device_type  dt   ON  dev.device_type_id   =   dt.id  ------------ tested at 100% no worries
                            INNER JOIN  device.device_network   network  ON   dev.id  =   network.device_id   -----  this has to be an INNER JOIN - the few device_ids missing on device_network is a data quality problem to be solved elsewhere 
                            INNER JOIN  device.device_network_provider  dnp   ON   network.network_provider_id   =   dnp.id   ------ INNER JOIN is fine for 4 and 12 - device_network_provider is missing id of "N", currently 65k rows in device_network                         
                            
                            INNER JOIN  device.fg_firstlast  fl  ON   dev.account_id  = fl.accountid   AND    dev.id   =   fl.deviceid
                            INNER JOIN  device.dg_deviceevent devevent  ON   dev.account_id  =  devevent.accountid  AND   dev.id   =   devevent.deviceid



------- from fg_firstlast - only rows with eventtypecode AUTO_LOC
WHERE   fl.eventtypecode  =   'AUTO_LOC'

-----------  excluding Factory accounts 593 and 648
AND     acct.id   NOT IN   (593, 648)

----------- from dg_deviceevent - only interested in these event types
AND     devevent.eventtypecode   IN   ('RESET',   'EXT_PWR_LOW',  'AUTO_LOC')     


--------- from dg_deviceevent, we are only interested in rows that are plus or minus 7 days from the fg_firstlast most recent AUTO_LOC  
--------- this is one approach
----------AND   TO_DATE(devevent.daystamp,  'YYYYMMDD') >=   (fl.maxstartdate - 7)    
----------AND   TO_DATE(devevent.daystamp,  'YYYYMMDD') <=   (fl.maxstartdate + 7)
--------- but we will be doing it exactly Kousar's way
AND   devevent.daystamp  >=  CAST((TO_CHAR(DATEADD(DAY,   -7,  fl.maxstartdate),  'YYYYMMDD'))  AS  INTEGER)
AND   devevent.daystamp  <=  CAST((TO_CHAR(DATEADD(DAY,    7,  fl.maxstartdate),  'YYYYMMDD'))  AS  INTEGER)

------- only networks Nspire Sprint (4) and Nspire Sprint Vision (12) 
AND  network.network_provider_id   IN  ('4', '12')

------- and the final WHERE condition in the WITH subquery - restrict brandid 62 from the account table - ATS devices only   62=Vehicle Finance
AND   acct.brand_id    =  62



------------ IN PRODUCTION - IF YOU NEED TO LOOK AT SPECIFIC ACCOUNTS ADD THAT HERE
-----------   AND acct.accountid in (1560,91732,63586,959,91882,4266,2284) 


)

-------------  that is the end of the WITH subquery


SELECT 


A.deviceid  ,    A.serialnumber ,     A.accountid ,   A.accountname ,    A.brandid ,     A.brandname ,   A.devicetypename  ,   
A.device_network_provider_name  AS Carrier,    A.networkactive   ,    A.networkrenewaldate,   
DATE_PART('YEAR',  A.minstartdate) AS cohortyear, 
DATE_PART('MONTH', A.minstartdate) AS cohortmonth,
A.minstartdate as First_Auto_Locate,
A.maxstartdate as Last_Auto_Locate,

(SELECT eventtypecode FROM device.fg_firstlast fl WHERE fl.accountid = A.accountid AND fl.deviceid = A.deviceid ORDER BY maxstartdate DESC  LIMIT  1) AS lastevent          ,
(SELECT maxstartdate  FROM device.fg_firstlast fl WHERE fl.accountid = A.accountid AND fl.deviceid = A.deviceid ORDER BY maxstartdate DESC  LIMIT  1) AS lasteventdate      ,

CASE A.not_reporting WHEN  1 THEN 1 ELSE 0  END   AS NRU                                                                                                                    ,
CASE    WHEN  (A.not_reporting = 1 and A.eventpriority = 3) then 1 ELSE NULL END AS  Low_Battery                                                                            ,
CASE    WHEN  (A.not_reporting = 1 and A.eventpriority = 2) then 1 ELSE NULL END AS reset                                                                                   ,
CASE    WHEN  (A.not_reporting = 1 and A.eventpriority = 1 and COUNT(A.eventtypecount) < 8  ) THEN 1 ELSE NULL END AS spotty_autolocate                                     ,
CASE    WHEN  (A.not_reporting = 1 and A.eventpriority = 1 and COUNT(A.eventtypecount) = 8  ) then 1 ELSE NULL END AS stop_reporting                                        ,
CASE    WHEN  (A.networkactive  =  'false' and A.networkrenewaldate < (CURRENT_DATE - 2)) THEN 1 ELSE NULL END AS expired                                                   ,  



TO_CHAR(  (CURRENT_DATE - 2),  'Mon DD, YYYY')   AS  snapshot_date



FROM TEMP A

INNER JOIN 

(SELECT deviceid,    accountid,   accountname,   device_network_provider_name,   minstartdate,    maxstartdate,  MAX(eventpriority) AS eventpriority  
FROM  TEMP   GROUP BY   deviceid,  accountid,  accountname,  device_network_provider_name,  minstartdate,   maxstartdate     )    B

ON 

A.deviceid  =  B.deviceid   AND  A.accountid  =   B.accountid   AND   A.accountname =   B.accountname 
AND A.device_network_provider_name  =   B.device_network_provider_name AND  A.minstartdate =   B.minstartdate 
AND A.maxstartdate  =  B.maxstartdate
AND  A.eventpriority >= B.eventpriority

GROUP BY  A.deviceid, A.serialnumber, A.accountid, A.accountname, A.brandid,  A.brandname, A.devicetypename,  A.device_network_provider_name,   
A.networkactive,   A.networkrenewaldate ,    A.minstartdate ,   A.maxstartdate , A.event_type_code ,  A.eventpriority ,   A.not_reporting

ORDER BY  Carrier,  devicetypename,   NRU,  Low_Battery,  reset,   spotty_autolocate,   cohortyear,  cohortmonth,  accountname




--------------------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------- end of the real query - anything after this is for test




   
