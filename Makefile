PROJECT_ID=banded-meridian-435911-g6
ZONE=us-east4-a
VM_PATH=/srv/app
REPO_URL=https://github.com/markbosire/youtubbe-clone-gcp.git

run-local:
	docker-compose up 

###

create-tf-backend-bucket:
	gcloud storage buckets create gs://$(PROJECT_ID)-tderraform --project=$(PROJECT_ID)

### 

ENV=staging
terraform-create-workspace: 
	cd terraform && \
		terraform workspace new $(ENV)

### 

terraform-init: 
	cd terraform && \
		terraform workspace select $(ENV) && \
		terraform init
TF_ACTION?=plan
terraform-action:
	cd terraform && \
		terraform workspace select $(ENV) && \
		terraform $(TF_ACTION) \
		-var-file="./environments/common.tfvars" \
		-var-file="./environments/$(ENV)/config.tfvars" \

APP_NAME=youtube
VM_NAME=$(APP_NAME)-vm-$(ENV)
GITHUB_SHA?=latest
LOCAL_TAG_BACKEND=youtube-backend:$(GITHUB_SHA)
LOCAL_TAG_FRONTEND=youtube-frontend:$(GITHUB_SHA)
REMOTE_TAG_BACKEND=gcr.io/$(PROJECT_ID)/$(LOCAL_TAG_BACKEND)
REMOTE_TAG_FRONTEND=gcr.io/$(PROJECT_ID)/$(LOCAL_TAG_FRONTEND)

CONTAINER_NAME_BACKEND=youtube-backend
CONTAINER_NAME_FRONTEND=youtube-frontend


ssh:
	gcloud compute ssh --zone $(ZONE) --project $(PROJECT_ID) $(VM_NAME)

ssh-cmd: 
	gcloud compute ssh --zone $(ZONE) --project $(PROJECT_ID) --command "$(CMD)" $(VM_NAME) 


build:
	docker compose build

push:
	docker tag $(LOCAL_TAG_BACKEND) $(REMOTE_TAG_BACKEND)
	docker push $(REMOTE_TAG_BACKEND)
	docker tag $(LOCAL_TAG_FRONTEND) $(REMOTE_TAG_FRONTEND)
	docker push $(REMOTE_TAG_FRONTEND)


deploy: 
	# Pull the latest code on the VM
	$(MAKE) ssh-cmd CMD='\
		if [ -d $(VM_PATH) ]; then \
			cd $(VM_PATH) && git pull; \
		else \
			git clone $(REPO_URL) $(VM_PATH); \
		fi'

	# Configure Docker credentials on the VM for Google Container Registry access
	$(MAKE) ssh-cmd CMD='docker-credential-gcr configure-docker'
	$(MAKE) ssh-cmd CMD='docker stop $(docker ps -q) || true'
	$(MAKE) ssh-cmd CMD='docker rm $(docker ps -a -q) || true'
	
	# Pull the latest image on the VM
	@echo "Pulling latest container images..."
	$(MAKE) ssh-cmd CMD='cd $(VM_PATH) && docker pull $(REMOTE_TAG)'

	# Restart containers using docker-compose
	@echo "Deploying new container versions..."
	$(MAKE) ssh-cmd CMD='cd $(VM_PATH) && docker-compose down && docker-compose up -d'