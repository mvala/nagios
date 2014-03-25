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

DEPLOY_NAGIOS_SERVER="wiki.saske.sk:/etc/nagios"
DEPLOY_NAGIOS_NRPE_DIR="/etc/nrpe.d"

function help() {
  echo
  echo "usage:"
  echo "       $0 cluster.conf"
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

function hosts_gen() {

  local MYHOST=$1

  if [[ $MYHOST != *$DOMAIN* ]];then
    echo "Error : Host '$MYHOST' doesn't containg '$DOMAIN' !!!"
    exit 10
  fi
  local MYHOST_SHORT="${MYHOST//$DOMAIN/}"
  local MYHOST_IP=$(host $MYHOST | cut -d " " -f 4)

cat >> $DIR_OUT/$HOSTS_FILE <<EOF
define host {
    use        linux-server
    host_name  $MYHOST
    alias      $MYHOST_SHORT
    address    $MYHOST_IP
}

EOF
}

function hostsgroup_gen() {
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
    sed -i -e ''$LINE's/$/,'$2'/' $DIR_OUT/$HOST_GROUP_FILE
  fi
}

function services_gen() {

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
      local SERVICE_NRPE_COMMAND=$(echo $line | cut -d : -f 4)

      [ "$line_servgr" != "$SERVICE" ] && continue

      IS_CHECK_NRPE=$(echo $SERVICE_COMMAND | grep "check_nrpe!$SERVICE")
      if [ $? -eq 0 ];then
          echo "command[$SERVICE]=$SERVICE_NRPE_COMMAND" >> $DIR_NRPE_OUT/$2.cfg
      fi

      IS_SERVICE=$(cat $DIR_OUT/$SERVICES_FILE | grep "# $SERVICE")
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
        LINE=$(cat $DIR_OUT/$SERVICES_FILE | grep -ni "# $SERVICE" | cut -d : -f 1)
        LINE=`expr $LINE + 3`
        sed -i -e ''$LINE's/$/,'$2'/' $DIR_OUT/$SERVICES_FILE
      fi

    done < $FILE_SERVICES_IN
  done < $SERVICES_IN_DIR/$1

}

function servicegroup_gen() {

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

    IS_SERVICE=$(cat $DIR_OUT/$SERVICE_GROUP_FILE | grep "# $MY_SERVICE_GROUP")
    if [ ! $? -eq 0 ];then

cat >> $DIR_OUT/$SERVICE_GROUP_FILE <<EOF
# $MY_SERVICE_GROUP
define servicegroup {
        servicegroup_name               $MY_SERVICE_GROUP
        alias                           $MY_SERVICE_GROUP
        members                         $2,$SERVICE_DESCRIPTION
        }

EOF
    else

      LINE=$(cat $DIR_OUT/$SERVICE_GROUP_FILE | grep -ni "# $MY_SERVICE_GROUP" | cut -d : -f 1)
      LINE=`expr $LINE + 4`
      sed -i -e ''$LINE's/$/,'"$2,$SERVICE_DESCRIPTION"'/' $DIR_OUT/$SERVICE_GROUP_FILE
    fi

  done < $SERVICES_IN_DIR/$MY_SERVICE_GROUP

}

function deploy() {

DEPLOY_NAGIOS_SERVER=$(head -n 1 $FILE_CLUSTER_IN)
DEPLOY_NAGIOS_NRPE_DIR=$(tail -n +2 $FILE_CLUSTER_IN | head -n 1)

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
echo -n "Do you want to deploy ? (for deploy press [ENTER] or CTRL-C to cancel)"
read MY_INPUT

# checking if we can connect
echo -n "Checking ssh to root@$(echo $DEPLOY_NAGIOS_SERVER | cut -d : -f 1)"
ssh root@$(echo $DEPLOY_NAGIOS_SERVER | cut -d : -f 1) echo -n
[ $? -eq 0 ] || exit 10
echo " [OK]"
MY_PSSH_HOSTS=""
for f in $(ls $DIR_NRPE_OUT);do
  MY_PSSH_HOSTS="root@${f//.cfg/} $MY_PSSH_HOSTS"
done
echo "Checking ssh to all nrpe servers "
pssh -H "$MY_PSSH_HOSTS" echo -n
[ $? -eq 0 ] || exit 11
echo "Checking ssh to all nrpe servers [OK]"


echo "Copying all config files for nagios server ..."
echo "scp etc/objects/* root@$DEPLOY_NAGIOS_SERVER/objects/"
scp etc/objects/* root@$DEPLOY_NAGIOS_SERVER/objects/
ssh root@$(echo $DEPLOY_NAGIOS_SERVER | cut -d : -f 1) service nagios restart

echo "Copying nrpe configs for all hosts ..."
for f in $(ls $DIR_NRPE_OUT);do
  echo "scp $DIR_NRPE_OUT/$f root@${f//.cfg/}:$DEPLOY_NAGIOS_NRPE_DIR/"
  scp $DIR_NRPE_OUT/$f root@${f//.cfg/}:$DEPLOY_NAGIOS_NRPE_DIR/
done

echo "Restarting nrpe on all nrpe hosts ..."
pssh -H "$MY_PSSH_HOSTS" service nrpe restart
[ $? -eq 0 ] || exit 12
echo "Restarting nrpe on all nrpe hosts [OK]"

}

if [ -n "$1" ];then
  FILE_CLUSTER_IN="$1"
fi


if [ ! -f "$FILE_CLUSTER_IN" ];then
  echo
  echo "Error: file '$FILE_CLUSTER_IN' was not found !!!"
  help
  exit 1
fi

check

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
  [ -z "$line" ] && continue
  [ "${line:0:1}" = "#" ] && continue

#  echo $line
  MYHOST=$(echo $line | cut -d: -f 1)
  MYGROUPS=$(echo $line | cut -d: -f 2)
  MYGROUPS=$(echo ${MYGROUPS//,/ })
  MYSERVICES=$(echo $line | cut -d: -f 3)
  MYSERVICES=$(echo ${MYSERVICES//,/ })

  hosts_gen $MYHOST
  for gr in $MYGROUPS;do
    hostsgroup_gen $gr $MYHOST
  done
  for service in $MYSERVICES;do
    services_gen "$service" $MYHOST
    servicegroup_gen "$service" $MYHOST
  done

done < $FILE_CLUSTER_IN



#echo
#echo "+++++++++++++++++++++++++++++++++++++"
#echo "File : $DIR_OUT/$HOSTS_FILE"
#echo
#cat $DIR_OUT/$HOSTS_FILE
#echo

#echo "File : $DIR_OUT/$HOST_GROUP_FILE"
#echo
#cat $DIR_OUT/$HOST_GROUP_FILE
#echo

#echo "File : $DIR_OUT/$SERVICES_FILE"
#echo
#cat $DIR_OUT/$SERVICES_FILE
#echo
#echo "+++++++++++++++++++++++++++++++++++++"
#echo

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
