#!/bin/bash
PROJECT_ID=tidal-memento-371114 \
BUILD_REGIST=sd-repo \
CLUSTER_NAME=stable-diffusion-zyj \
SA_NAME="986038904910-compute@developer.gserviceaccount.com" \
REGION=us-central1 \
ZONE=us-central1-c \
MACHINE_TYPE=g2-standard-4 \
NETWORK=default \
BUCKET_NAME=sd-model-bucket \
BUCKET_LOCATION=US \
KSA_NAME=k8s-sa \
APP_SA_NAME=stable-diffusion-tf-sa

gcloud config set project $PROJECT_ID

#create artifact repository
gcloud artifacts repositories create ${BUILD_REGIST} --repository-format=docker \
--location=${REGION}

#build container image of sd webui
cd ./docker
#option1: Build Docker image locally (machine with at least 8GB memory avaliable)
#gcloud auth configure-docker ${REGION}-docker.pkg.dev
#docker build . -t ${REGION}-docker.pkg.dev/${PROJECT_ID}/${BUILD_REGIST}/sd-webui:inference
#docker push 

#option2: Build image with Cloud Build
gcloud builds submit --machine-type=e2-highcpu-32 --disk-size=100 --region=${REGION} -t ${REGION}-docker.pkg.dev/${PROJECT_ID}/${BUILD_REGIST}/sd-webui:inference 


echo "start GKE node pool provisioning, cluster name: " $CLUSTER_NAME

#create a network and subnet for the backend cluster
gcloud compute networks create $NETWORK --subnet-mode=custom
gcloud compute networks subnets create backend-subnet \
    --network=$NETWORK \
    --range=10.128.0.0/20 \
    --region=$REGION

#default node pool
gcloud beta container clusters create $CLUSTER_NAME \
    --region $REGION \
    --node-locations $ZONE \
    --machine-type g2-standard-4 \
    --service-account $SA_NAME \
    --num-nodes 1 \
    --workload-pool=$PROJECT_ID.svc.id.goog \
    --addons GcsFuseCsiDriver \
    --network=$NETWORK \
    --scopes=https://www.googleapis.com/auth/monitoring


gcloud container clusters get-credentials $CLUSTER_NAME --region=$REGION

#create on demand and spot node pool for model1
gcloud beta container node-pools create "ondemand-model1" \
    --cluster=$CLUSTER_NAME \
    --region=$REGION \
    --node-locations $ZONE \
    --machine-type=$MACHINE_TYPE \
    --num-nodes 0 \
    --total-min-nodes=0 \
    --total-max-nodes=8 \
    --enable-autoscaling \
    --disk-size "100" \
    --disk-type "pd-ssd" \
    --service-account=$SA_NAME \
    --node-labels=instance-type=ondemand,model=model1 \
    --workload-metadata=GKE_METADATA \
    --scopes=https://www.googleapis.com/auth/monitoring


gcloud beta container node-pools create "spot-model1" \
    --cluster=$CLUSTER_NAME \
    --region $REGION \
    --node-locations $ZONE \
    --machine-type $MACHINE_TYPE \
    --num-nodes 0 \
    --total-max-nodes=8 \
    --enable-autoscaling \
    --disk-size "100" \
    --disk-type "pd-ssd" \
    --service-account=$SA_NAME \
    --node-labels=instance-type=spot,model=model1 \
    --workload-metadata=GKE_METADATA \
    --scopes=https://www.googleapis.com/auth/monitoring \
    --spot

#create on demand and spot node pool for model2
gcloud beta container node-pools create "ondemand-model2" \
    --cluster=$CLUSTER_NAME \
    --region $REGION \
    --node-locations $ZONE \
    --machine-type=$MACHINE_TYPE \
    --num-nodes 0 \
    --total-min-nodes=0 \
    --total-max-nodes=8 \
    --enable-autoscaling \
    --disk-size "100" \
    --disk-type "pd-ssd" \
    --service-account=$SA_NAME \
    --node-labels=instance-type=ondemand,model=model2 \
    --workload-metadata=GKE_METADATA \
    --scopes=https://www.googleapis.com/auth/monitoring

