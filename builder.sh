#!/usr/bin/env bash

#################### configs ################
    #clusters
    DEV_CLUSTER_PROVIDER=$(yq .dev-cluster.provider .config/demo-values.yaml)
    DEV_CLUSTER_NAME=$(yq .dev-cluster.name .config/demo-values.yaml)
    STAGE_CLUSTER_PROVIDER=$(yq .stage-cluster.provider .config/demo-values.yaml)
    STAGE_CLUSTER_NAME=$(yq .stage-cluster.name .config/demo-values.yaml)
    PROD_CLUSTER_PROVIDER=$(yq .prod-cluster.provider .config/demo-values.yaml)
    PROD_CLUSTER_NAME=$(yq .prod-cluster.name .config/demo-values.yaml)
    #image registry
    PRIVATE_REPO_SERVER=$(yq .ootb_supply_chain_basic.registry.server .config/tap-values-full.yaml)
    PRIVATE_REPO_USER=$(yq .buildservice.kp_default_repository_username .config/tap-values-full.yaml)
    PRIVATE_REPO_PASSWORD=$(yq .buildservice.kp_default_repository_password .config/tap-values-full.yaml)
    SYSTEM_REPO=$(yq .tap.systemRepo .config/demo-values.yaml)
    #tap
    TANZU_NETWORK_USER=$(yq .buildservice.tanzunet_username .config/tap-values-full.yaml)
    TANZU_NETWORK_PASSWORD=$(yq .buildservice.tanzunet_password .config/tap-values-full.yaml)
    TAP_VERSION=$(yq .tap.version .config/demo-values.yaml)
    APPS_NAMESPACE=$(yq .tap.appNamespace .config/demo-values.yaml)
    #domains
    SYSTEM_SUB_DOMAIN=$(yq .tap_gui.ingressDomain .config/tap-values-full.yaml | cut -d'.' -f 1)
    DEV_SUB_DOMAIN=$(yq .cnrs.domain_name .config/tap-values-full.yaml | cut -d'.' -f 1)
    RUN_SUB_DOMAIN=$(yq .cnrs.domain_name .config/tap-values-run.yaml | cut -d'.' -f 1)
    #misc        
    GW_INSTALL_DIR=$(yq .apis.scgwInstallDirectory .config/demo-values.yaml)

