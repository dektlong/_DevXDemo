
# Demo of DevX with Tanzu 

This repo contains artifacts to run a demo illustrating the vision and capabilities of Tanzu for Dev, AppOps and Platform Ops

## Preperations 

- AKS and/or EKS access configured, with cluster creation permissions to match the specs in ```scripts/eks-handler.sh``` and ```scripts/aks-handler.sh```
- Rename the folder ```config-template``` to  ```.config``` 

- Update values in the ```.config``` directory

  - ```tap-values```: assumes access to the image registry and domains defined

- Update ```workload/dekt4pets``` folder to match ```tap-values```

  - ```image:``` value in ```backend/dekt4pets-backend.yml```

  - ```serverUrl:``` value in ```gateway/dekt4pets-gatway.yml``` and ```gateway/dekt4pets-gatway-dev.yml```

- Update ```host:``` value in ```workload/brownfield-apis``` files to match ```tap-values```

- The ingress setup is based on GoDaddy DNS, if you are using a different one, please modify ```scripts/ingress-handler.sh```

## Installation

### Core

- run ```./builder.sh init [aks / eks]``` to install the following:

- install TAP with the following packages
    - Clound Native Runtime
    - App Accelerator
    - App Live View
    - API Portal
    - Build Service
    - Supply Chain components
    - Image metadata store
    - Image policy webhook
    - Scan controller
    - Grype scanner
    - Spring Cloud Gateway (via HELM)
- install the following Demo examples
      - App Accelerators
      - Source-to-image supply-chain 
      - DevXMood workload
      - brownfield APIs
- setup dns and ingress rules 

### Add API-grid specific setup
- ```./api-grid.sh```
- create the ```dekt4pets-backend``` and ```dekt4pets-frontend``` images
- setup SSO and app configs 

## Running the demo 

### Core 

- access tap gui accelerators dev-cloudnative tag
  - create DevX-sensors workload using the boot-backend accelerator 
  - create the DevX-portal workload using the web-function accelerator 
  - use DevX-mood-app as the parent application in both cases

- access the api-portal and highlight how discovery of existing APIs prior to creating new ones is done 
- highlight the simplicity of the workload.yaml 

- show the simple tap installed command (don't actually run)
  - tanzu package install tap -p tap.tanzu.vmware.com -v 1.0.1  --values-file tap-values.yaml -n tap-install

- show all the packages installed on 
  - tanzu package installed list -n tap-install

- create workloads 
  - tanzu apps workload create -f workloads/devx-mood/mood-sensors.yaml -y
  - tanzu apps workload create -f workloads/devx-mood/mood-portal.yaml -y

- follow workload creation 
  - tanzu apps workload list -n dekt-apps

- access tap gui accelerators devops-cloudnative tag
  - create source-to-api supplychain using the microservices-supplychain accelerator with web-backend workload type 
  - create source-to-api supplychain using the microservices-supplychain accelerator with web-frontend workload type

- highlight the separation of concerns between supplychain (AppOps) and supplychain-templates (Platform Ops)

- show applied supply chains 
  - tanzu apps cluster-supply-chain list
  - Note! The source-to-api supplychain is not active, the sensor is using the source-to-url as well 
 

- show supply chain and build service behind the scenes 
  - tanzu apps workload get mood-sensors -n dekt-apps
  - tanzu apps workload tail mood-sensors --since 100m --timestamp  -n dekt-apps

- access the live url of portal workload and show the call back to the sensors APIs 

- register a new entity in tap backstage gui
  - https://github.com/dektlong/_DevXDemo/blob/main/workloads/devx-mood/backstage/catalog-info.yaml
  - show system view via DevX-mood-app
  - click down on DevX-sensors to show application live view

- make a code change in DevX-portal app to bypass the backend api calls 
  - https://github.com/dektlong/devx-mood/main.go , change ALWAYS_HAPPY flag to true 
  - show how supply chain pickup the change and re run the path to prod
    - tanzu apps workload get mood-portal -n dekt-apps
  - show a happy dog with sensors ignored

### API-grid specific example
- deploy dekt4pets-backend ```./api-grid.sh backend```   
  - show in api-portal dekt4pets-dev item added in real time  and how the front end team can discover and re-use backend APIs  

- deploy dekt4pets-frontend  ```./api-grid.sh frontend``` 
  - show in api portal how the frontend routes are added in real time 
- deploy a production  gateway with ingress access ```./api-grid.sh dekt4pets```
- Note! these apps are not using tap supply chain 

## Cleanup

- full cleanup to delete the cluster  ```./builder.sh cleanup [aks/eks]```

- partial cleanup to remove just workloads ```./builder.sh reset```

# Enjoy!