gcloud beta container node-pools create "spot-model2" \
    --cluster=$CLUSTER_NAME \
    --region $REGION \
    --node-locations $ZONE \
    --machine-type $MACHINE_TYPE \
    --num-nodes 0 \
    --total-max-nodes=8 \
    --enable-autoscaling \
    --disk-size "100" \
    --disk-type "pd-ssd" \
    --service-account=$SA_NAME \
    --node-labels=instance-type=spot,model=model2 \
    --workload-metadata=GKE_METADATA \
    --scopes=https://www.googleapis.com/auth/monitoring \
    --spot


gcloud container node-pools delete default-pool --region $REGION --cluster=$CLUSTER_NAME --quiet

#daemonset to install GPU driver
kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/container-engine-accelerators/master/nvidia-driver-installer/cos/daemonset-preloaded-latest.yaml

###connect to gcs 
#create a gcs bucket
gcloud storage buckets create gs://$BUCKET_NAME --location=$BUCKET_LOCATION

#get the credentials of the cluster
gcloud container clusters get-credentials $CLUSTER_NAME \
    --region $REGION

#K8s SA
kubectl create serviceaccount $KSA_NAME \
    --namespace default

#App SA
gcloud iam service-accounts create $APP_SA_NAME \
    --project=$PROJECT_ID

#add access to APP SA, "--role" can be customized
gcloud storage buckets add-iam-policy-binding gs://$BUCKET_NAME \
    --member "serviceAccount:$APP_SA_NAME@$PROJECT_ID.iam.gserviceaccount.com" \
    --role roles/storage.objectAdmin

#add iam binding
gcloud iam service-accounts add-iam-policy-binding $APP_SA_NAME@$PROJECT_ID.iam.gserviceaccount.com \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:$PROJECT_ID.svc.id.goog[default/$KSA_NAME]"

#add annotation
kubectl annotate serviceaccount $KSA_NAME \
    --namespace default \
    iam.gke.io/gcp-service-account=$APP_SA_NAME@$PROJECT_ID.iam.gserviceaccount.com

#apply gcs fuse
kubectl apply -f gcs-pv-2.yaml
kubectl apply -f gcs-pvc-2.yaml
kubectl apply -f sd15-deployment2.yaml

#In container, verify the model file in gcs is mounted in the correct path
#进入容器终端，验证gcs里的文件是否mount到正确路径
#kubectl exec --stdin --tty $POD_NAME -c stable-diffusion-webui -- /bin/bash

### create external load balancer if needed
kubectl apply -f service-2-external-lb.yaml

### create internal load balancer
#create subnet for proxy
gcloud compute networks subnets create proxy-subnet \
    --purpose=REGIONAL_MANAGED_PROXY \
    --role=ACTIVE \
    --region=$REGION \
    --network=$NETWORK \
    --range=10.1.2.0/24

#create firewall rules 
gcloud compute firewall-rules create fw-allow-health-check \
    --network=$NETWORK \
    --action=allow \
    --direction=ingress \
    --source-ranges=130.211.0.0/22,35.191.0.0/16 \
    --rules=tcp

CONTAINER_PORT=7860
gcloud compute firewall-rules create proxy-connection \
    --allow=TCP:$CONTAINER_PORT \
    --source-ranges=10.1.2.0/24 \
    --network=$NETWORK

kubectl apply -f service-2.yaml
kubectl apply -f internal-ingress.yaml
#need to wait few minutes
kubectl get ingress


#configure horizontal pod autoscaling
#create a fixed existing pod in on-demand node pool
kubectl apply -f sd15-deplyment2-static.yaml
#only allow autoscaling of sd15-deployment2 based on GPU duty cycle
#1. verify scope
gcloud container clusters describe $CLUSTER_NAME --region $REGION

#2. for workload identity
gcloud iam service-accounts add-iam-policy-binding --role  roles/iam.workloadIdentityUser \
--member "serviceAccount:$PROJECT_ID.svc.id.goog[custom-metrics/custom-metrics-stackdriver-adapter]" \
$APP_SA_NAME@$PROJECT_ID.iam.gserviceaccount.com

kubectl annotate serviceaccount --namespace custom-metrics \
  custom-metrics-stackdriver-adapter \
  iam.gke.io/gcp-service-account=$APP_SA_NAME@$PROJECT_ID.iam.gserviceaccount.com

kubectl create clusterrolebinding cluster-admin-binding --clusterrole cluster-admin --user "$(gcloud config get-value account)"
kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/k8s-stackdriver/master/custom-metrics-stackdriver-adapter/deploy/production/adapter_new_resource_model.yaml
kubectl apply -f hpa-2.yaml















