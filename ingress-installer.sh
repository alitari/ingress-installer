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
  local exitValue=$4
  (
  echo "XXX" ; echo "waiting for pod ready"; echo "XXX"
  for t in $(seq 1 50);
  do 
      tt=$((t*2))
      echo "$tt" ;
      local exists=$(res_exists "$n" "$r" "$s")
      if [ "$exists" = "$exitValue" ]; then
          break
      else 
          sleep 1
      fi
  done
  ) |
  dialog --title "Waiting..." --gauge "Starte Backup-Script" 8 30
  dialog --clear
}

function helm_install() {
    local repo=$1
    local namespace=$2
    local release=$3
    local charts=$4
    local options=$5
    helm repo add $repo
    helm repo update
    kubectl create ns $namespace || true
    kubectl ns $namespace
    helm upgrade $release $charts --install $options
}

function create_issuer() {
    local name=$1
    local server=$2
    local email=$3
    # | kubectl apply -
    cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1alpha2
kind: Issuer
metadata:
  name: $name
spec:
  acme:
    server: $server
    email: $email
    privateKeySecretRef:
      name: $name
    solvers:
      - http01:
          ingress:
            class: nginx
EOF
}

function create_ingress() {
    local name=$1
    local host=$2
    local service=$3
    local annotation="${4:-}"
    local path="${5:-/}"
    local port="${6:-80}"

    # | kubectl apply -f -
    cat <<EOF
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: $name
  annotations:
    kubernetes.io/ingress.class: "nginx"
    $annotation
spec:
  rules:
    - host: $host
      http:
        paths:
          - path: $path
            backend:
              serviceName: $service
              servicePort: $port
EOF
}


EMAIL_REGEXP="^([A-Za-z]+[A-Za-z0-9]*((\.|\-|\_)?[A-Za-z]+[A-Za-z0-9]*){1,})@(([A-Za-z]+[A-Za-z0-9]*)+((\.|\-|\_)?([A-Za-z]+[A-Za-z0-9]*)+){1,})+\.([A-Za-z]{2,})+$"

HEIGHT=30
WIDTH=120
CHOICE_HEIGHT=20
BACKTITLE="Ingress Installer"
TITLE="Ingress Installer"

for (( ; ; ))
do

CLUSTER_EXT_IP=$(kubectl -n ingress-controller get svc nginx-ingress-controller -ojson --ignore-not-found | jq -r .status.loadBalancer.ingress[0].ip)
IGHR_CTRL=$(res_exists "ingress-controller" "pod" "-l app=nginx-ingress,component=controller --field-selector=status.phase=Running")
CERT_MGR=$(res_exists "ingress-controller" "pod" "-l app=cert-manager")
CERT_ISS=$(res_exists "ingress-controller" "issuers.cert-manager.io" "issuer")
MENU="ingress-controller: $IGHR_CTRL (ingress-ip: $CLUSTER_EXT_IP) , cert-manager: $CERT_MGR , cert-issuer: $CERT_ISS \n
  ingresses: $(kubectl get ingress --all-namespaces --no-headers=true | wc -l)\n\
  Select option:"
OPTIONS=(1 "install ingress controller"
         2 "uninstall ingress controller"
         3 "install cert-manager"
         4 "uninstall cert-manager"
         5 "install cert issuer"
         6 "uninstall cert issuer"
         7 "test"
         9 "list installations"
         r "reload")

CHOICE=$(dialog --colors --clear \
                --backtitle "$BACKTITLE" \
                --title "$TITLE" \
                --menu "$MENU" \
                $HEIGHT $WIDTH $CHOICE_HEIGHT \
                "${OPTIONS[@]}" \
                2>&1 >/dev/tty)

clear
case $CHOICE in
        $DIALOG_CANCEL)
            echo "cancel"
            break
            ;;

        1)
            echo "install ingress controller..."
            helm_install "stable https://kubernetes-charts.storage.googleapis.com" "ingress-controller" "nginx-ingress" "stable/nginx-ingress" ""
            wait_res_exists "ingress-controller" "pod" "-l app=nginx-ingress,component=controller --field-selector=status.phase=Running" "\Z2[X]\Zn"
            ;;
        2)
            echo "uninstall ingress controller..."
            kubectl ns "ingress-controller"
            helm delete "nginx-ingress"
            wait_res_exists "ingress-controller" "pod" "-l app=nginx-ingress,component=controller --field-selector=status.phase=Running" "[ ]"
            ;;
        3)
            echo "install cert-manager..."
            kubectl apply --validate=false -f https://raw.githubusercontent.com/jetstack/cert-manager/release-0.11/deploy/manifests/00-crds.yaml
            helm_install "helm repo add jetstack https://charts.jetstack.io" "ingress-controller" "cert-manager" "jetstack/cert-manager" ""
            ;;
        4)
            echo "uninstall cert-manager..."
            kubectl delete -f https://raw.githubusercontent.com/jetstack/cert-manager/release-0.11/deploy/manifests/00-crds.yaml
            helm delete "cert-manager"
            ;;
        5)
            clear
            echo "install cert issuer..."
            kubectl ns "ingress-controller"
            issuerServer=$(dialog --clear --menu "Issuer server" 9 80 5 "https://acme-staging-v02.api.letsencrypt.org/directory" "(staging - letsencrypt)" "https://acme-v02.api.letsencrypt.org/directory" "(prod - letsencrypt)" 3>&1 1>&2 2>&3)
            if [[ ! -z "$issuerServer" ]]; then
              email=$(dialog --clear --title "Issuer notification email" --inputbox "Email" 8 60 "" 3>&1 1>&2 2>&3)
              if [[ ! $email =~ ${EMAIL_REGEXP} ]]; then
                echo "invalid email: '$email'"
              else 
                create_issuer "issuer" $issuerServer $email
                sleep 5
              fi
            fi
            ;;

        6)
            echo "uninstall cert issuer..."
            kubectl delete issuers.cert-manager.io "issuer"
            ;;
        7)
            echo "install non-secure ingress..."
            # create namespace list
            

            # menu select namespace
            # menu select service

            create_ingress "name" "host" "service"
            sleep 5

            ;;

        9)
            echo "list installations"
            CONTENT="installations: \n=================\n\
$(helm list --all-namespaces --short)\n\n\
ingresses:\n==============\n\
$(kubectl get ingress --all-namespaces --no-headers=true --ignore-not-found -ocustom-columns=NAME:metadata.name,HOST:spec.rules[0].host,BACKEND:spec.rules[0].http.paths[0].backend.serviceName)\n\n"
            dialog --title 'list installations' --msgbox "$CONTENT" $HEIGHT $WIDTH
            ;;
        r)
            ;;
esac
done