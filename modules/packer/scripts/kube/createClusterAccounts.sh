#!/bin/bash

############################################################
############################################################
############   Misc Notes:   ############
## A good idea would be to make a note for where each of these applies in the file
## Im fond of all the notes in one spot vs scattered throughout since they dont apply
##  to the code directly, mainly brainstormed thoughts. Many end up stale after we tried
##  it or figured out a solution though which can cause confusion


#Common error: fatal: unable to access 'https://gitlab-ci-token:token@example.com/repo/proj.git/': Could not resolve host: example.com
#https://docs.gitlab.com/runner/executors/kubernetes.html#fatal-unable-to-access-httpsgitlab-ci-tokentokenexamplecomrepoprojgit-could-not-resolve-host-examplecom
## config option to fix    helper_image_flavor = "ubuntu"

### Start locked&paused is WONDERFUL for the kube runner
### We then have to enable it per project
### Maybe we can supply it with a list of projects, otherwise thats a manual step each time we move gitlab

## SA must be created before register (under normal circumstances)
## https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/#add-imagepullsecrets-to-a-service-account

### Allow namespaced project level service accounts to
###  Deploy to dev, beta, and prod

### Allow environment level service accounts to delete themselves
### OR namespaced project level service accoun to delete
###  environment level service accounts on merge
### -- Surprisingly we still dont have a real solution for NS cleanup
###   I actually think it messes things up if it gets deleted and we push to the same branch name
###   which further causes issues until the cluster runner cache is cleared



## Either A, make account in each NS or in default (empty doesnt make sense anymore)
## Need to test creating the service account in default and making
##  sure it cannot do anything there then see if we can bind it to other namespaces

#### Alternatively, we allow the default account in each namespace to have cluster-admin 
####  privileges and add a kubernetes runner for each of those namespaces.
#### If we get it our kubernetes runner to work correctly we should switch to that model


### == The namespace we provide is where the builder containers are created and 95% sure we confirmed
### ==  the SA must exist in that namespace and a rolebinding isnt enough

############################################################
############################################################

PROD_DEPLOY_ACCOUNT_NAME="deploy"
REVIEW_DEPLOY_ACCOUNT_NAME="review"
RUNNER_HOST_DOMAIN=$(hostname -d)
TAG_LIST="kubernetes"

GL_DEPLOY_FILE_LOCATION=$HOME/.kube/gitlab-deploy-service-account.yaml
GL_REVIEW_FILE_LOCATION=$HOME/.kube/gitlab-review-service-account.yaml
GL_ADMIN_FILE_LOCATION=$HOME/.kube/gitlab-admin-service-account.yaml
GL_NAMESPACE_FILE_LOCATION=$HOME/.kube/gitlab-namespaces.yaml
PUB_CA_FILE_LOCATION=$HOME/.kube/pub-ca.crt

DEPLOY_FROM_NAMESPACE_NAME="deploy"
NAMESPACES_DEFAULTS=( "review" "dev" "beta" "production" )
NAMESPACES=("dev")

RUNNER_TOKEN=""
KUBE_API_HOST_URL=""
KUBE_VERSION="latest"

while getopts "a:d:h:i:l:n:t:v:ru" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        a) KUBE_API_HOST_URL=$OPTARG;;
        d) RUNNER_HOST_DOMAIN=$OPTARG;;
        h) RUNNER_HOST_URL=$OPTARG;;
        i) KUBE_IMAGE=$OPTARG;;
        l) TAG_LIST_EXT=$OPTARG;;
        n) NAMESPACE=$OPTARG;;
        t) RUNNER_TOKEN=$OPTARG;;
        v) KUBE_VERSION=$OPTARG;;
        r) REGISTER="true";;
        u) USE_NAMESPACES_DEFAULTS="true";;
    esac
done

## TODO: Need to convert a string "dev,beta,production" into array


