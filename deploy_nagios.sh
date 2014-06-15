#!/bin/bash
#
# script will generate nagios cofiguration files
#

FILE_CLUSTER_IN="cluster.conf"
FILE_SERVICES_IN="services.conf"
DIR_OUT="etc/objects"
DIR_NRPE_OUT="etc/nrpe"
SERVICES_IN_DIR="services"

DOMAIN=".saske.sk"
HOSTS_FILE="hosts.cfg"
HOST_GROUP_FILE="hostgroups.cfg"
SERVICES_FILE="services.cfg"
SERVICE_GROUP_FILE="servicegroups.cfg"

DEPLOY_ONLY=0
DEPLOY_NAGIOS_SERVER="wiki.saske.sk:/etc/nagios"
DEPLOY_NAGIOS_NRPE_DIR="/etc/nrpe.d"

TEMPLATE_TYPE=0
TEMPLATE_CURRENT_NAME=""
TEMPLATES=""

function help() {
  echo
  echo "usage:"
  echo "       $0                : full process"
  echo "       $0 --deploy-only  : deploy only"
  echo
}

function check_prog() {
  echo -n "Chekcing $1 "
  IS_PROG=$(which $1)
  if [ ! $? -eq 0 ];then
    exit 1
  fi
  echo " [FOUND]"
}

function check() {
  check_prog scp
  check_prog ssh
  check_prog pssh
}

function ipfor() {
  ping -c 1 $1 | grep -Eo -m 1 '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}';
}

function hosts_gen() {


  [ $TEMPLATE_TYPE -eq 1 ] && return
  local MYHOST=$1

#  if [[ $MYHOST != *$DOMAIN* ]];then
#    if [ "${MYHOST:0:5}" != "tmpl_" ];then
#      echo "Error : Host '$MYHOST' doesn't containg '$DOMAIN' !!!"
#      exit 10
#    fi
#  fi
  local MYHOST_SHORT="${MYHOST//$DOMAIN/}"
#  local MYHOST_IP=$(host $MYHOST | cut -d " " -f 4)

  local MYHOST_IP=$(ipfor $MYHOST)

cat >> $DIR_OUT/$HOSTS_FILE <<EOF
define host {
    use            linux-server
    host_name      $MYHOST
    alias          $MYHOST_SHORT
    address        $MYHOST_IP
    contact_groups admins
}

EOF
}

function hostsgroup_gen() {

  [ $TEMPLATE_TYPE -eq 1 ] && return

  IS_GROUP=$(cat $DIR_OUT/$HOST_GROUP_FILE | grep "hostgroup_name" | grep $1)
  if [ ! $? -eq 0 ];then
cat >> $DIR_OUT/$HOST_GROUP_FILE <<EOF
define hostgroup {
        hostgroup_name  $1
        alias           $1
        members         $2
        }

EOF
  else
    # find line to change
    LINE=$(cat $DIR_OUT/$HOST_GROUP_FILE | grep -ni "hostgroup_name" | grep $1 | cut -d : -f 1)
    LINE=`expr $LINE + 2`
    [ $? -eq 0 ] || exit 1
    sed -i -e ''$LINE's/$/,'$2'/' $DIR_OUT/$HOST_GROUP_FILE
  fi
}

function services_gen() {

  [ $TEMPLATE_TYPE -eq 2 ] && return

  while read line; do
    [ -z "$line" ] && continue
    [ "${line:0:1}" = "#" ] && continue

    local SERVICE=$(echo $line | cut -d : -f 1)
    local SERVICE_DESCRIPTION=$(echo $line | cut -d : -f 2)
    local SERVICE_COMMAND=$(echo $line | cut -d : -f 3)
    local SERVICE_NRPE_COMMAND=$(echo $line | cut -d : -f 4,5,6)

    [ "$1" != "$SERVICE" ] && continue

    IS_CHECK_NRPE=$(echo $SERVICE_COMMAND | grep "check_nrpe!$SERVICE")
    if [ $? -eq 0 ];then
        echo "command[$SERVICE]=$SERVICE_NRPE_COMMAND" >> $DIR_NRPE_OUT/$2.cfg
    fi

    IS_SERVICE=$(cat $DIR_OUT/$SERVICES_FILE | grep "^# $SERVICE$")
    if [ ! $? -eq 0 ];then

cat >> $DIR_OUT/$SERVICES_FILE <<EOF
# $SERVICE
define service {
        use                             local-service
        host_name                       $2
        service_description             $SERVICE_DESCRIPTION
        check_command                   $SERVICE_COMMAND
        }

EOF

   else
      # find line to change
      LINE=$(cat $DIR_OUT/$SERVICES_FILE | grep -ni "^# $SERVICE$" | cut -d : -f 1)
      LINE=`expr $LINE + 3`
      [ $? -eq 0 ] || exit 1
      sed -i -e ''$LINE's/$/,'$2'/' $DIR_OUT/$SERVICES_FILE
    fi
  done < $FILE_SERVICES_IN

}

