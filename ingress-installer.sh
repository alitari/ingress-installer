#!/bin/bash

function domain_to_cluster() {
  local domain=$1
  local ip=$(dig +short $domain @resolver1.opendns.com)
  if [ "$ip" == "$CLUSTER_EXT_IP" ]; then
    echo "\Z2[X]\Zn"
  else 
    echo "[ ]"
  fi
}

function select_ns() {
  local namespaceList=$(kubectl get ns --field-selector=status.phase=Active --no-headers=true -o=custom-columns=NAME:.metadata.name | awk '{print v++,$1}')
  # menu select namespace
  local number=$(dialog --clear --menu "Select namespace" 30 80 25 $namespaceList 3>&1 1>&2 2>&3)
  if [[ ! -z "$number" ]]; then
    local namespaceArr=($namespaceList)
    local namespace=${namespaceArr[$(( $number*2 + 1))]}
    kubectl ns "$namespace"
  fi
}

function select_service() {
  local namespaceList=$(kubectl get ns --field-selector=status.phase=Active --no-headers=true -o=custom-columns=NAME:.metadata.name | awk '{print v++,$1}')
  # menu select namespace
  local number=$(dialog --clear --menu "Select namespace" 30 80 25 $namespaceList 3>&1 1>&2 2>&3)
  if [[ ! -z "$number" ]]; then
    local namespaceArr=($namespaceList)
    local namespace=${namespaceArr[$(( $number*2 + 1))]}
    kubectl ns "$namespace"
    if [ "$?" -eq "0" ]; then
      # menu select service
      local serviceList=$(kubectl get svc --no-headers=true -o=custom-columns=NAME:.metadata.name | awk '{print v++,$1}')
      local serviceArr=($serviceList)
      if [[ "${#serviceArr[@]}" -eq 0 ]];then 
        echo "ABORT: found no services in namespace '$namespace'"
        sleep 5
      else 
        number=$(dialog --clear --menu "Select service" 30 80 25 $serviceList 3>&1 1>&2 2>&3)
        if [[ ! -z "$number" ]]; then
          SERVICE=${serviceArr[$(( $number*2 + 1))]}
        fi
      fi
    fi
  fi
}

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
    local port="${4:-80}"
    local annotation="${5:-}"
    local path="${6:-/}"
    cat <<EOF | kubectl apply -f -
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

