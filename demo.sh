#!/usr/bin/env bash

#################### load configs from values yaml  ################

    VIEW_CLUSTER=$(yq .clusters.view.name .config/demo-values.yaml)
    DEV_CLUSTER=$(yq .clusters.dev.name .config/demo-values.yaml)
    STAGE_CLUSTER=$(yq .clusters.stage.name .config/demo-values.yaml)
    PROD1_CLUSTER=$(yq .clusters.prod1.name .config/demo-values.yaml)
    PROD2_CLUSTER=$(yq .clusters.prod2.name .config/demo-values.yaml)
    BROWNFIELD_CLUSTER=$(yq .clusters.brownfield.name .config/demo-values.yaml)
    PRIVATE_CLUSTER=$(yq .brownfield_apis.privateClusterContext .config/demo-values.yaml)
    PORTAL_WORKLOAD="mood-portal"
    SENSORS_WORKLOAD="mood-sensors"
    MEDICAL_WORKLOAD="mood-doctor"
    PREDICTOR_WORKLOAD="mood-predictor"
    DEV1_WORKLOAD="myportal"
    DEV2_WORKLOAD="mysensors"
    DEV_SUB_DOMAIN=$(yq .dns.devSubDomain .config/demo-values.yaml)
    PROD1_SUB_DOMAIN=$(yq .dns.prod1SubDomain .config/demo-values.yaml)
    PROD2_SUB_DOMAIN=$(yq .dns.prod2SubDomain .config/demo-values.yaml)
    DOMAIN=$(yq .dns.domain .config/demo-values.yaml)
    TAP_VERSION=$(yq .tap.tapVersion .config/demo-values.yaml)
    DEV1_NAMESPACE=$(yq .apps_namespaces.dev1 .config/demo-values.yaml)
    DEV2_NAMESPACE=$(yq .apps_namespaces.dev2 .config/demo-values.yaml)
    TEAM_NAMESPACE=$(yq .apps_namespaces.team .config/demo-values.yaml)
    STAGEPROD_NAMESPACE=$(yq .apps_namespaces.stageProd .config/demo-values.yaml)
    SNIFF_THRESHOLD_MILD=15
    SNIFF_THRESHOLD_AGGRESSIVE=50
    PREDICTOR_IMAGE=$(yq .private_registry.host .config/demo-values.yaml)/isvs/$(yq .tap.isvImg .config/demo-values.yaml)
    IMAGE_SCAN_TEMPLATE_PORTAL=$(yq .tap.imageScanPortal .config/demo-values.yaml)
    IMAGE_SCAN_TEMPLATE_SENSORS=$(yq .tap.imageScanSensors .config/demo-values.yaml)
    IMAGE_SCAN_TEMPLATE_DOCTOR=$(yq .tap.imageScanDoctor .config/demo-values.yaml)
    IMAGE_SCAN_TEMPLATE_PREDICTOR=$(yq .tap.imageScanPredictor .config/demo-values.yaml)
    

    

