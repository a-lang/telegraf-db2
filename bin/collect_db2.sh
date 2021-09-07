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

Get_snapdb() {
    local csv

    # APPLS_CUR_CONS: Applications connected currently
    # LOCKS_WAITING: Agents currently waiting on locks
    # NUM_INDOUBT_TRANS: Number of indoubt transactions

    db2 -x "select DB_NAME,APPLS_CUR_CONS,LOCKS_WAITING,NUM_INDOUBT_TRANS from sysibmadm.snapdb \
            where DB_NAME='$dbn' " > $tmpfile
    # Covert to CSV
    sed -i "s/ \+/,/g" $tmpfile
    # for debug only
    #cat $tmpfile

    for csv in $(cat $tmpfile);
    do
        _appls_cur_cons=$(Is_number $(echo $csv | awk -F, '{print $2}') 0)
        _locks_waiting=$(Is_number $(echo $csv | awk -F, '{print $3}') 0)
        _num_indoubt_trans=$(Is_number $(echo $csv | awk -F, '{print $4}') 0)
        Output_snapdb
    done

}

Output_snapdb() {
    _db=$dbals

    # InfluxDB Format:
    # <measurement>,<tag-key>=<tag-value> <field1-key>=<field1-value>,<field2-key>=<field2-value>,...
    echo "snapdb,db=$_db appls_cur_cons=$_appls_cur_cons,locks_waiting=$_locks_waiting,num_indoubt_trans=$_num_indoubt_trans"
}

Get_log_util() {
    local csv

    db2 -x "select DB_NAME, LOG_UTILIZATION_PERCENT, TOTAL_LOG_USED_KB, TOTAL_LOG_AVAILABLE_KB from sysibmadm.log_utilization \
            where DB_NAME='$dbn' " > $tmpfile
    # Covert to CSV
    sed -i "s/ \+/,/g" $tmpfile
    # for debug only
    #cat $tmpfile

    for csv in $(cat $tmpfile);
    do
        _log_utilization_percent=$(Is_number $(echo $csv | awk -F, '{print $2}') 0)
        _total_log_used_kb=$(Is_number $(echo $csv | awk -F, '{print $3}') 0)
        _total_log_available_kb=$(Is_number $(echo $csv | awk -F, '{print $4}') 0)
        Output_log_util
    done

}

Output_log_util() {
    _db=$dbals

    # InfluxDB Format:
    # <measurement>,<tag-key>=<tag-value> <field1-key>=<field1-value>,<field2-key>=<field2-value>,...
    echo "log_util,db=$_db log_util_percent=$_log_utilization_percent,log_used_kb=$_total_log_used_kb,log_available_kb=$_total_log_available_kb"
}

Get_snapdb2() {
    local csv

    db2 -x "select DB_NAME, COMMIT_SQL_STMTS, ROLLBACK_SQL_STMTS, DYNAMIC_SQL_STMTS, STATIC_SQL_STMTS, ROWS_READ from sysibmadm.snapdb \
            where DB_NAME='$dbn' " > $tmpfile
    # Covert to CSV
    sed -i "s/ \+/,/g" $tmpfile
    # for debug only
    #cat $tmpfile

    for csv in $(cat $tmpfile);
    do
        _commit_sql=$(Is_number $(echo $csv | awk -F, '{print $2}') 0)
        _rollback_sql=$(Is_number $(echo $csv | awk -F, '{print $3}') 0)
        _dynamic_sql=$(Is_number $(echo $csv | awk -F, '{print $4}') 0)
        _static_sql=$(Is_number $(echo $csv | awk -F, '{print $5}') 0)
        _rows_read=$(Is_number $(echo $csv | awk -F, '{print $6}') 0)
        Output_snapdb2
    done

}

Output_snapdb2() {
    _db=$dbals

    # InfluxDB Format:
    # <measurement>,<tag-key>=<tag-value> <field1-key>=<field1-value>,<field2-key>=<field2-value>,...
    echo "snapdb2,db=$_db commit_sql=$_commit_sql,rollback_sql=$_rollback_sql,dynamic_sql=$_dynamic_sql,static_sql=$_static_sql,rows_read=$_rows_read"
}

