#!/bin/bash
PROJECT_ID=<your project id>
CLUSTER_NAME=stable-diffusion-cluster
REGION=us-central1
ZONE=(us-central1-a us-central1-b us-central1-c)
NETWORK=default 
MAX_NODES=8 
MACHINE_TYPE=g2-standard-4 
DISK_SIZE="100" 
BUCKET_NAME=$PROJECT_ID-stable-diffusion
BUCKET_LOCATION=$REGION
KSA_ROLE=roles/storage.objectAdmin 
KSA_NAME=k8s-sa 
APP_SA_NAME=stable-diffusion-sa

gcloud config set project $PROJECT_ID

echo "start GKE node pool provisioning, cluster name: " $CLUSTER_NAME

#create a cluster with a default node pool
gcloud beta container clusters create $CLUSTER_NAME \
    --region $REGION \
    --node-locations $ZONE \
    --machine-type $MACHINE_TYPE \
    --num-nodes 1 \
    --workload-pool=$PROJECT_ID.svc.id.goog \
    --addons GcsFuseCsiDriver \
    --network=$NETWORK \

gcloud container clusters get-credentials $CLUSTER_NAME --region=$REGION

for zone in ${ZONE[@]}; do
    echo "create on demand node pool for zone $zone"
    gcloud beta container node-pools create "ondemand-$zone" \
        --cluster=$CLUSTER_NAME \
        --region=$REGION \
        --node-locations $zone \
        --machine-type=$MACHINE_TYPE \
        --num-nodes 0 \
        --total-min-nodes=0 \
        --total-max-nodes=$MAX_NODES \
        --enable-autoscaling \
        --disk-size $DISK_SIZE \
        --disk-type "pd-ssd" \
        --node-labels=instance-type=ondemand \
        --workload-metadata=GKE_METADATA 
    
    echo "create spot node pool for zone $zone"
    gcloud beta container node-pools create "spot-$zone" \
        --cluster=$CLUSTER_NAME \
        --region $REGION \
        --node-locations $zone \
        --machine-type $MACHINE_TYPE \
        --num-nodes 0 \
        --total-max-nodes=$MAX_NODES \
        --enable-autoscaling \
        --disk-size $DISK_SIZE \
        --disk-type "pd-ssd" \
        --node-labels=instance-type=spot \
        --workload-metadata=GKE_METADATA \
        --spot
done

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
