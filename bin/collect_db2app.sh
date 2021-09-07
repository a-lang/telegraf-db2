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
    # Usage: Trim_space ${your-string} NULL
    local output
    output=$(echo $1 | sed 's/[[:space:]]//g')
    if [ -z $output ]
    then
        echo "$2"
    else
        echo "$output" 
    fi
}

Get_snapappl() {
    local csv

    db2 -x "select A.DB_NAME, A.AGENT_ID, substr(I.APPL_NAME,1,20), I.PRIMARY_AUTH_ID, I.APPL_STATUS, A.AGENT_USR_CPU_TIME_S, A.AGENT_SYS_CPU_TIME_S, A.ROWS_READ, A.ROWS_SELECTED, I.APPL_ID, COALESCE((NULLIF(A.ROWS_READ,0)/NULLIF(A.ROWS_SELECTED,0)),0) as my_cost, I.EXECUTION_ID from sysibmadm.snapappl A, sysibmadm.snapappl_info I \
            where A.DB_NAME = '$dbn' \
              and I.AGENT_ID = A.AGENT_ID \
              and I.DB_NAME = A.DB_NAME \
              and A.AGENT_USR_CPU_TIME_S > 0 \
              and I.IS_SYSTEM_APPL=0 \
            order by APPL_NAME " > $tmpfile
    # Covert to CSV
    sed -i "s/ \+/,/g" $tmpfile
    #cat $tmpfile

    for csv in $(cat $tmpfile);
    do
        _agent_id=$(echo $csv | awk -F, '{print $2}')
        _appl_name=$(echo $csv | awk -F, '{print $3}')
        _auth_id=$(echo $csv | awk -F, '{print $4}')
        _appl_status=$(echo $csv | awk -F, '{print $5}')
        _usr_cpu_time_s=$(echo $csv | awk -F, '{print $6}')
        _sys_cpu_time_s=$(echo $csv | awk -F, '{print $7}')
        _rows_read=$(echo $csv | awk -F, '{print $8}')
        _rows_selected=$(echo $csv | awk -F, '{print $9}')
        _appl_id=$(echo $csv | awk -F, '{print $10}')
        _my_cost=$(echo $csv | awk -F, '{print $11}')
        _exec_id=$(echo $csv | awk -F, '{print $12}')
        Output_snapappl
    done

}

Output_snapappl() {
    _db=$dbals

    # InfluxDB Format:
    # <measurement>,<tag-key>=<tag-value> <field1-key>=<field1-value>,<field2-key>=<field2-value>,...
    echo "snapappl,db=$_db,agent_id=$_agent_id,appl_name=$(Trim_space $_appl_name NULL),auth_id=$_auth_id,appl_status=$_appl_status,client_ip=${_appl_id%.*.*},exec_id=$(Trim_space $_exec_id NULL) usr_cpu_time_s=$_usr_cpu_time_s,sys_cpu_time_s=$_sys_cpu_time_s,rows_read=$_rows_read,rows_selected=$_rows_selected,my_cost=$_my_cost"
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

#tmpfile="/tmp/$(basename $0).$$.tmp"
tmpfile=$(mktemp) || exit 1
trap "rm -f $tmpfile" EXIT

Get_snapappl

# Terminate the connection
db2 terminate > /dev/null 2>&1
