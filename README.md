# Stable-Diffusion-Solution
<img width="2550" alt="image" src="https://github.com/YanjunZhou995/Stable-Diffusion-Solution/assets/87971537/2de784c3-f6e7-4c23-aed7-6c4580c2e2fa">
<img width="2552" alt="image" src="https://github.com/YanjunZhou995/Stable-Diffusion-Solution/assets/87971537/26e0a55e-5261-4970-ac90-75ae674623f1">


1. Modify parameters in deploy.sh
```
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
3. Run deploy.sh  
4. Upload model files to GCS bucket in folder "model2". If you use another folder name, remember to modify the "- only-dir" in gcs-pv.yaml
```
  mountOptions:
    - implicit-dirs
    - only-dir=model2
```
5. Configure GCS FUSE in cluster. \
Modify gcs-pv, gcs-pvc, sd15-deployment yaml files. \
Apply gcs fuse.
```
kubectl apply -f gcs-pv-1.yaml
kubectl apply -f gcs-pvc-1.yaml
```
```
kubectl apply -f gcs-pv-2.yaml
kubectl apply -f gcs-pvc-2.yaml
```
create a fixed existing pod in on-demand node pool.
```
kubectl apply -f sd15-deplyment1-static.yaml
kubectl apply -f sd15-deplyment2-static.yaml
```
In container terminal, verify the model file in gcs is mounted in the correct path.
```
kubectl get pod
kubectl exec --stdin --tty $POD_NAME -c stable-diffusion-webui -- /bin/bash
```
6. Configure Horizontal Pod Autoscaling. \
create dynamic deployment, dynamic deployment can be on either on-demand node pool or spot node pool.
```
kubectl apply -f sd15-deployment1-dynamic.yaml
kubectl apply -f sd15-deployment2-dynamic.yaml
```
only allow autoscaling of sd15-deployment2-dynamic based on GPU duty cycle. \
The Horizontal Pod Autoscaler changes the shape of your Kubernetes workload by automatically increasing or decreasing the number of Pods in response to the workload's CPU or memory consumption, or in response to custom metrics reported from within Kubernetes or external metrics from sources outside of your cluster. Install the stackdriver adapter to enable the stable-diffusion deployment scale with GPU usage metrics.
```
kubectl create clusterrolebinding cluster-admin-binding --clusterrole cluster-admin --user "$(gcloud config get-value account)"
kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/k8s-stackdriver/master/custom-metrics-stackdriver-adapter/deploy/production/adapter_new_resource_model.yaml
```

give monitoring viewer role to App SA.
```
gcloud projects add-iam-policy-binding \
    $PROJECT_ID \
    --member="serviceAccount:$APP_SA_NAME@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/monitoring.viewer"

gcloud iam service-accounts add-iam-policy-binding --role  roles/iam.workloadIdentityUser \
--member "serviceAccount:$PROJECT_ID.svc.id.goog[custom-metrics/custom-metrics-stackdriver-adapter]" $APP_SA_NAME@$PROJECT_ID.iam.gserviceaccount.com --project=$PROJECT_ID

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
Create external load balancer.
kubectl apply -f service-1-external-lb.yaml
kubectl apply -f service-2-external-lb.yaml


