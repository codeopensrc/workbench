#!/bin/bash

# This pertains to creating a registry on AWS's ECR.
# Todo item would be creating the registry anywhere


# TODO: Specify dev/stage/prod and ensure we create the ECR repos in those those
#   environments with AWS credentials/regions etc.

OLDREGION=""
NEWREGION=""

OLDPROFILE=""
NEWPROFILE=""

OLDREGISTRY=""
NEWREGISTRY=""

################################################
######## Nothing below this needs to be edited
################################################

LOGIN=$(aws --profile $OLDPROFILE ecr get-login --no-include-email --region $OLDREGION)
$LOGIN

REPOS=(`aws --profile $OLDPROFILE ecr describe-repositories --region $OLDREGION | jq -r ".repositories[].repositoryName"`)

for repo in "${REPOS[@]}"; do

    # All tags associated with repo
    IDS=(`aws --profile $OLDPROFILE ecr list-images --repository-name=$repo --region $OLDREGION | jq -r .imageIds[].imageTag`)

    PATCH=0
    MINOR=0
    MAJOR=0
    VER=$MAJOR.$MINOR.$PATCH

    # Get highest tagged version
    for id in "${IDS[@]}"; do
        NEWPATCH=$(echo $id | cut -d "." -f 3)
        NEWMINOR=$(echo $id | cut -d "." -f 2)
        NEWMAJOR=$(echo $id | cut -d "." -f 1 | sed  "s/v//g")

        if [[ $NEWPATCH == "null" ]] || [[ $NEWMINOR == "null" ]] || [[ $NEWMAJOR == "null" ]]; then
            continue
        fi

        if [[ $NEWPATCH == "latest" ]] || [[ $NEWMINOR == "latest" ]] || [[ $NEWMAJOR == "latest" ]]; then
            continue
        fi

        if [[ $NEWPATCH -ge $PATCH ]] && [[ $NEWMINOR -ge $MINOR ]] && [[ $NEWMAJOR -ge $MAJOR ]]; then
            VER=$NEWMAJOR.$NEWMINOR.$NEWPATCH
            MAJOR=$NEWMAJOR
            MINOR=$NEWMINOR
            PATCH=$NEWPATCH
        fi
    done

    # Pull image from old registry
    docker pull $OLDREGISTRY/$repo:$VER

    # Login to new registry
    LOGIN=$(aws --profile $NEWPROFILE ecr get-login --no-include-email --region $NEWREGION)
    $LOGIN

    # Create repo in new registry
    aws --profile $NEWPROFILE ecr create-repository --repository-name "$repo" --region $NEWREGION

    # Push version to new registry
    docker tag $OLDREGISTRY/$repo:$VER $NEWREGISTRY/$repo:$VER;
    docker push $NEWREGISTRY/$repo:$VER;

    # Tag as latest and push that to new registry as well
    docker tag $OLDREGISTRY/$repo:$VER $NEWREGISTRY/$repo:latest;
    docker push $NEWREGISTRY/$repo:latest;
done
