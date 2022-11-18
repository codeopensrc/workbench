#!/bin/bash

AGENT_NAME_DEFAULTS=( "review" "dev" "beta" "production" )

## For conveniece and so it is not required to keep a PAT available, we create a temp
##  PAT and revoke it at the bottom
TOKEN_UUID=`uuidgen`
TEMP_PAT=""
if [[ -z $TEMP_PAT ]]; then
    sudo gitlab-rails runner "token = User.find(1).personal_access_tokens.create(scopes: [:api], name: 'Temp PAT'); token.set_token('$TOKEN_UUID'); token.save!";
else
    TOKEN_UUID=$TEMP_PAT
fi

while getopts "d:n:u" flag; do
    # These become set during 'getopts'  --- $OPTIND $OPTARG
    case "$flag" in
        d) DOMAIN=$OPTARG;;
        n) AGENT_NAME=$OPTARG;;
        u) USE_DEFAULTS="true";;
    esac
done


if [[ -z "$DOMAIN" ]]; then echo "Domain not provided. Use -d"; exit; fi

GL_API_URL="https://gitlab.${DOMAIN}/api/v4"
GITLAB_AGENT_PROJECT_NAME="gitlab-cluster-agent"
GITLAB_AGENT_PROJECT_ID=""

if [[ -z "$USE_DEFAULTS" ]]; then
    if [[ -z "$AGENT_NAME" ]]; then echo "AGENT name not provided. Use -n"; exit; fi
    AGENT_NAMES=($AGENT_NAME)
else
    AGENT_NAMES=${AGENT_NAME_DEFAULTS[@]}
fi

## Check projects for agent management project id
## If found, delete old agents TODO: Do this more gracefully like matching names, only delete tokens etc.
## Else create the project

## In case the project name changes etc.
## Probably need to use topics but ensure its the correct project
#ACCETABLE_PROJECT_NAMES=( "$GITLAB_AGENT_PROJECT_NAME" )
QUERY_PARAMS="?simple=true&search=$GITLAB_AGENT_PROJECT_NAME"
GITLAB_AGENT_PROJECT_ID=$(curl --silent -X GET -H "PRIVATE-TOKEN: ${TOKEN_UUID}" \
    --url "$GL_API_URL/projects$QUERY_PARAMS" \
    | jq '.[] | select(.path == "'$GITLAB_AGENT_PROJECT_NAME'") | .id')

if [[ -n $GITLAB_AGENT_PROJECT_ID ]]; then
    ## When migrating GitLab instances/clusters, need to remove old agents

    ## List agents
    #GET /projects/:id/cluster_agents
    #curl --header "Private-Token: <your_access_token>" "https://gitlab.example.com/api/v4/projects/20/cluster_agents"

    ## Get their tokens
    #GET /projects/:id/cluster_agents/:agent_id/tokens
    #curl --header "Private-Token: <your_access_token>" "https://gitlab.example.com/api/v4/projects/20/cluster_agents/5/tokens"

    ## Delete the tokens
    #DELETE /projects/:id/cluster_agents/:agent_id/tokens/:token_id
    #curl --request DELETE --header "Private-Token: <your_access_token>" "https://gitlab.example.com/api/v4/projects/20/cluster_agents/5/tokens/1"

    ###
    ## OOORRR We just delete and re-create the agents
    ###

    ## List agents
    #GET /projects/:id/cluster_agents
    AGENT_LIST=$(curl --silent -H "PRIVATE-TOKEN: ${TOKEN_UUID}" \
        --url "$GL_API_URL/projects/$GITLAB_AGENT_PROJECT_ID/cluster_agents" | jq -r ".[].id" )

    ## Delete agents
    #DELETE /projects/:id/cluster_agents/:agent_id
    for AGENT_ID in ${AGENT_LIST[@]}; do
        echo "ID IS: $AGENT_ID"
        curl --silent -X DELETE -H "PRIVATE-TOKEN: ${TOKEN_UUID}" \
            --url "$GL_API_URL/projects/$GITLAB_AGENT_PROJECT_ID/cluster_agents/$AGENT_ID"
    done

    ###TODO: Possibly config whether to update existing projects agents access file with possibly updated agent names
    ## ie. existing project has 2-3 agents, new config

