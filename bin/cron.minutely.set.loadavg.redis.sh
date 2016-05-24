#!/bin/bash

set -u -e

minute=`date +%M`

usage() {
  echo "Usage:
  l First arg: Redis key to set the loadav e.g. 'cron:loadavg'
  l More args: Redis database numbers on the local instance in which to set this key.
  l e.g. 'cron:loadavg' 13 14 # will set on Redis databases 13 and 14
  " | sed 's/^\s\s*l //g'
}

rhabort() {
  [ -t 1 ] && >&2 echo "ABORT rhSetLoadAvgKey $*" && usage
  return $1
}

rhSetLoadAvgKey() {
  [ $# -ge 1 ] || rhabort 3 'args'
  key=`echo "$1" | grep '^\w\S*$'` || rhabort 4 "Invalid key [$1]"
  [ -n "$key" ] || rhabort 5 "Key validation failed [$1]"
  shift || rhabort 6 "No database numbers"
  for databaseNumber in "$@"
  do
    if echo "$databaseNumber" | grep -qv '^[0-9][0-9]*$'
    then
      rhabort 7 "Invalid database number: [$databaseNumber]"
    fi
  done
  while [ `date +%M` -eq $minute ]
  do
    local loadavgInteger=`cat /proc/loadavg | cut -d'.' -f1 | grep '^[0-9][\.0-9]*$'`
    if [ -n "$loadavgInteger" ]
    then
      for databaseNumber in "$@"
      do
         [ -t 1 ] && echo "redis-cli -n $databaseNumber setex $key 90 $loadavgInteger"
        if redis-cli -n $databaseNumber setex $key 90 $loadavgInteger | grep -v '^OK'
        then
          rhabort 13 'Unexpected reply'
        fi
      done
      [ -t 1 ] && echo "Sleeping for 13 seconds"
      sleep 13
    fi
  done
}

rhSetLoadAvgKey "$@"
