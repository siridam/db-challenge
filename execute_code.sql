
-------------------------------------
-- CREATE ROLES
-------------------------------------

CREATE USER MASTER_RW WITH PASSWORD 'dam0901';

CREATE USER MASTER_RO WITH PASSWORD 'app0729';


-------------------------------------
-- SCHEMA
-------------------------------------

CREATE SCHEMA USER_SCHEMA ;

GRANT USAGE ON SCHEMA USER_SCHEMA TO MASTER_RW;
GRANT USAGE ON SCHEMA USER_SCHEMA TO MASTER_RO;

-------------------------------------
-- Table Creation - USER_SCHEMA.USER
-------------------------------------

DROP TABLE IF EXISTS USER_SCHEMA.USER CASCADE
;

CREATE TABLE USER_SCHEMA.USER(
       LOGIN_ID              VARCHAR    
     , FNAME                 VARCHAR    NOT NULL
     , LNAME                 VARCHAR    NOT NULL
     , DOB                   DATE       NOT NULL
     , EMAIL_ID              VARCHAR    NOT NULL 
     , PASSWORD              VARCHAR    NOT NULL
     , IS_AUTHENTICATED      BOOLEAN  -- will be made active when user authenticates with the key generated
     , ACT_CREATE_DT         DATE
     , PWD_EXPIRY_DT         DATE
)
;

ALTER TABLE USER_SCHEMA.USER ADD CONSTRAINT PK_USER PRIMARY KEY (LOGIN_ID);

ALTER TABLE USER_SCHEMA.USER ADD CONSTRAINT UK_USER UNIQUE (EMAIL_ID);

GRANT SELECT ON USER_SCHEMA.USER TO MASTER_RO;

GRANT SELECT, INSERT, UPDATE, DELETE ON USER_SCHEMA.USER TO MASTER_RW;


-------------------------------------
-- Table Creation - USER_SCHEMA.KEY
-------------------------------------

DROP TABLE IF EXISTS USER_SCHEMA.KEY CASCADE
;

CREATE TABLE USER_SCHEMA.KEY(
       EMAIL_ID                   VARCHAR    
     , KEY                        VARCHAR           NOT NULL
     , CREATE_TIME                TIMESTAMPTZ       NOT NULL DEFAULT CURRENT_TIMESTAMP
     , EXPIRY_TIME                TIMESTAMPTZ       NOT NULL DEFAULT CURRENT_TIMESTAMP + INTERVAL '1 HOUR' 
)
;

ALTER TABLE USER_SCHEMA.KEY ADD CONSTRAINT PK_KEY PRIMARY KEY (EMAIL_ID)
;
ALTER TABLE USER_SCHEMA.KEY ADD CONSTRAINT KEY_FK1 FOREIGN KEY (EMAIL_ID) REFERENCES USER_SCHEMA.USER (EMAIL_ID) ON DELETE NO ACTION ON UPDATE NO ACTION
;

GRANT SELECT ON USER_SCHEMA.KEY TO MASTER_RO;

GRANT SELECT, INSERT, UPDATE, DELETE ON USER_SCHEMA.KEY TO MASTER_RW;

---------------------------------------------
-- Table Creation - USER_SCHEMA.LOG_HISTORY
---------------------------------------------
DROP TABLE IF EXISTS USER_SCHEMA.LOG_HISTORY CASCADE
;

CREATE TABLE USER_SCHEMA.LOG_HISTORY(
       LOG_ID                     SERIAL PRIMARY KEY
     , LOGIN_ID                   VARCHAR    NOT NULL
     , STATUS                     VARCHAR    NOT NULL
     , STATUS_CODE                INTEGER 
     , ERROR_DESCRIPTION          VARCHAR
     , SESSION_ID                 INTEGER
     , SESSION_START_TIME         TIMESTAMPTZ
     , SESSION_END_TIME           TIMESTAMPTZ
)
;

GRANT SELECT ON USER_SCHEMA.LOG_HISTORY TO MASTER_RO;

GRANT SELECT, INSERT, UPDATE, DELETE ON USER_SCHEMA.LOG_HISTORY TO MASTER_RW;

--------------------------
-- create F_GENERATE_KEY
---------------------------

drop function if exists USER_SCHEMA.F_GENERATE_KEY;
CREATE OR REPLACE FUNCTION USER_SCHEMA.F_GENERATE_KEY (
    EMAIL VARCHAR
)
    RETURNS  VARCHAR
    LANGUAGE PLPGSQL
AS 
$$
DECLARE KEY_GENERATED VARCHAR;
BEGIN

