Please note that the code is executed and tested multiple times on pgAdmin4 version 7.1. 
If using different version and if code is not compatible, kindly let me know. I will update it to make it compatible with your preferred version.

------------------------
Deployment Instructions:
-------------------------

 1. Execute create_db.sql file first
    It will create a new database USER_DB.
  
2. please switch to new database USER_DB and then execute execute_code.sql
   this would create 3 tables and 7 functions


------------------
CODE DETAILS
-----------------

1. TO create user profile, 
   
    select user_schema.f_create_user(login, first_name, last_name, date_of_birth, email, passwd)

This would insert record into user_schema.USER and user_schema.key tables and return a key to authenticate

2. to regerate key,
     select  user_schema.f_generate_key(email)
	this would update key table with latest key and increase expiry time by 1 hour 
	   
3. when user authenticates with the key ,
    select user_schema.f_authenticate_user(email, key_value)
    user account is marked authenticated if done in 1 hour(is_authenticate = true in user table with expiry date of 1 month)

4. To change passwords, 
      select user_schema.f_change_pwd(login, new_paswd)
	  -- password updated in user table and expiry date is increased by 30 days

5. to log login history
      select user_schema.f_log_history(login, passwd)
	  -- logs into log_history table and returns session_id for succesful login / status_code for failed ones
	  
6. To logout from session
      select user_schema.f_logout(login)
	  -- updates session_end_time in log_history table and returns status message

7. To report the users who password is about to expire in 7 days
	  select user_schema.f_rpt_password_expiry()
	  -- displays users 'first_name last_name' who should update their passwords in 1 week
	  
8. To report for given time period parameters a number of distinct users logged into the system each day who is 18 years old (age >=18 years and < 19 years).
      select user_schema.f_rpt_users_logged(start_time, end_time)
	  -- This wil lreturn date,number of disticnt users logged
	  
	  
NOTE : This code can be enhanced to save memory and improve performance by definining column size and creating indexes if loading huge data.
 Assumed the parameters that come from external sources and coded accordingly.
 covered all the main  & most of the required scenarios and ingored few edge case scenarios
