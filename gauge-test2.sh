#!/bin/bash
function res_exists() {
  local namespace=$1
  local resource=$2
  local selector=$3
  local count=$(kubectl -n $namespace get $resource $selector --ignore-not-found --no-headers=true | wc -l)
  if [ "$count" -eq "0" ]; then
    echo "[ ]"
  else 
    echo "\Z2[X]\Zn"
  fi
}

function wait_res_exists() {
  local n=$1
  local r=$2
  local s=$3
  (
  echo "XXX" ; echo "waiting for pod ready"; echo "XXX"
  for t in $(seq 1 10);
  do 
      tt=$((t*10))
      echo "$tt" ;
      local exists=$(res_exists "$n" "$r" "$s")
      if [ ! "$exists" = "[ ]" ]; then
          break
      else 
          sleep 1
      fi
  done
  ) |
  dialog --title "Fortschrittszustand" --gauge "Starte Backup-Script" 8 30
  dialog --clear
}


wait_res_exists "ingress-controller" "pod" "-l app=nginx-ingress,component=controller --field-selector=status.phase=Running"

# DIALOG=dialog
# (
# echo "XXX" ; echo "waiting for pod ready"; echo "XXX"
# for t in $(seq 1 10);
# do 
#     tt=$((t*10))
#     echo "$tt" ;
#     IGHR_CTRL=$(res_exists "ingress-controller" "pod" "-l app=nginx-ingress,component=controller --field-selector=status.phase=Running")
#     if [ ! "$IGHR_CTRL" = "[ ]" ]; then
#         break
#     else 
#         sleep 1
#     fi
# done
# ) |
# $DIALOG --title "Fortschrittszustand" --gauge "Starte Backup-Script" 8 30
# $DIALOG --clear
# $DIALOG --msgbox "Arbeit erfolgreich beendet ..." 0 0
# $DIALOG --clear
# clear

