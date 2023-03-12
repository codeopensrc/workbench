#!/bin/bash

###! Discussion/brainstorming regarding agents/runners/service accounts moved to:
###! https://gitlab.codeopensrc.com/os/workbench/-/issues/45

## For now a single agent works - going to use 1 until we have a reason not to
AGENT_NAME_DEFAULTS=( "review" )
#AGENT_NAME_DEFAULTS=( "review" "beta" "production" )

GL_CLUSTER_AGENT_ROLE_NAME=gitlab-agent-clusterrole
GL_AGENT_FILE_LOCATION=$HOME/.kube/gitlab-agent-service-account.yaml

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

###! Discussion/brainstorming regarding agents/runners/service accounts moved to:
###! https://gitlab.codeopensrc.com/os/workbench/-/issues/45
#cat <<-EOF > $GL_AGENT_FILE_LOCATION
#apiVersion: rbac.authorization.k8s.io/v1
#kind: ClusterRole
#metadata:
#  name: $GL_CLUSTER_AGENT_ROLE_NAME
#rules:
#- apiGroups: [""]
#  resources: ["pods"]
#  verbs: ["get", "list", "watch", "create", "delete"]
#- apiGroups: [""]
#  resources: ["pods/exec", "pods/attach"]
#  verbs: ["create", "patch", "delete"]
#- apiGroups: [""]
#  resources: ["pods/log"]
#  verbs: ["get"]
#- apiGroups: [""]
#  resources: ["secrets"]
#  verbs: ["get", "create", "update", "delete"]
#- apiGroups: [""]
#  resources: ["configmaps"]
#  verbs: ["create", "update", "delete"]
#---
#EOF

## Register multiple agents and install via helm
for AGENT_NAME in ${AGENT_NAMES[@]}; do
    echo "AGENT_NAME: $AGENT_NAME"

    ## Register agent
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

    ###! Discussion/brainstorming regarding agents/runners/service accounts moved to:
    ###! https://gitlab.codeopensrc.com/os/workbench/-/issues/45
    ## By default the agent has cluster-admin ClusterRoleBinding
    ## set rbac.create=false to not attach the cluster role
    ## We'll create and attach our own roles to each agent like we do runners
    ## For now our RBAC should essentially mimic the cert-based approached but without the gitlab-admin role
    #https://gitlab.com/gitlab-org/charts/gitlab-agent/-/blob/main/templates/clusterrolebinding-cluster-admin.yaml

    SERVICE_ACCOUNT=$AGENT_NAME
    NAMESPACE=$AGENT_NAME
    ## TODO: Review role/rolebinding for agents
    if [[ $AGENT_NAME = "review" ]]; then 
        SERVICE_ACCOUNT=default
        NAMESPACE=gitlab-agent
    else
        SERVICE_ACCOUNT=gitlab-deploy-agent;
        NAMESPACE=gitlab-deploy-agent;
    fi

    ###! Discussion/brainstorming regarding agents/runners/service accounts moved to:
    ###! https://gitlab.codeopensrc.com/os/workbench/-/issues/45
    ### For now we'll just mimic runner permissions until we determine exact permissions needed
    ### Agent names mimic our runner namespaces
    #if [[ $AGENT_NAME = "review" ]]; then 
    #    cat <<-EOF >> $GL_AGENT_FILE_LOCATION
    #    apiVersion: v1
    #    kind: ServiceAccount
    #    metadata:
    #      name: $SERVICE_ACCOUNT
    #      namespace: $NAMESPACE
    #    ---
    #    EOF
    #fi

    ###! Discussion/brainstorming regarding agents/runners/service accounts moved to:
    ###! https://gitlab.codeopensrc.com/os/workbench/-/issues/45
    ### Going to try one agent in one namespace with a rolebinding in its own namespace and see if we
    ###   can use our runners with service accounts to deploy to all namespaces based on runner service account permissions
    #if [[ $AGENT_NAME = "review" ]]; then 
    #    cat <<-EOF >> $GL_AGENT_FILE_LOCATION
    #    apiVersion: rbac.authorization.k8s.io/v1
    #    kind: RoleBinding
    #    metadata:
    #      name: gitlab-agent-rolebinding
    #      namespace: $NAMESPACE
    #    subjects:
    #      - kind: ServiceAccount
    #        name: 
    #        namespace: $NAMESPACE
    #    roleRef:
    #      kind: ClusterRole
    #      name: $GL_CLUSTER_AGENT_ROLE_NAME
    #      apiGroup: rbac.authorization.k8s.io
    #    ---
    #    EOF
    #fi
    #kubectl apply -f $GL_AGENT_FILE_LOCATION


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