function create_tls_ingress() {
    local name=$1
    local host=$2
    local service=$3
    local port="${4:-80}"
    local annotation="${5:-}"
    local path="${6:-/}"
    cat <<EOF | kubectl apply -f -
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: $name
  annotations:
    kubernetes.io/ingress.class: "nginx"
    cert-manager.io/issuer: "issuer"
    $annotation
spec:
  tls:
    - hosts:
        - $host
      secretName: ${service}-tls
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
HOST_REGEXP="^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]*[a-zA-Z0-9])\.)*([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]*[A-Za-z0-9])$"

HEIGHT=30
WIDTH=140
CHOICE_HEIGHT=20
BACKTITLE="Ingress Installer"
TITLE="Ingress Installer"

NAMESPACE_IGHR_CTRL="ingress-controller"
NAMESPACE_CERT_MGR="cert-manager"

for (( ; ; ))
do

CLUSTER_EXT_IP=$(kubectl -n $NAMESPACE_IGHR_CTRL get svc nginx-ingress-controller -ojson --ignore-not-found | jq -r .status.loadBalancer.ingress[0].ip)
IGHR_CTRL=$(res_exists "$NAMESPACE_IGHR_CTRL" "pod" "-l app=nginx-ingress,component=controller --field-selector=status.phase=Running")
CERT_MGR=$(res_exists "$NAMESPACE_CERT_MGR" "pod" "-l app=cert-manager")
MENU="ingress-controller: $IGHR_CTRL (ingress-ip: $CLUSTER_EXT_IP) , cert-manager: $CERT_MGR \n   Select option:"

OPTIONS=(1 "install ingress controller"
         2 "uninstall ingress controller"
         3 "install cert-manager"
         4 "uninstall cert-manager"
         5 "install cert issuer"
         7 "install non-secure ingress with nip.io domain"
         8 "install tls ingress"
         s "show issuers"
         g "show ingresses"
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
            helm_install "stable https://kubernetes-charts.storage.googleapis.com" "$NAMESPACE_IGHR_CTRL" "nginx-ingress" "stable/nginx-ingress" ""
            # wait_res_exists "$NAMESPACE_IGHR_CTRL" "pod" "-l app=nginx-ingress,component=controller --field-selector=status.phase=Running" "\Z2[X]\Zn"
            ;;
        2)
            kubectl ns "$NAMESPACE_IGHR_CTRL"
            helm delete "nginx-ingress"
            # wait_res_exists "$NAMESPACE_IGHR_CTRL" "pod" "-l app=nginx-ingress,component=controller --field-selector=status.phase=Running" "[ ]"
            kubectl delete ns "$NAMESPACE_IGHR_CTRL"
            ;;
        3)
            kubectl apply --validate=false -f https://raw.githubusercontent.com/jetstack/cert-manager/release-0.11/deploy/manifests/00-crds.yaml
            helm_install "jetstack https://charts.jetstack.io" "$NAMESPACE_CERT_MGR" "cert-manager" "jetstack/cert-manager" ""
            ;;
        4)
            kubectl ns "$NAMESPACE_CERT_MGR"
            kubectl delete -f https://raw.githubusercontent.com/jetstack/cert-manager/release-0.11/deploy/manifests/00-crds.yaml
            helm delete "cert-manager"
            kubectl delete ns "$NAMESPACE_CERT_MGR"
            kubectl delete clusterrole -l app.kubernetes.io/instance=cert-manager
            kubectl delete clusterrolebindings -l app.kubernetes.io/instance=cert-manager
            kubectl -n kube-system delete role -l app.kubernetes.io/instance=cert-manager
            kubectl -n kube-system delete rolebinding -l app.kubernetes.io/instance=cert-manager
            kubectl delete mutatingwebhookconfiguration -l app.kubernetes.io/instance=cert-manager
            kubectl delete validatingwebhookconfiguration -l app.kubernetes.io/instance=cert-manager
            ;;
        5)
            clear
            issuerServer=$(dialog --clear --menu "Issuer server" 9 80 5 "https://acme-staging-v02.api.letsencrypt.org/directory" "(staging - letsencrypt)" "https://acme-v02.api.letsencrypt.org/directory" "(prod - letsencrypt)" 3>&1 1>&2 2>&3)
            if [[ ! -z "$issuerServer" ]]; then
              email=$(dialog --clear --title "Issuer notification email" --inputbox "Email" 8 60 "" 3>&1 1>&2 2>&3)
              if [[ ! $email =~ ${EMAIL_REGEXP} ]]; then
                echo "invalid email: '$email'"
              else 
                select_ns
                create_issuer "issuer" $issuerServer $email
                sleep 5
              fi
            fi
            ;;
        7)
            select_service
            HOST="${SERVICE}.${CLUSTER_EXT_IP}.nip.io"
            PORT=$(kubectl get svc $SERVICE --no-headers=true -o=custom-columns=PORT:.spec.ports[0].port)
            echo "host: $HOST, service: $SERVICE, port: $PORT"
            create_ingress "$SERVICE" "$HOST" "$SERVICE" "$PORT"
            sleep 5
            ;;
        8)
            select_service
            PORT=$(kubectl get svc $SERVICE --no-headers=true -o=custom-columns=PORT:.spec.ports[0].port)
            HOST=$(dialog --clear --title "Host" --inputbox "Host" 8 60 "" 3>&1 1>&2 2>&3)
            if [[ ! $HOST =~ ${HOST_REGEXP} ]]; then
              echo "invalid host name: '$HOST'"
            else 
              create_tls_ingress "$SERVICE" "$HOST" "$SERVICE" "$PORT"
            fi
            sleep 5
            ;;
        s)
            ISSUERS=$(kubectl get issuer --all-namespaces --ignore-not-found )
            dialog --title 'issuers'  --colors --clear --msgbox "$ISSUERS" $HEIGHT $WIDTH
            ;;
        g)
            INGRESSES=$(kubectl get ingress --all-namespaces --no-headers=true --ignore-not-found -ocustom-columns=NAME:metadata.name,HOST:spec.rules[0].host,BACKEND:spec.rules[0].http.paths[0].backend.serviceName \
| while read line ; do \
    read -r -a cols <<< "$line"; \
    dtc=$(domain_to_cluster "${cols[1]}");
    echo "$dtc ${line}\n"; \
 done ;)
            dialog --title 'ingresses'  --colors --clear --msgbox "$INGRESSES" $HEIGHT $WIDTH
            ;;
        r)
            ;;
esac
done