function services_gen_from_group() {

  [ $TEMPLATE_TYPE -eq 2 ] && return

  if [ ! -f $SERVICES_IN_DIR/$1 ];then
    echo "SERVICE $1 was not found in $SERVICES_IN_DIR/$1 !!!"
    exit 1
  fi

  while read line_servgr; do
    [ -z "$line_servgr" ] && continue
    [ "${line_servgr:0:1}" = "#" ] && continue

    while read line; do
      [ -z "$line" ] && continue
      [ "${line:0:1}" = "#" ] && continue

      local SERVICE=$(echo $line | cut -d : -f 1)
      local SERVICE_DESCRIPTION=$(echo $line | cut -d : -f 2)
      local SERVICE_COMMAND=$(echo $line | cut -d : -f 3)
      local SERVICE_NRPE_COMMAND=$(echo $line | cut -d : -f 4,5,6)

      [ "$line_servgr" != "$SERVICE" ] && continue

      IS_CHECK_NRPE=$(echo $SERVICE_COMMAND | grep "check_nrpe!$SERVICE")
      if [ $? -eq 0 ];then
          echo "command[$SERVICE]=$SERVICE_NRPE_COMMAND" >> $DIR_NRPE_OUT/$2.cfg
      fi

      IS_SERVICE=$(cat $DIR_OUT/$SERVICES_FILE | grep "^# $SERVICE$")
      if [ ! $? -eq 0 ];then

cat >> $DIR_OUT/$SERVICES_FILE <<EOF
# $SERVICE
define service {
        use                             local-service
        host_name                       $2
        service_description             $SERVICE_DESCRIPTION
        check_command                   $SERVICE_COMMAND
        }

EOF

# cat $DIR_OUT/$SERVICES_FILE | grep "# $SERVICE"
# exit 1

      else
        # find line to change
        LINE=$(cat $DIR_OUT/$SERVICES_FILE | grep -ni "^# $SERVICE$" | cut -d : -f 1)
        LINE=`expr $LINE + 3`
        [ $? -eq 0 ] || exit 1
        sed -i -e ''$LINE's/$/,'$2'/' $DIR_OUT/$SERVICES_FILE
      fi

    done < $FILE_SERVICES_IN
  done < $SERVICES_IN_DIR/$1

}