INSERT INTO USER_SCHEMA.KEY ( EMAIL_ID
                            , KEY
                            , CREATE_TIME
                            , EXPIRY_TIME
                            )
     SELECT EMAIL                                 AS EMAIL_ID
          , MD5(RANDOM()::TEXT)                   AS KEY
          , CURRENT_TIMESTAMP                     AS CREATE_TIME
          , CURRENT_TIMESTAMP + INTERVAL '1 HOUR' AS EXPIRY_TIME

 ON CONFLICT ON CONSTRAINT PK_KEY
   DO UPDATE
              SET KEY           = EXCLUDED.KEY
                , CREATE_TIME   = CURRENT_TIMESTAMP
                , EXPIRY_TIME   = CURRENT_TIMESTAMP + INTERVAL '1 HOUR'
            WHERE USER_SCHEMA.KEY.KEY    <> EXCLUDED.KEY;
            
SELECT KEY INTO KEY_GENERATED FROM USER_SCHEMA.KEY WHERE EMAIL_ID = EMAIL;
RETURN KEY_GENERATED;

END;

$$;

GRANT EXECUTE ON FUNCTION USER_SCHEMA.F_GENERATE_KEY TO MASTER_RO;
GRANT EXECUTE ON FUNCTION USER_SCHEMA.F_GENERATE_KEY TO MASTER_RW;

--------------------------
-- create F_CREATE_USER
-----------------------------
drop function if exists USER_SCHEMA.F_CREATE_USER;
CREATE OR REPLACE FUNCTION USER_SCHEMA.F_CREATE_USER (
     LOGIN          varchar
   , FIRST_NAME     varchar
   , LAST_NAME      varchar
   , DATE_OF_BIRTH  date
   , EMAIL          varchar 
   , PASSWD         varchar
)
    RETURNS VARCHAR
language plpgsql
    as 
    $$
    DECLARE ACTIVATION_KEY VARCHAR;
begin
     INSERT INTO USER_SCHEMA.USER ( LOGIN_ID
                                  , FNAME
                                  , LNAME
                                  , DOB
                                  , EMAIL_ID
                                  , PASSWORD
                                  )
     SELECT LOGIN           AS LOGIN_ID
          , FIRST_NAME      AS FNAME
          , LAST_NAME       AS LNAME
          , DATE_OF_BIRTH   AS DOB
          , EMAIL           AS EMAIL_ID
          , PASSWD          AS PASSWORD
      
  ON CONFLICT ON CONSTRAINT PK_USER DO NOTHING;
               
ACTIVATION_KEY = (select USER_SCHEMA.F_GENERATE_KEY(EMAIL));
return ACTIVATION_KEY;
end;
$$; 

GRANT EXECUTE ON FUNCTION USER_SCHEMA.F_CREATE_USER TO MASTER_RO;
GRANT EXECUTE ON FUNCTION USER_SCHEMA.F_CREATE_USER TO MASTER_RW;


---------------------------------------------------------------
-- create F_AUTHENTICATE_USER
---------------------------------------------------------------
drop function if exists USER_SCHEMA.F_AUTHENTICATE_USER;
CREATE OR REPLACE FUNCTION USER_SCHEMA.F_AUTHENTICATE_USER (
     EMAIL      VARCHAR
   , KEY_VALUE  VARCHAR
)
    RETURNS   VARCHAR
LANGUAGE PLPGSQL
    AS 
    $$
    --DECLARE AUTHENTICATE VARCHAR;
BEGIN

IF EXISTS ( SELECT 1 FROM USER_SCHEMA.KEY
             WHERE EMAIL_ID = EMAIL
               AND KEY = KEY_VALUE
               AND CURRENT_TIMESTAMP <= EXPIRY_TIME )

THEN 
    UPDATE USER_SCHEMA.USER
       SET IS_AUTHENTICATED  = TRUE
         , ACT_CREATE_DT = CURRENT_DATE
         , PWD_EXPIRY_DT = CURRENT_DATE + INTERVAL '1 MONTH'
     WHERE EMAIL_ID = EMAIL;
     
     RETURN 'ACCOUNT ACTIVATED';

ELSE

    UPDATE USER_SCHEMA.USER
       SET IS_AUTHENTICATED = FALSE
     WHERE EMAIL_ID = EMAIL 
       AND IS_AUTHENTICATED <> TRUE;
     
    RETURN 'FAILED TO AUTHENTICATE USER / ALREADY AUTHENTICATED';

END IF;
END;

$$;

GRANT EXECUTE ON FUNCTION USER_SCHEMA.F_AUTHENTICATE_USER TO MASTER_RO;
GRANT EXECUTE ON FUNCTION USER_SCHEMA.F_AUTHENTICATE_USER TO MASTER_RW;