#################### functions ################

    #install-all
    install-all() {

        
        install-tap $DEV_CLUSTER_NAME "tap-values-full.yaml"
       
        install-tap $STAGE_CLUSTER_NAME "tap-values-build.yaml"

        install-tap $PROD_CLUSTER_NAME "tap-values-run.yaml"
        
        add-dekt-supplychain $DEV_CLUSTER_NAME

        update-dns-entries

        update-multi-cluster-views
    }

    #install-localhost
    install-localhost() {

        install-tap $DEV_CLUSTER_NAME "tap-values-localhost.yaml"
        add-dekt-supplychain $DEV_CLUSTER_NAME

        echo
        echo "update gui LB IP values in tap-values-localhost.yaml. hit any key.."
        read

        tanzu package installed update tap --package-name tap.tanzu.vmware.com --version $TAP_VERSION -n tap-install -f .config/tap-values-localhost.yaml
    }

    #install-mac
    install-mac() {

        install-tap $DEV_CLUSTER_NAME "tap-values-laptop.yaml"
    }


    #install-tap
    install-tap () {

        tap_cluster_name=$1
        tap_values_file_name=$2

        echo
        echo "========================================================================"
        echo "Installing TAP on $tap_cluster_name cluster with $tap_values_file_name configs..."
        echo "========================================================================"
        echo

        kubectl config use-context $tap_cluster_name
        kubectl create ns tap-install
       
        tanzu secret registry add tap-registry \
            --username ${TANZU_NETWORK_USER} --password ${TANZU_NETWORK_PASSWORD} \
            --server "registry.tanzu.vmware.com" \
            --export-to-all-namespaces --yes --namespace tap-install

        tanzu package repository add tanzu-tap-repository \
            --url registry.tanzu.vmware.com/tanzu-application-platform/tap-packages:$TAP_VERSION \
            --namespace tap-install

        tanzu package install tap -p tap.tanzu.vmware.com -v $TAP_VERSION \
            --values-file .config/$tap_values_file_name \
            --namespace tap-install

         #setup apps namespace
        kubectl create ns $APPS_NAMESPACE
        tanzu secret registry add registry-credentials --server $PRIVATE_REPO_SERVER --username $PRIVATE_REPO_USER --password $PRIVATE_REPO_PASSWORD -n $APPS_NAMESPACE
        kubectl apply -f .config/supplychain-rbac.yaml -n $APPS_NAMESPACE
    }

    #update-dns-entries
    update-dns-entries() {

        kubectl config use-context $DEV_CLUSTER_NAME
        scripts/ingress-handler.sh update-tap-dns $SYSTEM_SUB_DOMAIN
        scripts/ingress-handler.sh update-tap-dns $DEV_SUB_DOMAIN

        kubectl config use-context $PROD_CLUSTER_NAME
        scripts/ingress-handler.sh update-tap-dns $RUN_SUB_DOMAIN
    }

    #update-multi-cluster-views
    update-multi-cluster-views() {

       echo
       echo "Configure TAP Workloads GUI plugin to support multi-clusters ..."
       echo
       
       kubectl config use-context $STAGE_CLUSTER_NAME
       kubectl apply -f .config/tap-gui-viewer-sa-rbac.yaml
       export buildClusterUrl=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
       export buildClusterToken=$(kubectl -n tap-gui get secret $(kubectl -n tap-gui get sa tap-gui-viewer -o=json \
        | jq -r '.secrets[0].name') -o=json \
        | jq -r '.data["token"]' \
        | base64 --decode)

       yq '.tap_gui.app_config.kubernetes.clusterLocatorMethods.[0].clusters.[0].url = env(buildClusterUrl)' .config/tap-values-full.yaml -i
       yq '.tap_gui.app_config.kubernetes.clusterLocatorMethods.[0].clusters.[0].serviceAccountToken = env(buildClusterToken)' .config/tap-values-full.yaml -i


       kubectl config use-context $DEV_CLUSTER_NAME
       kubectl apply -f .config/tap-gui-viewer-sa-rbac.yaml
       export devClusterUrl=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
       export devClusterToken=$(kubectl -n tap-gui get secret $(kubectl -n tap-gui get sa tap-gui-viewer -o=json \
        | jq -r '.secrets[0].name') -o=json \
        | jq -r '.data["token"]' \
        | base64 --decode)

       yq '.tap_gui.app_config.kubernetes.clusterLocatorMethods.[0].clusters.[1].url = env(devClusterUrl)' .config/tap-values-full.yaml -i
       yq '.tap_gui.app_config.kubernetes.clusterLocatorMethods.[0].clusters.[1].serviceAccountToken = env(devClusterToken)' .config/tap-values-full.yaml -i

       tanzu package installed update tap --package-name tap.tanzu.vmware.com --version $TAP_VERSION -n tap-install -f .config/tap-values-full.yaml

    } 
   
    #add the dekt-path2prod custom supply chain and related components to the context of choice
    add-dekt-supplychain() {
        
        tap_cluster_name=$1
        
        echo
        echo "==============================================================================="
        echo "Add the dekt-path2prod custom supplychain on TAP cluster $tap_cluster_name ..."
        echo "==============================================================================="
        echo
        
        kubectl config use-context $tap_cluster_name

        kubectl apply -f .config/disable-scale2zero.yaml

        #accelerators 
        kustomize build accelerators | kubectl apply -f -

        #dekt-path2prod custom supply chain
        kubectl apply -f .config/dekt-path2prod.yaml

        #scan policy
        kubectl apply -f .config/scan-policy.yaml -n $APPS_NAMESPACE

        #testing pipeline
        kubectl apply -f .config/tekton-pipeline.yaml -n $APPS_NAMESPACE

        #rabbitmq 
        kapp -y deploy --app rmq-operator --file https://github.com/rabbitmq/cluster-operator/releases/download/v1.9.0/cluster-operator.yml
        kubectl apply -f .config/rabbitmq-cluster-config.yaml -n $APPS_NAMESPACE
        kubectl apply -f .config/reading-rabbitmq-instance.yaml -n $APPS_NAMESPACE
    }
    
    #add-apis
    add-apis () {

        kubectl create ns scgw-system

        kubectl create secret docker-registry spring-cloud-gateway-image-pull-secret \
            --docker-server=$PRIVATE_REPO_SERVER \
            --docker-username=$PRIVATE_REPO_USER \
            --docker-password=$PRIVATE_REPO_PASSWORD \
            --namespace scgw-system
 
        relocate-gw-images

        $GW_INSTALL_DIR/scripts/install-spring-cloud-gateway.sh --namespace scgw-system

        #brownfield API
        kubectl create ns brownfield-apis
        kubectl create secret generic sso-credentials --from-env-file=.config/sso-creds.txt -n api-portal
        kustomize build brownfield-apis | kubectl apply -f -

        scripts/ingress-handler.sh add-brownfield-apis $SYSTEM_SUB_DOMAIN
    }

    #relocate-images
    relocate-gw-images() {

        echo "Make sure docker deamon is running..."
        read
        
        docker login $PRIVATE_REPO_SERVER -u $PRIVATE_REPO_USER -p $PRIVATE_REPO_PASSWORD
        
        $GW_INSTALL_DIR/scripts/relocate-images.sh $PRIVATE_REPO_SERVER/$SYSTEM_REPO
    }

    #relocate-tap-images
    relocate-tap-images() {

        echo "Make sure docker deamon is running..."
        read
        
        docker login $PRIVATE_REPO_SERVER -u $PRIVATE_REPO_USER -p $PRIVATE_REPO_PASSWORD

        docker login registry.tanzu.vmware.com -u $TANZU_NETWORK_USER -p $TANZU_NETWORK_PASSWORD
        
        export INSTALL_REGISTRY_USERNAME=$PRIVATE_REPO_USER
        export INSTALL_REGISTRY_PASSWORD=$PRIVATE_REPO_PASSWORD
        export INSTALL_REGISTRY_HOSTNAME=$PRIVATE_REPO_SERVER
        export TAP_VERSION=$TAP_VERSION

        imgpkg copy -b registry.tanzu.vmware.com/tanzu-application-platform/tap-packages:$TAP_VERSION \
            --to-repo ${INSTALL_REGISTRY_HOSTNAME}/$SYSTEM_REPO/tap-packages

    }
    
    #install-gui-dev
    install-gui-dev() {

        kubectl apply -f .config/tap-gui-dev-package.yaml

        export INSTALL_REGISTRY_HOSTNAME=dev.registry.tanzu.vmware.com
        export INSTALL_REGISTRY_USERNAME=$TANZU_NETWORK_USER
        export INSTALL_REGISTRY_PASSWORD=$TANZU_NETWORK_PASSWORD

        tanzu secret registry add dev-registry --username ${INSTALL_REGISTRY_USERNAME} --password ${INSTALL_REGISTRY_PASSWORD} --server ${INSTALL_REGISTRY_HOSTNAME} --export-to-all-namespaces --yes --namespace tap-install

        tanzu package install tap-gui -p tap-gui.tanzu.vmware.com -v 1.1.0-build.1 --values-file .config/tap-gui-values.yaml -n tap-install

        #scripts/ingress-handler.sh gui-dev
        kubectl port-forward service/server 7000 -n tap-gui

        
       
    }
    
    #incorrect usage
    incorrect-usage() {
        
        echo
        echo "Incorrect usage. Please specify one of the following: "
        echo
        echo
        echo "  init"
        echo       
        echo "  apis"
        echo
        echo "  dev"
        echo
        echo "  delete"
        echo
        echo "  relocate-tap-images"
        echo
        echo "  runme [ function-name ]"
        echo
        exit
    }