else
    DATA='{"path": "'${GITLAB_AGENT_PROJECT_NAME}'", 
            "description": "Project to manage gitlab k8s agents",
            "operations_access_level": "enabled",
            "snippets_enabled": "true",
            "snippets_access_level": "enabled",
            "builds_access_level": "private",
            "auto_devops_enabled": "false",
            "container_registry_access_level": "disabled",
            "packages_enabled": "false",
            "releases_access_level": "disabled",
            "analytics_access_level": "disabled",
            "security_and_compliance_access_level": "disabled",
            "visibility": "public",
            "initialize_with_readme": "true"}'

    #"topics": "[]",
    #"jobs_enabled": "false",       jobs need to be enabled for Infra > Kubernetes section to appear
    #"snippets_enabled": "true",    To make it private in 15.5.3, needs to be "enabled"

    ## Create project
    GITLAB_AGENT_PROJECT_ID=$(curl --silent -X POST -H "PRIVATE-TOKEN: ${TOKEN_UUID}" \
        -H "Content-Type: application/json" \
        --data "${DATA}" \
        --url "$GL_API_URL/projects/" | jq -r ".id")

    echo "Wait 5 for repo to be created"
    sleep 5;

    ## .gitlab/agents/AGENT_NAME/config.yaml   for each agent
    ## This create human-readable format, and converts newlines to literal newlines for json upload
	AGENT_ACCESS_FILE=$(cat <<-EOF | perl -p -e 's/\n/\\n/'
	ci_access:
	  groups:
	    - id: root
	EOF
	)
    ### Ok if for same user/group
    #ci_access:
    #  projects:
    #    - id: project-name

    for AGENT_NAME in ${AGENT_NAMES[@]}; do
        echo "COMMITING AGENT: $AGENT_NAME"

        PAYLOAD='{ "branch": "main", "content": "'${AGENT_ACCESS_FILE}'",
            "commit_message": "Add agent: '${AGENT_NAME}'" }'
        FILE_RES=$(curl -X POST -H "PRIVATE-TOKEN: ${TOKEN_UUID}" \
            -H "Content-Type: application/json" \
            --data "${PAYLOAD}" \
            --url "$GL_API_URL/projects/${GITLAB_AGENT_PROJECT_ID}/repository/files/%2Egitlab%2Fagents%2F${AGENT_NAME}%2Fconfig%2Eyaml")
        echo "$FILE_RES"

        echo "Wait 2 for next agent"
        sleep 2;
    done
fi


## Add gitlab-agent chart
helm repo add gitlab https://charts.gitlab.io
helm repo update