---------------------------------------------------------------
-- create F_CHANGE_PWD
---------------------------------------------------------------
drop function if exists USER_SCHEMA.F_CHANGE_PWD;
CREATE OR REPLACE FUNCTION USER_SCHEMA.F_CHANGE_PWD (
     login varchar
   , new_paswd  varchar
)
    RETURNS   VARCHAR
language plpgsql
    as 
    $$
    --DECLARE AUTHENTICATE VARCHAR;
begin

CASE WHEN EXISTS ( SELECT 1 FROM user_schema.user WHERE login_id = login and password <> new_paswd and is_authenticated = true)

THEN 
     update TEST_SCHEMA.user 
     set password = new_paswd
       , pwd_expiry_dt = CURRENT_DATE + INTERVAL '1 MONTH'
     where login_id = login
       and is_authenticated = true
      ;
      RETURN 'PASSWORD UPDATED';

WHEN
      EXISTS ( SELECT 1 FROM user_schema.user WHERE login_id = login and password = new_paswd and is_authenticated = true)
THEN
       RETURN 'NEW PASSWORD CANNOT BE SAME AS EXISTING PASSWORD';

ELSE
      RETURN 'USER/ACCOUNT DOES NOT EXIST';
end CASE;

END;

$$;

GRANT EXECUTE ON FUNCTION USER_SCHEMA.F_CHANGE_PWD TO MASTER_RO;
GRANT EXECUTE ON FUNCTION USER_SCHEMA.F_CHANGE_PWD TO MASTER_RW;

---------------------------------------------------------------
-- create F_LOG_HISTORY
---------------------------------------------------------------
drop function if exists USER_SCHEMA.F_LOG_HISTORY;
CREATE OR REPLACE FUNCTION USER_SCHEMA.F_LOG_HISTORY (
     LOGIN VARCHAR
   , PASSWD VARCHAR
)
    RETURNS VARCHAR
LANGUAGE PLPGSQL
    AS 
    $$
    DECLARE STATUS_CODE VARCHAR;
BEGIN

CASE

WHEN EXISTS ( SELECT 1 FROM USER_SCHEMA.USER WHERE LOGIN_ID = LOGIN AND PASSWORD = PASSWD AND PWD_EXPIRY_DT >= CURRENT_DATE AND IS_AUTHENTICATED = TRUE)

THEN 
      INSERT INTO USER_SCHEMA.LOG_HISTORY ( LOGIN_ID
                                          , LOGIN_STATUS
                                          , STATUS_CODE
                                          , ERROR_DESCRIPTION
                                          , SESSION_ID
                                          , SESSION_START_TIME
                                          , SESSION_END_TIME
                                          )
     SELECT LOGIN                             AS LOGIN_ID
          , 'SUCCESS'                         AS LOGIN_STATUS
          , '0'                               AS STATUS_CODE
          , NULL                              AS ERROR_DESCRIPTION
          , PID                               AS SESSION_ID
          , CURRENT_TIMESTAMP                 AS SESSION_START_TIME
          , NULL                              AS SESSION_END_TIME
       FROM PG_STAT_ACTIVITY WHERE USENAME = LOGIN AND STATE= 'active';
          
     SELECT PID INTO STATUS_CODE FROM PG_STAT_ACTIVITY WHERE USENAME = LOGIN AND STATE = 'active';
     RETURN STATUS_CODE;

WHEN EXISTS ( SELECT 1 FROM USER_SCHEMA.USER WHERE LOGIN_ID = LOGIN AND PASSWORD = PASSWD AND IS_AUTHENTICATED = TRUE AND PWD_EXPIRY_DT < CURRENT_DATE)

THEN 
     INSERT INTO USER_SCHEMA.LOG_HISTORY ( LOGIN_ID
                       , LOGIN_STATUS
                       , STATUS_CODE
                       , ERROR_DESCRIPTION
                       , SESSION_ID
                       , SESSION_START_TIME
                       , SESSION_END_TIME
                       )
     SELECT LOGIN                             AS LOGIN_ID
          , 'FAIL'                            AS LOGIN_STATUS
          , '1'                               AS STATUS_CODE
          , 'ACCOUNT IS INACTIVE'             AS ERROR_DESCRIPTION
          , NULL                              AS SESSION_ID
          , NULL                              AS SESSION_START_TIME
          , NULL                              AS SESSION_END_TIME;
          
      RETURN '1';
      
WHEN EXISTS ( SELECT 1 FROM USER_SCHEMA.USER WHERE LOGIN_ID = LOGIN AND PASSWORD = PASSWD AND IS_AUTHENTICATED = FALSE)