#################### main ##########################

case $1 in
init)
    case $DEV_CLUSTER_PROVIDER in
    aks)
        scripts/aks-handler.sh create $DEV_CLUSTER_NAME 3
        ;;
    eks)
        scripts/eks-handler.sh create $DEV_CLUSTER_NAME 3
        ;;
    tkg)
        scripts/tkg-handler.sh create $DEV_CLUSTER_NAME 3
        ;;
    minikube)
        scripts/minikube-handler.sh create
        install-mac
        ;;
    *)
        incorrect-usage
        ;;
    esac
    case $STAGE_CLUSTER_PROVIDER in
    aks)
        scripts/aks-handler.sh create $STAGE_CLUSTER_NAME 2
        ;;
    eks)
        scripts/eks-handler.sh create $STAGE_CLUSTER_NAME 2
        ;;
    tkg)
        scripts/tkg-handler.sh create $STAGE_CLUSTER_NAME 2
        ;;
    *)
        incorrect-usage
        ;;
    esac
    case $PROD_CLUSTER_PROVIDER in
    aks)
        scripts/aks-handler.sh create $PROD_CLUSTER_NAME 2
        ;;
    eks)
        scripts/eks-handler.sh create $PROD_CLUSTER_NAME 2
        ;;
    tkg)
        scripts/tkg-handler.sh create $PROD_CLUSTER_NAME 2
        ;;
    *)
        incorrect-usage
        ;;
    esac
    install-all
    ;;
delete)
    echo "!!!Are you sure you want to delete all clusters?"
    read
    ./demo-helper.sh cleanup-helper
    scripts/aks-handler.sh delete $DEV_CLUSTER_NAME
    scripts/aks-handler.sh delete $STAGE_CLUSTER_NAME
    scripts/aks-handler.sh delete $PROD_CLUSTER_NAME
    scripts/eks-handler.sh delete $DEV_CLUSTER_NAME
    scripts/eks-handler.sh delete $STAGE_CLUSTER_NAME
    scripts/eks-handler.sh delete $PROD_CLUSTER_NAME
    #scripts/tkg-handler.sh delete $DEV_CLUSTER_NAME
    #scripts/tkg-handler.sh delete $STAGE_CLUSTER_NAME
    #scripts/tkg-handler.sh delete $PROD_CLUSTER_NAME
    #scripts/minikube-handler.sh delete
    ;;
apis)
    add-apis
    ;;
dev)
    install-gui-dev
    ;;
relocate-tap-images)
    relocate-tap-images
    ;;
runme)
    $2
    ;;
*)
    incorrect-usage
    ;;
esac