#################### functions ################

    #info
    info () {

        scripts/dektecho.sh info "One API Install"
        
        echo "  tanzu package install tap"
        echo "      --package tap.tanzu.vmware.com"
        echo "      --version $TAP_VERSION"
        echo "      --values-file .config/tap_values.yaml"
        echo "      --namespace tap-install"
        
        scripts/dektecho.sh info "View cluster (TAP 'view' profile)"
        kubectl config use-context $VIEW_CLUSTER
        kubectl cluster-info | grep 'control plane' --color=never
        tanzu package installed list -n tap-install

        scripts/dektecho.sh info "Dev-Test cluster (TAP 'intereate' profile)"
        kubectl config use-context $DEV_CLUSTER 
        kubectl cluster-info | grep 'control plane' --color=never
        tanzu package installed list -n tap-install
        
        scripts/dektecho.sh info "Staging cluster (TAP 'build' profile)"
        kubectl config use-context $STAGE_CLUSTER 
        kubectl cluster-info | grep 'control plane' --color=never
        tanzu package installed list -n tap-install

        scripts/dektecho.sh info "Production cluster $PROD1_CLUSTER (TAP 'run' profile)"
        kubectl config use-context $PROD1_CLUSTER 
        kubectl cluster-info | grep 'control plane' --color=never
        tanzu package installed list -n tap-install

        scripts/dektecho.sh info "Production cluster $PROD2_CLUSTER (TAP 'run' profile)"
        kubectl config use-context $PROD2_CLUSTER 
        kubectl cluster-info | grep 'control plane' --color=never
        tanzu package installed list -n tap-install

        addBrownfield=$(kubectl config get-contexts | grep $BROWNFIELD_CLUSTER)
        if [ -z "$addBrownfield" ]
        then
            echo ""
        else
            scripts/dektecho.sh info "Social cluster (access via tanzu service mesh)"
            kubectl config use-context $BROWNFIELD_CLUSTER 
            kubectl cluster-info | grep 'control plane' --color=never

            scripts/dektecho.sh info "Private cluster (access via tanzu service mesh)"
            kubectl config use-context $PRIVATE_CLUSTER
            kubectl cluster-info | grep 'control plane' --color=never
        fi

        kubectl config use-context $DEV_CLUSTER 

    }
    
    #create-dev-workloads
    create-dev-workloads() {

        #bitnami postgreSQL inventory db
        scripts/dektecho.sh cmd "tanzu service class-claim create inventory --class postgresql-unmanaged --parameter storageGB=2 -n $TEAM_NAMESPACE"
        tanzu service class-claim create inventory --class postgresql-unmanaged --parameter storageGB=2  -n $TEAM_NAMESPACE

        #bitnami rabbitmq reading queue
        scripts/dektecho.sh cmd "tanzu service class-claim create reading --class rabbitmq-unmanaged --parameter replicas=2 --parameter storageGB=1 -n $TEAM_NAMESPACE"
        tanzu service class-claim create reading --class rabbitmq-unmanaged --parameter replicas=2 --parameter storageGB=1 -n $TEAM_NAMESPACE
        
        #dev1 workload
        scripts/dektecho.sh cmd "tanzu apps workload create $DEV1_WORKLOAD -f .config/workloads/mood-portal.yaml -y -n $DEV1_NAMESPACE"
        tanzu apps workload create $DEV1_WORKLOAD -f .config/workloads/mood-portal.yaml \
            -y -n $DEV1_NAMESPACE

        #dev2 workload
        scripts/dektecho.sh cmd "tanzu apps workload create $DEV2_WORKLOAD -f .config/workloads/mood-sensors.yaml -y -n $DEV2_NAMESPACE"
         tanzu apps workload create  $DEV2_WORKLOAD -f .config/workloads/mood-sensors.yaml \
            --param-yaml testing_pipeline_matching_labels='{"apps.tanzu.vmware.com/language": "java"}' \
            -y -n $DEV2_NAMESPACE

        #portal workload
        scripts/dektecho.sh cmd "tanzu apps workload create $PORTAL_WORKLOAD -f .config/workloads/mood-portal.yaml -y -n $TEAM_NAMESPACE"
        sensorsActivateAPI="http://mood-sensors.$DEV_SUB_DOMAIN.$DOMAIN/activate"
        sensorsMeasureeAPI="http://mood-sensors.$DEV_SUB_DOMAIN.$DOMAIN/measure"
        tanzu apps workload create $PORTAL_WORKLOAD -f .config/workloads/mood-portal.yaml \
            --env SNIFF_THRESHOLD=$SNIFF_THRESHOLD_AGGRESSIVE \
            --env SENSORS_ACTIVATE_API=$sensorsActivateAPI \
            --env SENSORS_MEASURE_API=$sensorsMeasureeAPI \
            -y -n $TEAM_NAMESPACE

        #sensors workload
        scripts/dektecho.sh cmd "tanzu apps workload create $SENSORS_WORKLOAD -f .config/workloads/mood-sensors.yaml -y -n $TEAM_NAMESPACE"
         tanzu apps workload create $SENSORS_WORKLOAD -f .config/workloads/mood-sensors.yaml \
            -y -n $TEAM_NAMESPACE

        #doctor workload
        scripts/dektecho.sh cmd "tanzu apps workload create $MEDICAL_WORKLOAD -f .config/workloads/mood-doctor.yaml -y -n $TEAM_NAMESPACE"
        tanzu apps workload create $MEDICAL_WORKLOAD -f .config/workloads/mood-doctor.yaml \
            -y -n $TEAM_NAMESPACE

        #predictor workload 
        scripts/dektecho.sh cmd "tanzu apps workload create $PREDICTOR_WORKLOAD -f .config/workloads/mood-predictor.yaml -y -n $TEAM_NAMESPACE"
        tanzu apps workload create $PREDICTOR_WORKLOAD -f .config/workloads/mood-predictor.yaml \
            --image $PREDICTOR_IMAGE \
            -y -n $TEAM_NAMESPACE
        
    }

    #create-stage-workloads
    create-stage-workloads() {

        #RDS postgreSQL inventory db
        scripts/dektecho.sh cmd "tanzu service class-claim create inventory --class aws-rds-psql -p storageGB=30 -n $STAGEPROD_NAMESPACE"
        tanzu service class-claim create inventory --class aws-rds-psql -p storageGB=30 -n $STAGEPROD_NAMESPACE

        #bitnami rabbitmq reading queue
        scripts/dektecho.sh cmd "tanzu service class-claim create reading --class rabbitmq-unmanaged --parameter replicas=2 -n $STAGEPROD_NAMESPACE"
        tanzu service class-claim create reading --class rabbitmq-unmanaged --parameter replicas=2 --parameter storageGB=1 -n $STAGEPROD_NAMESPACE

        #portal workload
        scripts/dektecho.sh cmd "tanzu apps workload create $PORTAL_WORKLOAD-$PROD1_SUB_DOMAIN -f .config/workloads/mood-portal.yaml -y -n $STAGEPROD_NAMESPACE"
        sensorsActivateAPI="http://mood-sensors.$PROD1_SUB_DOMAIN.$DOMAIN/activate"
        sensorsMeasureeAPI="http://mood-sensors.$PROD1_SUB_DOMAIN.$DOMAIN/measure"
        tanzu apps workload create $PORTAL_WORKLOAD -f .config/workloads/mood-portal.yaml \
            --env SNIFF_THRESHOLD=$SNIFF_THRESHOLD_MILD \
            --env SENSORS_ACTIVATE_API=$sensorsActivateAPI \
            --env SENSORS_MEASURE_API=$sensorsMeasureeAPI \
            --param scanning_image_template=$IMAGE_SCAN_TEMPLATE_PORTAL \
            -y -n $STAGEPROD_NAMESPACE

        #sensors workload
        scripts/dektecho.sh cmd "tanzu apps workload create $SENSORS_WORKLOAD -f .config/workloads/mood-sensors.yaml -y -n $STAGEPROD_NAMESPACE"
        tanzu apps workload create $SENSORS_WORKLOAD -f .config/workloads/mood-sensors.yaml \
            --param scanning_image_template=$IMAGE_SCAN_TEMPLATE_SENSORS \
            -y -n $STAGEPROD_NAMESPACE

        #doctor workload
        scripts/dektecho.sh cmd "tanzu apps workload create $MEDICAL_WORKLOAD -f .config/workloads/mood-doctor.yaml -y -n $STAGEPROD_NAMESPACE"
        tanzu apps workload create $MEDICAL_WORKLOAD -f .config/workloads/mood-doctor.yaml  \
        --param scanning_image_template=$IMAGE_SCAN_TEMPLATE_DOCTOR \
            -y -n $STAGEPROD_NAMESPACE

        #predictor workload
        scripts/dektecho.sh cmd "tanzu apps workload create $PREDICTOR_WORKLOAD -f .config/workloads/mood-predictor.yaml -y -n $STAGEPROD_NAMESPACE"
        tanzu apps workload create $PREDICTOR_WORKLOAD -f .config/workloads/mood-predictor.yaml \
        --param scanning_image_template=$IMAGE_SCAN_TEMPLATE_PREDICTOR \
            --image $PREDICTOR_IMAGE \
            -y -n $STAGEPROD_NAMESPACE
        
    }

    #prod-roleout
    prod-roleout () {

        scripts/dektecho.sh status "Pulling workloads deliverables from $STAGE_CLUSTER cluster"
        kubectl config use-context $STAGE_CLUSTER
        kubectl get configmap $PORTAL_WORKLOAD-deliverable -n $STAGEPROD_NAMESPACE -o go-template='{{.data.deliverable}}' > .config/workloads/$PORTAL_WORKLOAD-deliverable.yaml
        kubectl get configmap $SENSORS_WORKLOAD-deliverable -n $STAGEPROD_NAMESPACE -o go-template='{{.data.deliverable}}' > .config/workloads/$SENSORS_WORKLOAD-deliverable.yaml
        kubectl get configmap $MEDICAL_WORKLOAD-deliverable -n $STAGEPROD_NAMESPACE -o go-template='{{.data.deliverable}}' > .config/workloads/$MEDICAL_WORKLOAD-deliverable.yaml
        
        scripts/dektecho.sh prompt  "Deliverables created. Press 'y' to continue deploying to production clusters" && [ $? -eq 0 ] || exit
        
        kubectl config use-context $PROD1_CLUSTER
        scripts/dektecho.sh status "Creating data services in $PROD1_CLUSTER production cluster..."
        tanzu service class-claim create inventory --class aws-rds-psql -p storageGB=30 -n $STAGEPROD_NAMESPACE
        tanzu service class-claim create reading --class rabbitmq-unmanaged --parameter replicas=2 --parameter storageGB=1 -n $STAGEPROD_NAMESPACE
        scripts/dektecho.sh status "Applying workloads deliverables to $PROD1_CLUSTER production cluster..."
        kubectl apply -f .config/workloads/$PORTAL_WORKLOAD-deliverable.yaml -n $STAGEPROD_NAMESPACE
        kubectl apply -f .config/workloads/$SENSORS_WORKLOAD-deliverable.yaml -n $STAGEPROD_NAMESPACE
        kubectl apply -f .config/workloads/$MEDICAL_WORKLOAD-deliverable.yaml -n $STAGEPROD_NAMESPACE

        kubectl config use-context $PROD2_CLUSTER
        scripts/dektecho.sh status "Creating data services in $PROD2_CLUSTER production cluster..."
        tanzu service class-claim create inventory --class aws-rds-psql -p storageGB=30 -n $STAGEPROD_NAMESPACE
        tanzu service class-claim create reading --class rabbitmq-unmanaged --parameter replicas=2 --parameter storageGB=1 -n $STAGEPROD_NAMESPACE
        scripts/dektecho.sh status "Applying workloads deliverables to $PROD2_CLUSTER production cluster..."
        kubectl apply -f .config/workloads/$PORTAL_WORKLOAD-deliverable.yaml -n $STAGEPROD_NAMESPACE
        kubectl apply -f .config/workloads/$SENSORS_WORKLOAD-deliverable.yaml -n $STAGEPROD_NAMESPACE
        kubectl apply -f .config/workloads/$MEDICAL_WORKLOAD-deliverable.yaml -n $STAGEPROD_NAMESPACE
        
        scripts/dektecho.sh status "Your DevX-Mood application is being deployed to production"

    }

    #supplychains
    supplychains () {

        scripts/dektecho.sh cmd "tanzu apps cluster-supply-chain list"
        
        tanzu apps cluster-supply-chain list
    }

    #track-workloads
    track-workloads () {

        tapCluster=$1
        appsNamespace=$2
        showLogs=$3
        

        kubectl config use-context $tapCluster

        scripts/dektecho.sh cmd "tanzu apps workload get $PORTAL_WORKLOAD -n $appsNamespace"
        tanzu apps workload get $PORTAL_WORKLOAD -n $appsNamespace

        scripts/dektecho.sh cmd "tanzu apps workload get $MEDICAL_WORKLOAD -n $appsNamespace"
        tanzu apps workload get $MEDICAL_WORKLOAD -n $appsNamespace

        scripts/dektecho.sh cmd "tanzu apps workload get $SENSORS_WORKLOAD -n $appsNamespace"
        tanzu apps workload get $SENSORS_WORKLOAD -n $appsNamespace
        
        if [ "$showLogs" == "logs" ]; then
            scripts/dektecho.sh cmd "tanzu apps workload tail $SENSORS_WORKLOAD --since 100m --timestamp  -n $appsNamespace"
            
            tanzu apps workload tail $SENSORS_WORKLOAD --since 100m --timestamp  -n $appsNamespace
        fi
    }

    
    #brownfield
    brownfield () {

        scripts/dektecho.sh info "Brownfield CONSUMER services"

        scripts/dektecho.sh cmd "kubectl get svc -n brownfield-apis"
        kubectl config use-context $DEV_CLUSTER
        kubectl get svc -n brownfield-apis
        kubectl config use-context $STAGE_CLUSTER
        kubectl get svc -n brownfield-apis
        kubectl config use-context $PROD1_CLUSTER
        kubectl get svc -n brownfield-apis
        kubectl config use-context $PROD2_CLUSTER
        kubectl get svc -n brownfield-apis

        scripts/dektecho.sh info "Brownfield PROVIDERS services"
        kubectl config use-context $BROWNFIELD_CLUSTER 
        kubectl get svc -n brownfield-apis
        
    }

    #soft reset of all clusters configurations
    reset() {

        kubectl config use-context $STAGE_CLUSTER
        tanzu apps workload delete $MEDICAL_WORKLOAD -n $STAGEPROD_NAMESPACE -y
        tanzu apps workload delete $PREDICTOR_WORKLOAD -n $STAGEPROD_NAMESPACE -y
        tanzu apps workload delete $PORTAL_WORKLOAD -n $STAGEPROD_NAMESPACE -y
        tanzu apps workload delete $SENSORS_WORKLOAD -n $STAGEPROD_NAMESPACE -y
        
        tanzu service class-claim delete reading -y -n $STAGEPROD_NAMESPACE
        tanzu service class-claim delete inventory -y -n $STAGEPROD_NAMESPACE
        kubectl delete -f .config/data-services/rds-postgres/inventory-db-rds-instance.yaml -n $STAGEPROD_NAMESPACE
        kubectl delete -f .config/data-services/tanzu/reading-instance-tanzu_rabbitmq.yaml -n $STAGEPROD_NAMESPACE

        kubectl config use-context $PROD1_CLUSTER
        kubectl delete deliverables/$PORTAL_WORKLOAD -n $STAGEPROD_NAMESPACE
        kubectl delete deliverables/$SENSORS_WORKLOAD -n $STAGEPROD_NAMESPACE
        kubectl delete deliverables/$MEDICAL_WORKLOAD -n $STAGEPROD_NAMESPACE
        tanzu service class-claim delete reading -y -n $STAGEPROD_NAMESPACE
        tanzu service class-claim delete inventory -y -n $STAGEPROD_NAMESPACE

        kubectl config use-context $PROD2_CLUSTER
        kubectl delete deliverables/$PORTAL_WORKLOAD -n $STAGEPROD_NAMESPACE
        kubectl delete deliverables/$SENSORS_WORKLOAD -n $STAGEPROD_NAMESPACE
        kubectl delete deliverables/$MEDICAL_WORKLOAD -n $STAGEPROD_NAMESPACE
        tanzu service class-claim delete reading -y -n $STAGEPROD_NAMESPACE
        tanzu service class-claim delete inventory -y -n $STAGEPROD_NAMESPACE
        
        kubectl config use-context $DEV_CLUSTER
        tanzu apps workload delete $MEDICAL_WORKLOAD -n $TEAM_NAMESPACE -y
        tanzu apps workload delete $PREDICTOR_WORKLOAD -n $TEAM_NAMESPACE -y
        tanzu apps workload delete $PORTAL_WORKLOAD -n $TEAM_NAMESPACE -y
        tanzu apps workload delete $SENSORS_WORKLOAD -n $TEAM_NAMESPACE -y
        tanzu apps workload delete $DEV1_WORKLOAD -n $DEV1_NAMESPACE -y
        tanzu apps workload delete $DEV2_WORKLOAD -n $DEV2_NAMESPACE -y
        tanzu service class-claim delete reading -y -n $TEAM_NAMESPACE
        tanzu service class-claim delete inventory -y -n $TEAM_NAMESPACE
        tanzu service class-claim delete reading -y -n $DEV1_NAMESPACE
        tanzu service class-claim delete inventory -y -n $DEV1_NAMESPACE

        rm .config/workloads/$PORTAL_WORKLOAD-deliverable.yaml
        rm .config/workloads/$SENSORS_WORKLOAD-deliverable.yaml
        rm .config/workloads/$MEDICAL_WORKLOAD-deliverable.yaml

        ./builder.sh update-tap multicluster
    }

    #reset-prod
    reset-prod () {

        clusterName=$1

        kubectl config use-context $clusterName
       
      
    }

    #incorrect usage
    incorrect-usage() {
        
        echo
        scripts/dektecho.sh err "Incorrect usage. Please specify one of the following: "
        echo
        echo "  info"
        echo
        echo "  dev"
        echo
        echo "  stage"
        echo
        echo "  prod"
        echo
        echo "  supplychains"
        echo
        echo "  track team/stage [logs]"
        echo
        echo "  services dev/team/stage"
        echo
        echo "  brownfield"
        echo
        echo "  behappy"
        echo
        echo "  uninstall"
        exit
    }