if [[ -z "$RUNNER_TOKEN" ]]; then
    ## Get tmp root password if using fresh instance. Otherwise this fails like it should
    TMP_ROOT_PW=$(sed -rn "s|Password: (.*)|\1|p" /etc/gitlab/initial_root_password)
    RUNNER_TOKEN=$(bash $HOME/code/scripts/misc/getRunnerToken.sh -u root -p $TMP_ROOT_PW -d $RUNNER_HOST_DOMAIN)
fi

if [[ -z "$RUNNER_TOKEN" ]]; then echo "Runner token not provided. Use -t"; exit; fi
if [[ -z "$KUBE_API_HOST_URL" ]]; then echo "Kube host API url not provided. Use -a"; exit; fi

##  -h causes runner host url to ignore the -d option
DEFAULT_RUNNER_HOST_URL="https://gitlab.${RUNNER_HOST_DOMAIN}"
if [[ -n "$RUNNER_HOST_URL" ]]; then DEFAULT_RUNNER_HOST_URL=$RUNNER_HOST_URL; fi

##  -i causes the image to ignore the -d option
DEFAULT_KUBE_IMAGE="registry.codeopensrc.com/os/workbench/kube:$KUBE_VERSION" #ok with this hardcoding atm
if [[ -n "$KUBE_IMAGE" ]]; then DEFAULT_KUBE_IMAGE=$KUBE_IMAGE; fi

if [[ -n "$TAG_LIST_EXT" ]]; then TAG_LIST="${TAG_LIST},${TAG_LIST_EXT}"; fi


if [[ -n "$NAMESPACE" ]]; then NAMESPACES=($NAMESPACE); fi
## This overrides using a single namespace
if [[ -n "$USE_NAMESPACES_DEFAULTS" ]]; then NAMESPACES=${NAMESPACES_DEFAULTS[@]}; fi

## Detect if https:// or port is missing and assume some defaults
PORT_REG=":[0-9]{2,5}$"
if [[ ! $KUBE_API_HOST_URL =~ "https://" ]]; then KUBE_API_HOST_URL="https://${KUBE_API_HOST_URL}"; fi
if [[ ! $KUBE_API_HOST_URL =~ $PORT_REG ]]; then KUBE_API_HOST_URL="${KUBE_API_HOST_URL}:6443"; fi



# 1.
## Create gitlab service account clusterwide
cat <<EOF > $GL_ADMIN_FILE_LOCATION
apiVersion: v1
kind: ServiceAccount
metadata:
  name: gitlab
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: gitlab-admin
subjects:
  - kind: ServiceAccount
    name: gitlab
    namespace: kube-system
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
EOF

kubectl apply -f $GL_ADMIN_FILE_LOCATION



# 2.
## Create namespaces
cat <<EOF > $GL_NAMESPACE_FILE_LOCATION
apiVersion: v1
kind: Namespace
metadata:
  name: $DEPLOY_FROM_NAMESPACE_NAME
  labels:
    name: $DEPLOY_FROM_NAMESPACE_NAME
---
apiVersion: v1
kind: Namespace
metadata:
  name: dev
  labels:
    name: dev
---
apiVersion: v1
kind: Namespace
metadata:
  name: beta
  labels:
    name: beta
---
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    name: production
EOF

kubectl apply -f $GL_NAMESPACE_FILE_LOCATION



### CA_FILE
SECRET=$(kubectl get secrets | grep default-token | cut -d " " -f1)
CERT=$(kubectl get secret ${SECRET} -o jsonpath="{['data']['ca\.crt']}" | base64 --decode)
## Another way
#ANOTHER_CERT=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.certificate-authority-data}' | base64 -d)

## When storing the decoded cert into a bash var it screws with newlines
## Our best alternative is using printf with newlines, but we it splits the space between BEGIN/END CERT
## This illustrates how to deal with it - would like a better way
## NOTE: It appears base64 has a -w0 opton to wrap or not that may solve this problem
FMT1=$(echo $CERT | sed "s|\sCERT|___CERT|g")
printf "%s\n" $FMT1 | sed "s|___CERT| CERT|g" > $PUB_CA_FILE_LOCATION


echo "" > $GL_DEPLOY_FILE_LOCATION
echo "" > $GL_REVIEW_FILE_LOCATION


