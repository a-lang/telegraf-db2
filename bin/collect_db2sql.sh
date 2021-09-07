#!/usr/bin/env bash
############################################################################
# Author: Alang, created by 2021/6/29 (alang.hsu@gmail.com)
# Purpose: This script works with the Telegraf, 
#          which is used to collect some metrics of the DB and
#          push them into the InfluxDB
#
# Usage: $0 -d {db-name} -a {alias-db-name} -u {db-user} -p {db-pass}
# Updated: 2021/7/19, Alang
#
#
###########################################################################

errlog="/var/log/telegraf/agent/err.$(basename $0).log"

. /home/db2mon/sqllib/db2profile

Usage() { 
    echo
    echo "Usage: $0 -d <database_name> -a <alias-db-name> -u <db_user> -p <db_pass>"
    echo
}

ToUpper() {
    echo $1 | tr "[:lower:]" "[:upper:]"
}

Is_number() { 
    # Usage: Is_number ${your-number} 0 
    # If the number is invalid, return 0.
    # If not specify, return NULL
    local input err_num re
    input=$1
    err_num=$2
    re="^[0-9]+([.][0-9]+)?$"
    if [[ $input =~ $re ]]; then
        echo $input
    else
        echo $err_num
    fi
}

Trim_space() {
    # Usage: Trim_space ${your-string}
    local input
    input=$1
    echo "$input" | sed 's/[[:space:]]//g'
}

Get_longsql() {
    local csv

    db2 -x "select substr(APPLICATION_NAME,1,20) ||'@'|| APPLICATION_HANDLE ||'@'|| SESSION_AUTH_ID ||'@'|| ELAPSED_TIME_SEC ||'@'|| ACTIVITY_STATE ||'@'|| substr(STMT_TEXT,1,100)  from sysibmadm.MON_CURRENT_SQL \
            where \
              ELAPSED_TIME_SEC > 60 \
            order by ELAPSED_TIME_SEC desc \
            fetch first 5 rows only " > $tmpfile
    # Debug only
    #cat $tmpfile
    #if [ $(wc -l $tmpfile | cut -b1) != "0" ]
    #then
    #    echo "=== [DEBUG]Time: $(date +'%F %T'), DB: $dbals  ===" >> $errlog
    #    cat $tmpfile >> $errlog
    #fi 

    while read line;
    do
        if [ "$(echo $line | sed -n '/@/p')" != "" ]
        then
            _appl_name=$(echo $line | awk -F@ '{print $1}')
            _appl_handle=$(echo $line | awk -F@ '{print $2}')
            _auth_id=$(echo $line | awk -F@ '{print $3}')
            _elapsed_time_sec=$(echo $line | awk -F@ '{print $4}')
            _activity_state=$(echo $line | awk -F@ '{print $5}')
            _stmt_text=$(echo $line | awk -F@ '{print $6}' | sed 's/\"/\\"/g')
            
            if [ -n $(Trim_space $_appl_handle) ] && [ -n $(Trim_space $_auth_id) ] && [ -n $_elapsed_time_sec ]
            then
                Output_longsql
            fi
        fi
    done < $tmpfile

}

Output_longsql() {
    _db=$dbals

    # InfluxDB Format:
    # <measurement>,<tag-key>=<tag-value> <field1-key>=<field1-value>,<field2-key>=<field2-value>,...
    echo "longsql,db=$_db,appl_handle=$(Trim_space $_appl_handle),appl_name=$(Trim_space $_appl_name),auth_id=$(Trim_space $_auth_id),activity_state=$_activity_state elapsed_time_sec=$_elapsed_time_sec,stmt_text=\"${_stmt_text}\""
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

tmpfile=$(mktemp) || exit 1
trap "rm -f $tmpfile" EXIT

Get_longsql

# Terminate the connection
db2 terminate > /dev/null 2>&1