THEN 
     INSERT INTO USER_SCHEMA.LOG_HISTORY ( LOGIN_ID
                       , LOGIN_STATUS
                       , STATUS_CODE
                       , ERROR_DESCRIPTION
                       , SESSION_ID
                       , SESSION_START_TIME
                       , SESSION_END_TIME
                       )
     SELECT LOGIN                             AS LOGIN_ID
          , 'FAIL'                            AS LOGIN_STATUS
          , '2'                               AS STATUS_CODE
          , 'ACCOUNT NOT AUTHENTICATED'       AS ERROR_DESCRIPTION
          , NULL                              AS SESSION_ID
          , NULL                              AS SESSION_START_TIME
          , NULL                              AS SESSION_END_TIME;
              
      RETURN '2';
      
WHEN EXISTS ( SELECT 1 FROM USER_SCHEMA.USER WHERE LOGIN_ID = LOGIN AND PASSWORD <> PASSWD )

THEN 
     INSERT INTO USER_SCHEMA.LOG_HISTORY ( LOGIN_ID
                       , LOGIN_STATUS
                       , STATUS_CODE
                       , ERROR_DESCRIPTION
                       , SESSION_ID
                       , SESSION_START_TIME
                       , SESSION_END_TIME
                       )
     SELECT LOGIN                             AS LOGIN_ID
          , 'FAIL'                            AS LOGIN_STATUS
          , '3'                               AS STATUS_CODE
          , 'PASSWORD IS WRONG'               AS ERROR_DESCRIPTION
          , NULL                              AS SESSION_ID
          , NULL                              AS SESSION_START_TIME
          , NULL                              AS SESSION_END_TIME;
              
      RETURN '3';

when EXISTS ( SELECT 1 FROM USER_SCHEMA.USER WHERE LOGIN_ID <> LOGIN  )

THEN 
     INSERT INTO USER_SCHEMA.LOG_HISTORY ( LOGIN_ID
                                         , LOGIN_STATUS
                                         , STATUS_CODE
                                         , ERROR_DESCRIPTION
                                         , SESSION_ID
                                         , SESSION_START_TIME
                                         , SESSION_END_TIME
                                         )
     SELECT LOGIN                             AS LOGIN_ID
          , 'FAIL'                            AS LOGIN_STATUS
          , '4'                               AS STATUS_CODE
          , 'NO SUCH USER EXISTS IN DB'       AS ERROR_DESCRIPTION
          , NULL                              AS SESSION_ID
          , NULL                              AS SESSION_START_TIME
          , NULL                              AS SESSION_END_TIME;
          
      RETURN '4';
else
return 'UNKNOWN ERROR';
END CASE;
END;
$$; 

GRANT EXECUTE ON FUNCTION USER_SCHEMA.F_LOG_HISTORY TO MASTER_RO;
GRANT EXECUTE ON FUNCTION USER_SCHEMA.F_LOG_HISTORY TO MASTER_RW;

---------------------------------------------------------------
-- create f_rpt_password_expiry
---------------------------------------------------------------
drop function if exists USER_SCHEMA.f_rpt_password_expiry;
create or replace function USER_SCHEMA.f_rpt_password_expiry()
returns setof varchar AS
$$
    select FNAME || ' ' || LNAME
    from user_schema.user
     where pwd_expiry_dt - current_date < 7
       and is_authenticated = true
$$ 
language sql;

GRANT EXECUTE ON FUNCTION USER_SCHEMA.f_rpt_password_expiry TO MASTER_RO;
GRANT EXECUTE ON FUNCTION USER_SCHEMA.f_rpt_password_expiry TO MASTER_RW;

---------------------------------------------------------------
-- create f_rpt_users_logged
---------------------------------------------------------------
drop function if exists USER_SCHEMA.f_rpt_users_logged;
create or replace function USER_SCHEMA.f_rpt_users_logged(start_time time, end_time time)
returns table (login_date date, count bigint) as
$$
begin
return query
    select cast(to_char(session_start_time,'yyyy-mm-dd') as date) as login_date , count(1) as count
     from user_schema.log_history h
        , user_schema.user u
     WHERE h.login_id = u.login_id
       and status_code = 0
      and extract(year from age(CURRENT_DATE,DOB)) = 18
     and (cast(to_char(session_start_time,'hh:mm:ss') as time) <= end_time
         or cast(to_char(session_end_time,'hh:mm:ss') as time) >= start_time )
         group by cast(to_char(session_start_time,'yyyy-mm-dd') as date);
         
END;
$$
LANGUAGE plpgsql;

GRANT EXECUTE ON FUNCTION USER_SCHEMA.f_rpt_users_logged TO MASTER_RO;
GRANT EXECUTE ON FUNCTION USER_SCHEMA.f_rpt_users_logged TO MASTER_RW;