Get_bp_util() {
    local csv

    db2 -x "
WITH bp_metrics AS (
 SELECT bp_name,
   sum( pool_data_l_reads + pool_temp_data_l_reads +
     pool_index_l_reads + pool_temp_index_l_reads +
     pool_xda_l_reads + pool_temp_xda_l_reads) as logical_reads,
   sum( pool_data_p_reads + pool_temp_data_p_reads +
     pool_index_p_reads + pool_temp_index_p_reads +
     pool_xda_p_reads + pool_temp_xda_p_reads) as physical_reads \
 FROM TABLE(MON_GET_BUFFERPOOL('',-2)) AS METRICS \
 GROUP BY bp_name \
 ) \
 SELECT
   VARCHAR(bp_name,20) AS bp_name,
   logical_reads,
   physical_reads,
   CASE WHEN logical_reads > 0
     THEN DEC((1 - (FLOAT(physical_reads) / FLOAT(logical_reads))) * 100,5,2)
     ELSE NULL
   END AS HIT_RATIO
 FROM bp_metrics \
 WHERE logical_reads > 0 AND physical_reads > 0 " > $tmpfile


    # Covert to CSV
    sed -i "s/ \+/,/g" $tmpfile
    # for debug only
    #cat $tmpfile

    for csv in $(cat $tmpfile);
    do
        _bp_name=$(echo $csv | awk -F, '{print $1}')
        _logical_reads=$(echo $csv | awk -F, '{print $2}')
        _physical_reads=$(echo $csv | awk -F, '{print $3}')
        _hit_ratio_percent=$(Is_number $(echo $csv | awk -F, '{print $4}') 0)
        Output_bp_util
    done

}

Output_bp_util() {
    _db=$dbals

    # InfluxDB Format:
    # <measurement>,<tag-key>=<tag-value> <field1-key>=<field1-value>,<field2-key>=<field2-value>,...
    echo "bp_util,db=$_db,bp=$_bp_name logical_reads=$_logical_reads,physical_reads=$_physical_reads,hit_ratio_percent=$_hit_ratio_percent"
}

Get_tbsp_util() {
    local csv

    db2 -x "select TBSP_ID, TBSP_NAME, TBSP_TOTAL_SIZE_KB, TBSP_USED_SIZE_KB, TBSP_UTILIZATION_PERCENT from sysibmadm.TBSP_UTILIZATION \
            where TBSP_AUTO_RESIZE_ENABLED <> 1 \
              and TBSP_TYPE = 'DMS' " > $tmpfile
    # Covert to CSV
    sed -i "s/^[[:space:]]*//;s/ \+/,/g" $tmpfile
    # for debug only
    #cat $tmpfile

    for csv in $(cat $tmpfile);
    do
        _tbsp_id=$(echo $csv | awk -F, '{print $1}')
        _tbsp_name=$(echo $csv | awk -F, '{print $2}')
        _tbsp_total_kb=$(Is_number $(echo $csv | awk -F, '{print $3}') 0)
        _tbsp_used_kb=$(Is_number $(echo $csv | awk -F, '{print $4}') 0)
        _tbsp_util_percent=$(Is_number $(echo $csv | awk -F, '{print $5}') 0)
        Output_tbsp_util
    done

}

Output_tbsp_util() {
    _db=$dbals

    # InfluxDB Format:
    # <measurement>,<tag-key>=<tag-value> <field1-key>=<field1-value>,<field2-key>=<field2-value>,...
    echo "tbsp_util,db=$_db,tbsp_id=$_tbsp_id,tbsp_name=$_tbsp_name tbsp_total_kb=$_tbsp_total_kb,tbsp_used_kb=$_tbsp_used_kb,tbsp_util_percent=$_tbsp_util_percent"
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

Get_snapdb
Get_log_util
Get_snapdb2
Get_bp_util
Get_tbsp_util

# Terminate the connection
db2 terminate > /dev/null 2>&1
