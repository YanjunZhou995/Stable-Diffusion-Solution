#!/bin/bash
PROJECT_ID=<project id> \
BUILD_REGIST=<sd-repo name> \
CLUSTER_NAME=<the name of your new cluster> \
SA_NAME="<service account>" \
REGION=<the desired region for your cluster, such as us-central1> \
ZONE=<the desired zone for your node pool, such as us-central1-a> \
NETWORK=default \
MAX_NODES=8 \
MACHINE_TYPE=g2-standard-4 \
DISK_SIZE="100" \
BUCKET_NAME=<sd-model-bucket> \
BUCKET_LOCATION=<US> \
KSA_ROLE=roles/storage.objectAdmin \
KSA_NAME=k8s-sa \
APP_SA_NAME=stable-diffusion-sa

gcloud config set project $PROJECT_ID

echo "start GKE node pool provisioning, cluster name: " $CLUSTER_NAME

#create a cluster with a default node pool
gcloud beta container clusters create $CLUSTER_NAME \
    --region $REGION \
    --node-locations $ZONE \
    --machine-type $MACHINE_TYPE \
    --service-account $SA_NAME \
    --num-nodes 1 \
    --workload-pool=$PROJECT_ID.svc.id.goog \
    --addons GcsFuseCsiDriver \
    --network=$NETWORK \

gcloud container clusters get-credentials $CLUSTER_NAME --region=$REGION

#create on demand and spot node pool for model1
gcloud beta container node-pools create "ondemand-model1" \
    --cluster=$CLUSTER_NAME \
    --region=$REGION \
    --node-locations $ZONE \
    --machine-type=$MACHINE_TYPE \
    --num-nodes 0 \
    --total-min-nodes=0 \
    --total-max-nodes=$MAX_NODES \
    --enable-autoscaling \
    --disk-size $DISK_SIZE \
    --disk-type "pd-ssd" \
    --service-account=$SA_NAME \
    --node-labels=instance-type=ondemand,model=model1 \
    --workload-metadata=GKE_METADATA 

gcloud beta container node-pools create "spot-model1" \
    --cluster=$CLUSTER_NAME \
    --region $REGION \
    --node-locations $ZONE \
    --machine-type $MACHINE_TYPE \
    --num-nodes 0 \
    --total-max-nodes=$MAX_NODES \
    --enable-autoscaling \
    --disk-size $DISK_SIZE \
    --disk-type "pd-ssd" \
    --service-account=$SA_NAME \
    --node-labels=instance-type=spot,model=model1 \
    --workload-metadata=GKE_METADATA \
    --spot

#create on demand and spot node pool for model2
gcloud beta container node-pools create "ondemand-model2" \
    --cluster=$CLUSTER_NAME \
    --region $REGION \
    --node-locations $ZONE \
    --machine-type=$MACHINE_TYPE \
    --num-nodes 0 \
    --total-min-nodes=0 \
    --total-max-nodes=$MAX_NODES \
    --enable-autoscaling \
    --disk-size $DISK_SIZE \
    --disk-type "pd-ssd" \
    --service-account=$SA_NAME \
    --node-labels=instance-type=ondemand,model=model2 \
    --workload-metadata=GKE_METADATA 

gcloud beta container node-pools create "spot-model2" \
    --cluster=$CLUSTER_NAME \
    --region $REGION \
    --node-locations $ZONE \
    --machine-type $MACHINE_TYPE \
    --num-nodes 0 \
    --total-max-nodes=$MAX_NODES \
    --enable-autoscaling \
    --disk-size $DISK_SIZE \
    --disk-type "pd-ssd" \
    --service-account=$SA_NAME \
    --node-labels=instance-type=spot,model=model2 \
    --workload-metadata=GKE_METADATA \
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

#add access to APP SA
gcloud storage buckets add-iam-policy-binding gs://$BUCKET_NAME \
    --member "serviceAccount:$APP_SA_NAME@$PROJECT_ID.iam.gserviceaccount.com" \
    --role $KSA_ROLE

#add iam binding
gcloud iam service-accounts add-iam-policy-binding $APP_SA_NAME@$PROJECT_ID.iam.gserviceaccount.com \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:$PROJECT_ID.svc.id.goog[default/$KSA_NAME]"

#add annotation
kubectl annotate serviceaccount $KSA_NAME \
    --namespace default \
    iam.gke.io/gcp-service-account=$APP_SA_NAME@$PROJECT_ID.iam.gserviceaccount.com
























