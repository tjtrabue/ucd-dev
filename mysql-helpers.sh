#!/bin/bash
# Helper functions for mysql.

# Assumes a username of ibm_ucd and password 'password'
# Assumes the admin account is 'root' with password 'root'

# THESE FUNCTIONS ARE INSECURE.  Don't use them if you care about your data.

mysql_login_options="-u root -proot"

getDBName() {
    candidate=$1
    echo -n $candidate | tr '/-' '[_*]'
}


mysqlHasDB() {
    dbname=$1
    result=$(mysql $mysql_login_options -s -N -e "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME='$dbname'")
    if [ -z $result ]; then
        return 1
    fi

    return 0
}

addDeployDB() {
    db_name=$1

    echo "Creating DB $db_name"

    sql1="CREATE DATABASE ${db_name};"
    sql2="GRANT ALL ON ${db_name}.* TO 'ibm_ucd'@'%' IDENTIFIED BY 'password' WITH GRANT OPTION;"

    mysql $mysql_login_options -s -e "$sql1"
    mysql $mysql_login_options -s -e "$sql2"
}

deleteDB() {
    db_name=$1
}

moveDB() {
    db_src=$1
    db_dest=$2
}