#################### main ##########################

case $1 in
info)
    info
    ;;
dev)
    kubectl config use-context $DEV_CLUSTER
    create-dev-workloads
    ;;
stage)
    kubectl config use-context $STAGE_CLUSTER
    create-stage-workloads
    ;;
prod)
    prod-roleout
    ;;
behappy)
    kubectl config use-context $DEV_CLUSTER
    tanzu apps workload apply $PORTAL_WORKLOAD --env SNIFF_THRESHOLD=$SNIFF_THRESHOLD_MILD -n $TEAM_NAMESPACE -y
    ;;   
besad)
    kubectl config use-context $DEV_CLUSTER
    tanzu apps workload apply $PORTAL_WORKLOAD --env SNIFF_THRESHOLD=$SNIFF_THRESHOLD_AGGRESSIVE -n $TEAM_NAMESPACE -y
    ;;
supplychains)
    supplychains
    ;;
services)
    case $2 in
    dev)
        data-services $DEV_CLUSTER $DEV1_NAMESPACE tanzu
        ;;
    team)
        data-services $DEV_CLUSTER $TEAM_NAMESPACE tanzu
        ;;
    stage)
        data-services $STAGE_CLUSTER $STAGEPROD_NAMESPACE rds
        ;;
    prod)
        data-services $PROD1_CLUSTER $STAGEPROD_NAMESPACE rds
        data-services $PROD2_CLUSTER $STAGEPROD_NAMESPACE rds
        ;;
    *)
        incorrect-usage
        ;;
    esac
    ;;
track)
    case $2 in
    team)
        track-workloads $DEV_CLUSTER $TEAM_NAMESPACE $3
        ;;
    stage)
        track-workloads $STAGE_CLUSTER $STAGEPROD_NAMESPACE $3
        ;;
    *)
        incorrect-usage
        ;;
    esac
    ;;
brownfield)
    brownfield
    ;;
reset)
    reset
    ;;
cleanup-helper)
    cleanup-helper
    ;;
*)
    incorrect-usage
    ;;
esac
