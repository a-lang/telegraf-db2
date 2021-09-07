#!/usr/bin/env bash
############################################################################
# Author: Alang, created by 2021/6/29 (alang.hsu@gmail.com)
# Purpose: This script works with the Telegraf, 
#          which is used to collect some metrics of the DB and
#          push them into the InfluxDB
#
# Usage: $0 -d {db-name} -a {alias-db-name} -u {db-user} -p {db-pass}
#
#
###########################################################################

. /home/db2mon/sqllib/db2profile

Usage() { 
    echo
    echo "Usage: $0 -d <database_name> -a <alias-db-name> -u <db_user> -p <db_pass>"
    echo
}

ToUpper() {
    echo $1 | tr "[:lower:]" "[:upper:]"
}

Get_data() {
    local runsql csvdata

    runsql=$(db2 -x "select count(*) from sysibmadm.db_history where operation = 'X' and start_time > current timestamp - 1 hours")
    csvdata=$(echo $runsql | sed "s/ \+/,/g")
    _arch_count=$csvdata
}

Output_data() {
    _db=$dbals

    # InfluxDB Format:
    # <measurement>,<tag-key>=<tag-value> <field1-key>=<field1-value>,<field2-key>=<field2-value>,...
    echo "datax1h,db=$_db arch_count=$_arch_count"
}

while getopts ":d:a:u:p:" o; do
    case "$o" in
        d )
            d=$OPTARG
            ;;
        a )
            a=$OPTARG
            ;;
        u )
            u=$OPTARG
            ;;
        p )
            p=$OPTARG
            ;;
        \?)
            echo "Invalid option: -$OPTARG"
            Usage
            ;;
        :)
            echo "Option -$OPTARG requires an argument."
            Usage
            ;;
    esac
done 

if [ $OPTIND -ne 9 ]; then
    echo "Invalid options entered."
    Usage
    exit 1
fi    

dbn=$(ToUpper $d)
dbals=$(ToUpper $a)
dbuser=$u
dbpass=$p

# Detect the connection to the DB
db2 terminate > /dev/null 2>&1
db2 connect to $dbals user $dbuser using $dbpass > /dev/null 2>&1
if [ $? -ne 0 ]
then
    echo "Abort: Unable to connect to the database $dbn !"
    db2 terminate > /dev/null 2>&1
    exit 1
fi

Get_data
Output_data

# Terminate the connection
db2 terminate > /dev/null 2>&1