function servicegroup_gen() {


  [ $TEMPLATE_TYPE -eq 2 ] && return

  # this is template -> create variable for servis group
  #  [ $TEMPLATE_TYPE -eq 2 ] && return


  MY_SERVICE_GROUP=$1
  MY_HOST=$2

  while read line_servgr; do
    [ -z "$line_servgr" ] && continue
    [ "${line_servgr:0:1}" = "#" ] && continue

    IS_OUR_SERVICE=0
    while read line; do
      [ $IS_OUR_SERVICE -eq 1 ] && continue
      [ -z "$line" ] && continue
      [ "${line:0:1}" = "#" ] && continue

      local SERVICE=$(echo $line | cut -d : -f 1)
      local SERVICE_DESCRIPTION=$(echo $line | cut -d : -f 2)

      if [ "$line_servgr" = "$SERVICE" ];then
        IS_OUR_SERVICE=1
      fi
    done < $FILE_SERVICES_IN

    [ $IS_OUR_SERVICE -eq 0 ] && continue

    IS_SERVICE=$(cat $DIR_OUT/$SERVICE_GROUP_FILE | grep "^# $MY_SERVICE_GROUP$")
    if [ ! $? -eq 0 ];then

      local MY_MEMBERS="$2,$SERVICE_DESCRIPTION"
      if [ $TEMPLATE_TYPE -eq 1 ];then
        MY_MEMBERS=""
        MY_TEMPLATE_SERVICE_GROUPS="${TEMPLATE_CURRENT_NAME}_SERVICE_GROUPS"
        MY_TEMPLATE_SERVICE_GROUPS_VAL="${TEMPLATE_CURRENT_NAME}_${MY_SERVICE_GROUP}_SERVICE_GROUPS_VAL"
        IS_SG=0
        for MY_SG_TMP in ${!MY_TEMPLATE_SERVICE_GROUPS};do
          if [ "$MY_SG_TMP" = "${MY_SERVICE_GROUP}" ];then
            IS_SG=1
            break
          fi
        done
        [ $IS_SG -eq 0 ] && export ${TEMPLATE_CURRENT_NAME}_SERVICE_GROUPS="${!MY_TEMPLATE_SERVICE_GROUPS} ${MY_SERVICE_GROUP}"
        export ${TEMPLATE_CURRENT_NAME}_${MY_SERVICE_GROUP}_SERVICE_GROUPS_VAL="${!MY_TEMPLATE_SERVICE_GROUPS_VAL},<host>,$SERVICE_DESCRIPTION"
      fi
cat >> $DIR_OUT/$SERVICE_GROUP_FILE <<EOF
# $MY_SERVICE_GROUP
define servicegroup {
        servicegroup_name               $MY_SERVICE_GROUP
        alias                           $MY_SERVICE_GROUP
        members                         $MY_MEMBERS
        }

EOF
    else

      if [ $TEMPLATE_TYPE -eq 1 ];then
        MY_TEMPLATE_SERVICE_GROUPS="${TEMPLATE_CURRENT_NAME}_SERVICE_GROUPS"
        MY_TEMPLATE_SERVICE_GROUPS_VAL="${TEMPLATE_CURRENT_NAME}_${MY_SERVICE_GROUP}_SERVICE_GROUPS_VAL"
        IS_SG=0
        for MY_SG_TMP in ${!MY_TEMPLATE_SERVICE_GROUPS};do
          if [ "$MY_SG_TMP" = "${MY_SERVICE_GROUP}" ];then
            IS_SG=1
            break
          fi
        done
        [ $IS_SG -eq 0 ] && export ${TEMPLATE_CURRENT_NAME}_SERVICE_GROUPS="${!MY_TEMPLATE_SERVICE_GROUPS} ${MY_SERVICE_GROUP}"
        export ${TEMPLATE_CURRENT_NAME}_${MY_SERVICE_GROUP}_SERVICE_GROUPS_VAL="${!MY_TEMPLATE_SERVICE_GROUPS_VAL},<host>,$SERVICE_DESCRIPTION"
      else
        LINE=$(cat $DIR_OUT/$SERVICE_GROUP_FILE | grep -ni "^# $MY_SERVICE_GROUP$" | cut -d : -f 1)
        LINE=`expr $LINE + 4`
        sed -i -e ''$LINE's/$/,'"$2,$SERVICE_DESCRIPTION"'/' $DIR_OUT/$SERVICE_GROUP_FILE
      fi
    fi

  done < $SERVICES_IN_DIR/$MY_SERVICE_GROUP

}

