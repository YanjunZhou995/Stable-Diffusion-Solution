# Stable-Diffusion-Solution
1. Modify parameters in deploy.sh
```
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
KSA_NAME=k8s-sa \
APP_SA_NAME=stable-diffusion-sa
```
2. Build Docker image of SD.
create artifact repository
```
gcloud artifacts repositories create ${BUILD_REGIST} --repository-format=docker \
--location=${REGION}
```
build container image of sd webui, with Cloud Build
```
cd ./docker
gcloud builds submit --machine-type=e2-highcpu-32 --disk-size=100 --region=${REGION} -t ${REGION}-docker.pkg.dev/${PROJECT_ID}/${BUILD_REGIST}/sd-webui:inference 
```
3. Run deploy.sh, manually running is recommended for customizing your parameters and verifying each step.  
4. Upload model files to GCS bucket in folder "model2". If you use another folder name, remember to modify the "- only-dir" in gcs-pv.yaml
```
  mountOptions:
    - implicit-dirs
    - only-dir=model2
```
5. Configure GCS FUSE with cluster.
Modify gcs-pv, gcs-pvc, sd15-deployment yaml files.
Apply gcs fuse.
```
kubectl apply -f gcs-pv-1.yaml
kubectl apply -f gcs-pvc-1.yaml
kubectl apply -f sd15-deployment1.yaml
```
```
kubectl apply -f gcs-pv-2.yaml
kubectl apply -f gcs-pvc-2.yaml
kubectl apply -f sd15-deployment2.yaml
```
In container terminal, verify the model file in gcs is mounted in the correct path.
```
kubectl exec --stdin --tty $POD_NAME -c stable-diffusion-webui -- /bin/bash
```
6. Configure Horizontal Pod Autoscaling.
create a fixed existing pod in on-demand node pool.
```
kubectl apply -f sd15-deplyment2-static.yaml
```
only allow autoscaling of sd15-deployment2 based on GPU duty cycle.
```
kubectl create clusterrolebinding cluster-admin-binding --clusterrole cluster-admin --user "$(gcloud config get-value account)"
kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/k8s-stackdriver/master/custom-metrics-stackdriver-adapter/deploy/production/adapter_new_resource_model.yaml
```

give monitoring viewer role to app sa.
```
gcloud projects add-iam-policy-binding \
    $PROJECT_ID \
    --member="serviceAccount:$APP_SA_NAME@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/monitoring.viewer"

gcloud iam service-accounts add-iam-policy-binding --role  roles/iam.workloadIdentityUser \
--member "serviceAccount:$PROJECT_ID.svc.id.goog[custom-metrics/custom-metrics-stackdriver-adapter]" $APP_SA_NAME@$PROJECT_ID.iam.gserviceaccount.com

kubectl annotate serviceaccount --namespace custom-metrics \
  custom-metrics-stackdriver-adapter \
  iam.gke.io/gcp-service-account=$APP_SA_NAME@$PROJECT_ID.iam.gserviceaccount.com
```
apply hpa.
```
kubectl apply -f hpa-1.yaml
kubectl apply -f hpa-2.yaml
```
7. Configure load balancer for cluster.
create external load balancer if needed.
```
kubectl apply -f service-1-external-lb.yaml
kubectl apply -f service-2-external-lb.yaml
```

create internal load balancer if needed.
create subnet for proxy.
```
gcloud compute networks subnets create proxy-subnet \
    --purpose=REGIONAL_MANAGED_PROXY \
    --role=ACTIVE \
    --region=$REGION \
    --network=$NETWORK \
    --range=10.1.2.0/23
```
create firewall rules. 
```
gcloud compute firewall-rules create fw-allow-health-check \
    --network=$NETWORK \
    --action=allow \
    --direction=ingress \
    --source-ranges=130.211.0.0/22,35.191.0.0/16 \
    --rules=tcp

CONTAINER_PORT=7860
gcloud compute firewall-rules create proxy-connection \
    --allow=TCP:$CONTAINER_PORT \
    --source-ranges=10.1.2.0/23 \
    --network=$NETWORK
```
apply service and ingress.
```
kubectl apply -f service-2.yaml
kubectl apply -f internal-ingress.yaml
```
verify the ingress is created, need to wait few minutes.
```
kubectl get ingress
```