for NAMESPACE in ${NAMESPACES[@]}; do

    if [[ $NAMESPACE = "review" ]]; then
        DEPLOY_ACCOUNT_NAME=$REVIEW_DEPLOY_ACCOUNT_NAME
        GL_ACCOUNT_FILE_LOCATION=$GL_REVIEW_FILE_LOCATION
        ROLE_TYPE="admin"
        ACCESS_LEVEL="not_protected"
    else
        DEPLOY_ACCOUNT_NAME=$PROD_DEPLOY_ACCOUNT_NAME
        GL_ACCOUNT_FILE_LOCATION=$GL_DEPLOY_FILE_LOCATION
        ROLE_TYPE="cluster-admin"
        ACCESS_LEVEL="ref_protected"
        TAG_LIST="${TAG_LIST/kubernetes/kubernetes_prod}"
    fi

    # 3.
    ## Create service account(s) (Currently doing per NS)
    ## Create a RoleBinding with the ClusterRole cluster-admin/admin privileges in each of the namespaces

    ### Only need account in the 1 namespaces we launch FROM not TO
    ### Prety sure we need an account in the namespace regardless of rolebindings because it attempts to detect
    ###  the permissions of the serviceaccount in the namespace by checking the NAMESPACE itself and NOT ROLEBINDINGS
    ###  for the namespace if im correct
    ### The namespace provided to the runner is where we CREATE the build/runner pods so
    ###  we at least need permissions in each of those namespaces. 
    ### Id like to have 2 service accounts, review and deploy, 4 namespaces, deploy dev beta prod
    ### What I thought is beinding the reiew and deploy account in the appropriate namespaces would be enough
    ### But that only allows to DEPLOY to those namespaces, the service account itself must exist in the namespace
    ###  in order to create pods FROM that namespace, is what im getting as a conclusion
    ### So we dont need a REVIEW namespace because it is gitlab managed and deploys to the respective namespaces

    ### One deploy namespace to launch FROM and dev beta prod namespaces to launch TO and separate the apps
    ### We could technically deploy from default but I feel like thats just bad practice
    ### First rolebinding declares our role in the DEPLOYFROM namespace for DEPLOYACCOUNT 
    ### Second rolebinding declares our role in the DEPLOYTO namespace for DEPLOYACCOUNT

    ###  The second rolebinding is needed because they are NOT "gitlab managed clusters" - This is so we can
    ###   have multiple dev/beta/prod deployments across projects under one namespace - a convention of how we organize apps/runners
    ###   Also our subdomain -> service dns resolving requires a predefined namespace versus dynamic namespaces (the type gitlab gives per project)

    ### === This does bring to attention networking security across namespaces and what they can access since theyre in the same network
    ##  === If we're able to proxy to other pods on the cluster what else can they access

    ## Create accounts and rolebindings in the $DEPLOY_FROM_NAMESPACE_NAME
    ## We use $NAMESPACE as we only want to create 2 accounts and rolebindings here
    if [[ $NAMESPACE = "review" || $NAMESPACE = "dev" ]]; then
	cat <<-EOF >> $GL_ACCOUNT_FILE_LOCATION
	apiVersion: v1
	kind: ServiceAccount
	metadata:
	  name: $DEPLOY_ACCOUNT_NAME
	  namespace: $DEPLOY_FROM_NAMESPACE_NAME
	---
	apiVersion: rbac.authorization.k8s.io/v1
	kind: RoleBinding
	metadata:
	  name: ${DEPLOY_FROM_NAMESPACE_NAME}-${ROLE_TYPE}
	  namespace: $DEPLOY_FROM_NAMESPACE_NAME
	subjects:
	  - kind: ServiceAccount
	    name: $DEPLOY_ACCOUNT_NAME
	    namespace: $DEPLOY_FROM_NAMESPACE_NAME
	roleRef:
	  kind: ClusterRole
	  name: $ROLE_TYPE
	  apiGroup: rbac.authorization.k8s.io
	---
	EOF
    fi

    ## Create rolebindings to deploy to all BUT "review" namespace (which doesnt exist) as gitlab
    ##  is managing all the deploy TO locations for the review service account
    if [[ $NAMESPACE != "review" ]]; then
	cat <<-EOF >> $GL_ACCOUNT_FILE_LOCATION
	apiVersion: rbac.authorization.k8s.io/v1
	kind: RoleBinding
	metadata:
	  name: ${NAMESPACE}-${ROLE_TYPE}
	  namespace: $NAMESPACE
	subjects:
	  - kind: ServiceAccount
	    name: $DEPLOY_ACCOUNT_NAME
	    namespace: $DEPLOY_FROM_NAMESPACE_NAME
	roleRef:
	  kind: ClusterRole
	  name: $ROLE_TYPE
	  apiGroup: rbac.authorization.k8s.io
	---
	EOF
    fi


    kubectl apply -f $GL_ACCOUNT_FILE_LOCATION
    # cli ref #kubectl create rolebinding dev-cluster-admin --clusterrole=cluster-admin --serviceaccount=dev:deploy --namespace=dev


    if [[ $NAMESPACE = "review" || $NAMESPACE = "dev" ]]; then

        ### SERVICE ACCOUNT TOKEN
        SERVICE_TOKEN_TXT=$(kubectl -n $DEPLOY_FROM_NAMESPACE_NAME describe secret $(kubectl -n $DEPLOY_FROM_NAMESPACE_NAME get secret | grep $DEPLOY_ACCOUNT_NAME | awk '{print $1}'))
        SERVICE_TOKEN=$(echo "$SERVICE_TOKEN_TXT" | sed -nr "s/token:\s+(.*)/\1/p")

        sudo gitlab-runner unregister --name "${DEPLOY_ACCOUNT_NAME}-kube-runner"

        ## TODO: These will be default - for testing they are shared atm
            #--locked="false" \
        sudo gitlab-runner register \
            --url "$DEFAULT_RUNNER_HOST_URL" \
            --registration-token "$RUNNER_TOKEN" \
            --non-interactive \
            --executor kubernetes \
            --tag-list "$TAG_LIST" \
            --locked \
            --paused \
            --run-untagged="false" \
            --access-level="$ACCESS_LEVEL" \
            --name "${DEPLOY_ACCOUNT_NAME}-kube-runner" \
            --kubernetes-image "$DEFAULT_KUBE_IMAGE" \
            --kubernetes-pull-policy "always" \
            --kubernetes-host "$KUBE_API_HOST_URL" \
            --kubernetes-namespace "$DEPLOY_FROM_NAMESPACE_NAME" \
            --kubernetes-service-account "$DEPLOY_ACCOUNT_NAME" \
            --kubernetes-bearer_token "$SERVICE_TOKEN" \
            --kubernetes-ca-file "$PUB_CA_FILE_LOCATION"


            #--kubernetes-namespace "$NAMESPACE" \
            #--kubernetes-privileged="" \
            #--kubernetes-namespace_overwrite_allowed "" \
            #--kubernetes-service_account_overwrite_allowed "" \

            #--kubernetes-image-pull-secrets VALUE
            ## --config /tmp/test-config.toml \

        gitlab-runner verify --delete
    fi
done





exit;


########################
## Everything below is new/untested
## Mainly I believe will be how we create a template file to use
########################
########################


## cat <<EOF > $FILE
## [runners.kubernetes]
##   host = "${KUBE_API_HOST_URL}"
##   cert_file = "/etc/ssl/kubernetes/api.crt"
##   key_file = "/etc/ssl/kubernetes/api.key"
##   ca_file = "/etc/ssl/kubernetes/ca.crt"
##   image = "golang:1.8"
## 
## EOF


### A sample TEMPLATE config file - we'll need this to specify namespaces per runner
##   --template-config /tmp/test-config.template.toml \

### $ cat > /tmp/test-config.template.toml << EOF
### [[runners]]
###   [runners.kubernetes]
###     [runners.kubernetes.volumes]
###       [[runners.kubernetes.volumes.empty_dir]]
###         name = "empty_dir"
###         mount_path = "/path/to/empty_dir"
###         medium = "Memory"
### EOF