## Register multiple agents and install via helm
for AGENT_NAME in ${AGENT_NAMES[@]}; do
    ## Register agent
    echo "AGENT_NAME: $AGENT_NAME"

    AGENT_ID=$(curl --silent -X POST -H "PRIVATE-TOKEN: ${TOKEN_UUID}" \
        -H "Content-Type: application/json" \
        --data '{ "name": "'${AGENT_NAME}'" }' \
        --url "$GL_API_URL/projects/$GITLAB_AGENT_PROJECT_ID/cluster_agents" \
        | jq -r .id)

    # Create a token for that agent and retrieve it to install in the cluster
    # Use AGENT_TOKEN to install agent with helm chart
    AGENT_TOKEN=$(curl --silent -X POST -H "PRIVATE-TOKEN: ${TOKEN_UUID}" \
        -H "Content-Type: application/json" \
        --data '{ "name": "'${AGENT_NAME}'" }' \
        --url "$GL_API_URL/projects/$GITLAB_AGENT_PROJECT_ID/cluster_agents/$AGENT_ID/tokens" \
        | jq -r .token)

    ## By default the agent has cluster-admin ClusterRoleBinding
    ## set rbac.create=false to not attach the cluster role
    ## We'll create and attach our own roles to each agent like we do runners
    ## For now our RBAC should essentially mimic the cert-based approached but without the gitlab-admin role
    #https://gitlab.com/gitlab-org/charts/gitlab-agent/-/blob/main/templates/clusterrolebinding-cluster-admin.yaml

    SERVICE_ACCOUNT=$AGENT_NAME
    NAMESPACE=$AGENT_NAME
    ## TODO: Review role/rolebinding for agents
    if [[ $AGENT_NAME = "review" ]]; then 
        SERVICE_ACCOUNT=gitlab-review-agent
        NAMESPACE=gitlab-review-agent
    else
        SERVICE_ACCOUNT=gitlab-deploy-agent;
        NAMESPACE=gitlab-deploy-agent;
    fi

    ## TODO: Mixing agents and runners aint great, but also mixing environments aint great
    ## Having a NS per runner and per agent seems like overkill but according to the rolebindings docs
    ##  just having edit access in the namespace allows access to any other service account in the NS
    ## Runners need to be able to access secrets for the registry and agents need to be able to at least create
    ##  pods/runners.. so we're in a bit of a pickle.
    ## If agents and runners are in their own namespace, they need to be able to create pods in another namespace
    ## Maybe a compromise is just "review/feature" agent namespace and "dev,beta,prod" agent namespace
    ## Then the same for runners "review/feature" runner namespace and "dev,beta,prod" runner namespace (we kinda do this with 'review' and 'deploy')
    ## Then do what we're doing with a namespace for each tier/stage of apps review, dev, beta, and prod
    ## https://kubernetes.io/docs/reference/access-authn-authz/rbac/#user-facing-roles

    ## Time to revist hierarchiecal namespaces - agent > runner-that-can-create-HNS > HNS
    #https://github.com/kubernetes-sigs/hierarchical-namespaces/releases

    ###### Long winded brainstorm write-up/vomit
    ## The agent can create/delete runner pods etc.
    ## Give the runner the ability to create dynamic hierarchical namespace but not delete namespaces
    ## Then just have a cronjob schedule deletes on HNS's however we see fit
    ## This gives isolation of pods/resources (kubectl get pods --all -n HNS), nothing actually running in the runner NS to worry about
    ##   (can probably limit ability to create pods in its own NS along with anything else, maybe a setup step to create a SA for that HNS), 
    ##   then subsequent pipeline steps use this newly setup SA with admin access of this very isolated namespace, which gives runners 
    ##   full ability to manage that HNS's resources, and gives us a way to clean up the namespace without accidently
    ##   deleting important namespace/resources (we can label these namespaces)
    ## Agent in NS1 creates runner pod in RUNNER_NS1 which can only create HNS in RUNNER_NS1
    ## POD in RUNNER_NS1 creates DYNAMIC_HNS1 and a service account for DYNAMIC_HNS1 with admin access
    ## Now followup pipeline steps use (admin) service account in DYNAMIC_HNS1 to create pods/ingress/secrets etc freely but limited to 
    ##   DYNAMIC_HNS1 without being able impersonate another service account or worry about other apps/resources
    ## Cleanup job deletes HNS if its been active/inactive for 3 days or something idk

    ## The only thing I think that needs to be figured out is dynamically creating a service account with admin for this new HNS then
    ##   having follow up pipeline steps use that service account.
    ## I think thats how and why we would use the following settings in gitlab
    ## - bearer_token_overwrite_allowed
    ## - namespace_overwrite_allowed
    ## - service_account_overwrite_allowed
    ## All resources would be something like review-hns-MY_COOL_NAMESPACE etc and pipeline steps then are allow to overrwite to use
    ##  our new unique namespace/resources based on our branch name

    ## Hopefully in allowing the creation of HNS we're allowed to create service accounts for it, that seems to be a bottleneck
    ## review-runner-ns  
    ## Hell hopefully we can allow creating HNS only within that namespace and not anywhere else etc.
    ##  Answer to the "only within the HNS", the answer is YES - subnamespaces:
    ##  https://github.com/kubernetes-sigs/multi-tenancy/blob/master/incubator/hnc/docs/user-guide/concepts.md#basic-subns

    ## kubectl hns create review-runner -n review-agent
    ## kubectl -n review-runner create serviceaccount review-runner
    ## kubectl -n review-runner create role create-sa-for-apps --verb=create,delete,update --resource=serviceaccounts   (or clusterrole)

    
    ## kubectl -n review-runner create rolebindinding create-sa-review-runner --role create-sa-for-apps --serviceaccount=review-agent:review-runner

    ## Now that the create-sa-review-runner SA has the ability to create rolebindings in review-runner, how can that be abused in CI
    ## I can now create a rolebinding that allows cool-new-app-sa in cool-new-app to get/create/delete secrets in thatguys-cool-new-app which is bad

    ## I have project-A with access to review-runner
    ## He has project-B with access to review-runner
    ## With access to review-runner, he can create a rolebind for his-cool-app-sa in project-B to access my-cool-app secrets in project-A
    ##   stuck again

    ## but rolebindings cant cross namespaces tho now that I remember... hmmmm

    ########
    ########
    ########
    ########
    ## On push, create a NS and service account for branch that has nothing to do with .gitlab-ci.yaml file, and having the user use 
    ##  our shared runner (that becomes the appeal of using it) that can only interact with that NS with that service account
    ## This is harder than it looks and we're still stuck there
    ## Letting people use runners for OUR project is not a problem anymore, but new projects to use our shared runner is...
    ########
    ## Can we limit a service account to ONLY ALLOW CREATING SUBNAMESPACES to our runner, and only get the service account
    ##  token for the subnamespace we just created
    ## Can we make like a kubernetes hook to like on `kubectl hns create` or `kubectl create ns` to grab the service account
    ##  token and have it stored in a variable
    ## Maybe we force the user to provide a KUBE_SERVICE_TOKEN CI variable, auto assign it to this newly created namespaces
    ##  service account, then you overrwrite the bearer_token with this variable to use this new namespace or it just fails

    ## Forcing the user to provide a unique token to provide to the unique namespaces service account...??
    ## Basically the review-runner can only create namespaces, which means you cant do a deploy of any kind, 
    ##   so for the following steps to be able to deploy/delete/push etc, the runner must have a token provided to overrwrite the default token
    ##   for the new namespace, then use bearer_token_overwrite, using the new namespace, allows the runner to get/create/update as the default accont
    ##   of that namespace
    ## Can we manually populate this service token based on like the 
    ########
    ########
    ########

    ## review-agent
    ##  |-- review-runner 

    ## AS service account review-runner (with limited access)   can
    ## kubectl hns create review-cool-new-app -n review-runner
    ## kubectl -n review-cool-new-app create serviceaccount cool-app-sa
    ##   Dont need to create admin as its a clusterrole already
    ## kubectl -n review-cool-new-app create rolebindinding cool-app-admin --role admin --serviceaccount=review-runner:cool-app-sa

    ## review-agent
    ##  |-- review-runner 
    ##    |-- review-cool-new-app

    ## now AS service-account cool-app-admin further down in pipelines

    ## kubectl get deploy,secrets,svc,pod -n review-agent
    ## NOPE
    ## kubectl get deploy,secrets,svc,pod -n review-runner
    ## NOPE
    ## kubectl get deploy,secrets,svc,pod -n review-cool-new-app
    ## review-cool-new-app-deploy-1
    ## review-cool-new-app-secret-1
    ## review-cool-new-app-svc-1
    ## review-cool-new-app-pod-1

    ## Allows us to let runners create unique namespaces and limited service accounts on the fly without giving
    ##   them full access to create/manage namespaces/serviceaccounts cluster-wide

    ## Is there a way to allow the review-runner service account to make service accounts and rolebindings for dynamic/new namespaces
    ## Allowing the review-runner SA to create namespaces (as long as it cant delete them) isnt that big of a deal
    ## But that review-runner SA now needs to be able to now at least be able to create a SA and rolebinding in that new namespace
    ## Then we have the SA/namespace override to the newly made/dynamic NS/service account that needs to have admin access

    ## Feels like this can work if we get over those obstacles

    #https://github.com/kubernetes-sigs/hierarchical-namespaces/releases

    helm upgrade --install $AGENT_NAME gitlab/gitlab-agent \
        --namespace $NAMESPACE \
        --create-namespace \
        --set image.tag=v15.5.1 \
        --set config.token="${AGENT_TOKEN}" \
        --set config.kasAddress="wss://gitlab.${DOMAIN}/-/kubernetes-agent/" \
        --set rbac.create=false \
        --set serviceAccount.create=false \
        --set serviceAccount.name=$SERVICE_ACCOUNT
done


consul kv put kube/gitlab_integrated true
