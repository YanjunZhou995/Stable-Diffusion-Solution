# Stable-Diffusion-Solution
1. Modify parameters in deploy.sh
```
PROJECT_ID=xxx
BUILD_REGIST=sd-repo
CLUSTER_NAME=stable-diffusion
SA_NAME="xxxxx-compute@developer.gserviceaccount.com"
REGION=us-central1
ZONE=us-central1-a
MACHINE_TYPE=g2-standard-4
NETWORK=default 
BUCKET_NAME=xxx-bucket # must change the name
BUCKET_LOCATION=US
KSA_NAME=k8s-sa
APP_SA_NAME=stable-diffusion-demo-sa
```
2. Run deploy.sh, manually run is recommended for customizing your parameters and verifying each step.  