function deploy() {

#DEPLOY_NAGIOS_SERVER=$(head -n 1 $FILE_CLUSTER_IN)
#echo "$(tail -n +2 $FILE_CLUSTER_IN | head -n 1)"
DEPLOY_NAGIOS_SERVER=$(cat $FILE_CLUSTER_IN | grep DEPLOY_NAGIOS_SERVER)
DEPLOY_NAGIOS_NRPE_DIR=$(cat $FILE_CLUSTER_IN | grep DEPLOY_NAGIOS_NRPE_DIR)

DEPLOY_NAGIOS_SERVER=${DEPLOY_NAGIOS_SERVER//# DEPLOY_NAGIOS_SERVER=/}
DEPLOY_NAGIOS_NRPE_DIR=${DEPLOY_NAGIOS_NRPE_DIR//# DEPLOY_NAGIOS_NRPE_DIR=/}
DEPLOY_NAGIOS_SERVER=${DEPLOY_NAGIOS_SERVER//\"/}
DEPLOY_NAGIOS_NRPE_DIR=${DEPLOY_NAGIOS_NRPE_DIR//\"/}

if [ -z "$DEPLOY_NAGIOS_SERVER" -o -z "$DEPLOY_NAGIOS_NRPE_DIR" ];then
  echo
  echo -n "Enter nagios server:path (default $DEPLOY_NAGIOS_SERVER)"
  read MY_INPUT
  [ -n "$MY_INPUT" ] && DEPLOY_NAGIOS_SERVER=$MY_INPUT
  echo -n "Enter nrpe path for hosts (default $DEPLOY_NAGIOS_NRPE_DIR)"
  read MY_INPUT
  [ -n "$MY_INPUT" ] && DEPLOY_NAGIOS_NRPE_DIR=$MY_INPUT
fi
echo ""
echo "DEPLOY_NAGIOS_SERVER=$DEPLOY_NAGIOS_SERVER"
echo "DEPLOY_NAGIOS_NRPE_DIR=$DEPLOY_NAGIOS_NRPE_DIR"
echo ""
if [ "$1" != "-f" ];then
  echo -n "Do you want to deploy ? (for deploy press [ENTER] or CTRL-C to cancel)"
  read MY_INPUT
fi
# checking if we can connect
echo -n "Checking ssh to root@$(echo $DEPLOY_NAGIOS_SERVER | cut -d : -f 1)"
ssh root@$(echo $DEPLOY_NAGIOS_SERVER | cut -d : -f 1) echo -n
[ $? -eq 0 ] || exit 10
echo " [OK]"
MY_PSSH_HOSTS=""
for f in $(ls $DIR_NRPE_OUT);do
  MY_PSSH_HOSTS="root@${f//.cfg/} $MY_PSSH_HOSTS"
done

if [ -n "$MY_PSSH_HOSTS" ];then
  echo "Checking ssh to all nrpe servers "
  pssh -O StrictHostKeyChecking=no -H "$MY_PSSH_HOSTS" echo -n
  [ $? -eq 0 ] || exit 11
  echo "Checking ssh to all nrpe servers [OK]"
fi

echo "Copying all config files for nagios server ..."
echo "scp etc/objects/* root@$DEPLOY_NAGIOS_SERVER/objects/"
scp etc/objects/* root@$DEPLOY_NAGIOS_SERVER/objects/
ssh root@$(echo $DEPLOY_NAGIOS_SERVER | cut -d : -f 1) service nagios restart

echo "Copying nrpe configs for all hosts ..."
for f in $(ls $DIR_NRPE_OUT);do
  echo "scp $DIR_NRPE_OUT/$f root@${f//.cfg/}:$DEPLOY_NAGIOS_NRPE_DIR/"
  scp $DIR_NRPE_OUT/$f root@${f//.cfg/}:$DEPLOY_NAGIOS_NRPE_DIR/
done

if [ -n "$MY_PSSH_HOSTS" ];then
  echo "Restarting nrpe on all nrpe hosts ..."
  pssh -O StrictHostKeyChecking=no -H "$MY_PSSH_HOSTS" service nrpe restart
  [ $? -eq 0 ] || exit 12
  echo "Restarting nrpe on all nrpe hosts [OK]"
fi
}

function addHost() {

  # generate hosts
  hosts_gen $MYHOST

  # generate hostgroups
  for gr in $MYGROUPS;do
    hostsgroup_gen $gr $MYHOST
  done

  # generate services
  for service in $MYSERVICES;do
    services_gen_from_group "$service" $MYHOST
    servicegroup_gen "$service" $MYHOST
  done
  # generate services from extra
  for service in $MYSERVICES_EXTRA;do
    services_gen "$service" $MYHOST
  done
}

if [ "$1" = "--deploy-only" ];then
  DEPLOY_ONLY=1
fi

if [ ! -f "$FILE_CLUSTER_IN" ];then
  echo
  echo "Error: file '$FILE_CLUSTER_IN' was not found !!!"
  help
  exit 1
fi

check

if [ $DEPLOY_ONLY -eq 0 ];then

  [ -d $DIR_OUT ] || mkdir -p $DIR_OUT
  rm -rf $DIR_NRPE_OUT
  [ -d $DIR_NRPE_OUT ] || mkdir -p $DIR_NRPE_OUT

  rm -f $DIR_OUT/$HOSTS_FILE
  touch $DIR_OUT/$HOSTS_FILE

  rm -f $DIR_OUT/$HOST_GROUP_FILE
  touch $DIR_OUT/$HOST_GROUP_FILE

  rm -f $DIR_OUT/$SERVICES_FILE
  touch $DIR_OUT/$SERVICES_FILE

  rm -f $DIR_OUT/$SERVICE_GROUP_FILE
  touch $DIR_OUT/$SERVICE_GROUP_FILE


  #MY_TMP_SERV_GROUP=""
  while read line; do
    [ "$line" = "# END" ] && break
    [ -z "$line" ] && continue
    [ "${line:0:1}" = "#" ] && continue

    TEMPLATE_TYPE=0
    TEMPLATE_CURRENT_NAME=""
    if [ "${line:0:5}" = "tmpl_" ];then
      TEMPLATE_TYPE=1
      export TEMPLATE_NAME="$(echo $line | cut -d: -f 1)"
      TEMPLATE_CURRENT_NAME="$TEMPLATE_NAME"
      TEMPLATES="$TEMPLATES $TEMPLATE_NAME"
      export ${TEMPLATE_NAME}_NAME="$TEMPLATE_NAME"
      export ${TEMPLATE_NAME}_LINE="$line"
    fi

    echo "$(date  +%H:%m:%S) $line"
    MYHOST=$(echo $line | cut -d: -f 1)
    MYGROUPS=$(echo $line | cut -d: -f 2)
    MYGROUPS=$(echo ${MYGROUPS//,/ })
    MYSERVICES=$(echo $line | cut -d: -f 3)
    MYSERVICES=$(echo ${MYSERVICES//,/ })
    MYSERVICES_EXTRA=$(echo $line | cut -d: -f 4)
    MYSERVICES_EXTRA=$(echo ${MYSERVICES_EXTRA//,/ })


    MY_TEMPLATE=tmpl_${MYGROUPS}_NAME

    # our host is using already defined template
    if [ -n "${!MY_TEMPLATE}" ];then
      TEMPLATE_TYPE=2
      TEMPLATE_CURRENT_NAME="tmpl_${MYGROUPS}"
      MY_TEMPLATE_HOSTS=tmpl_${MYGROUPS}_HOSTS
      export tmpl_${MYGROUPS}_HOSTS="${!MY_TEMPLATE_HOSTS} $MYHOST"
      MY_TEMPLATE_LINE=tmpl_${MYGROUPS}_LINE
      MYGROUPS=$(echo ${!MY_TEMPLATE_LINE} | cut -d: -f 2)
      MYGROUPS=$(echo ${MYGROUPS//,/ })
    fi

    addHost

  done < $FILE_CLUSTER_IN

  for TMPL in $TEMPLATES;do
    MY_HOSTS=${TMPL}_HOSTS
    MY_HOSTS2=""
    for TMPL_HOST in ${!MY_HOSTS};do
      cp $DIR_NRPE_OUT/$TMPL.cfg $DIR_NRPE_OUT/$TMPL_HOST.cfg
      MY_HOSTS2="$MY_HOSTS2,$TMPL_HOST"
    done
    MY_HOSTS2=${MY_HOSTS2/,/}
    sed -i 's/'$TMPL'/'$MY_HOSTS2'/g' $DIR_OUT/$SERVICES_FILE
    rm $DIR_NRPE_OUT/$TMPL.cfg

    MY_TEMPLATE_SERVICE_GROUPS="${TMPL}_SERVICE_GROUPS"
    for SG in ${!MY_TEMPLATE_SERVICE_GROUPS};do
      for TMPL_HOST in ${!MY_HOSTS};do
        MY_TEMPLATE_SERVICE_GROUPS_VALS="${TMPL}_${SG}_SERVICE_GROUPS_VAL"
        MY_SERVICE_GROUPS_VALS=${!MY_TEMPLATE_SERVICE_GROUPS_VALS}
        MY_SERVICE_GROUPS_VALS=${MY_SERVICE_GROUPS_VALS//<host>/$TMPL_HOST}
        MY_SERVICE_GROUPS_VALS=${MY_SERVICE_GROUPS_VALS/,/}
        LINE=$(cat $DIR_OUT/$SERVICE_GROUP_FILE | grep -ni "^# $SG$" | cut -d : -f 1)
        LINE=`expr $LINE + 4`
        sed -i -e ''$LINE's/$/,'"$MY_SERVICE_GROUPS_VALS"'/' $DIR_OUT/$SERVICE_GROUP_FILE
      done
    done
    sed -i 's/members                         ,/members                         /g' $DIR_OUT/$SERVICE_GROUP_FILE
  done

fi

deploy

RET=0

if [ $RET -eq 1 ];then
  echo "======================================================="
  echo "Error : No changes done (no entries in '$FILE_CLUSTER_IN' )!!!"
  echo "======================================================="
else
  echo "++++++++++"
  echo "Done OK"
  echo "++++++++++"
fi
