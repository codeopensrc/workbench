#!/bin/bash

#### NOTE: This migrates one s3 bucket at a time to stay fairly configurable
#### TODO: Write to allow cli inputs to run this script in a resource

# Switch to true if you want to ignore $INCLUDE date vars and sync everything
INCLUDE_ALL="false"
INCLUDE_ONLY_YEARS=("2020")
INCLUDE_ONLY_MONTHS=("01" "02" "03", "04", "05")
INCLUDE_ONLY_FOLDERS=()

OLDREGION=""
NEWREGION=""

OLDPROFILE=""
NEWPROFILE=""

OLDBUCKET=""
NEWBUCKET=""
MAKE_OBJECTS_PUBLIC=""
BLOCK_ALL_PUBLIC_ACCESS=""

DEST_ACC_NUM=""

# https://aws.amazon.com/premiumsupport/knowledge-center/copy-s3-objects-account/

#### Policy for Account A (src)
#### TODO: We are going to list all our previous buckets (or list the names we want) and
#### programatically apply the policy to all source buckets
SOURCE_POLICY='{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "DelegateS3Access",
            "Effect": "Allow",
            "Principal": {"AWS": "'$DEST_ACC_NUM'"},
            "Action": ["s3:ListBucket","s3:GetObject"],
            "Resource": [
                "arn:aws:s3:::'$OLDBUCKET'/*",
                "arn:aws:s3:::'$OLDBUCKET'"
            ]
        }
    ]
}'
DELEGATE_POLICY=$(jq -c '' <<< "${SOURCE_POLICY}")
aws --profile $OLDPROFILE s3api put-bucket-policy --bucket $OLDBUCKET --policy $DELEGATE_POLICY


# Create new bucket in new account
aws --profile $NEWPROFILE s3api create-bucket --bucket $NEWBUCKET --create-bucket-configuration LocationConstraint=$NEWREGION

# Add this policy to make all objects fetchable publically at NEWBUCKET
if [[ $MAKE_OBJECTS_PUBLIC == "true" ]]; then
    JSON='{
        "Version":"2012-10-17",
        "Statement": [
            {
                "Effect":"Allow",
                "Principal": "*",
                "Action":["s3:GetObject"],
                "Resource":["arn:aws:s3:::'$NEWBUCKET'/*"]
            }
        ]
    }'
    json=$(jq -c '' <<< "${JSON}")
    aws --profile $NEWPROFILE s3api put-bucket-policy --bucket $NEWBUCKET --policy $json
fi

# Just another layer to ensure we dont accidently make the bucket public for private buckets
if [[ $BLOCK_ALL_PUBLIC_ACCESS == "true" ]]; then
    # aws --profile $NEWPROFILE s3api get-public-access-block --bucket $NEWBUCKET
    aws --profile $NEWPROFILE s3api put-public-access-block --bucket $NEWBUCKET \
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
fi


INCLUDE_ARGS=()  # Leave Blank

for YEAR in "${INCLUDE_ONLY_YEARS[@]}"; do
    for MONTH in "${INCLUDE_ONLY_MONTHS[@]}"; do
        INCLUDE_ARGS+=(--include="*${YEAR}-${MONTH}*/*")
    done
done

# Sync old bucket to new bucket
# Add "--dryrun" to the end do a dry run
# aws --profile $NEWPROFILE s3 sync "s3://$OLDBUCKET" "s3://$NEWBUCKET"
if [ "${INCLUDE_ALL}" = "true" ]; then
    aws --profile $NEWPROFILE s3 sync "s3://$OLDBUCKET" "s3://$NEWBUCKET" --dryrun
fi

if [ "${INCLUDE_ALL}" = "false" ]; then
    # aws --profile $NEWPROFILE s3 sync "s3://$OLDBUCKET" "s3://$NEWBUCKET" --exclude='*' "${INCLUDE_ARGS[@]}" --dryrun
    if [[ ${#INCLUDE_ONLY_FOLDERS[@]} -le 0 ]]; then
        echo -e "Array of folder names required in INCLUDE_ONLY_FOLDERS if INCLUDE_ALL set to false. \nExiting"
        exit 1
    fi

    for FOLDER in "${INCLUDE_ONLY_FOLDERS[@]}"; do
        # echo $FOLDER
        aws --profile $NEWPROFILE s3 sync "s3://$OLDBUCKET/$FOLDER" "s3://$NEWBUCKET/$FOLDER" --exclude='*' "${INCLUDE_ARGS[@]}" --dryrun
    done
fi





## NOTE: Below is for those with less than root/admin credentials and have not tested it
##### Create a role: pull_buckets
##### Apply below policy to that role. Assign role to credential user

##### Below is there wording
## Attach an IAM policy to a user or role in Account B
##
## 1.    From Account B, create an IAM customer managed policy that allows an IAM
## user or role to copy objects from the source bucket in Account A to the destination
## bucket in Account B. The policy can be similar to the following example:
#
# {
#     "Version": "2012-10-17",
#     "Statement": [
#         {
#             "Effect": "Allow",
#             "Action": [
#                 "s3:ListBucket",
#                 "s3:GetObject"
#             ],
#             "Resource": [
#                 "arn:aws:s3:::awsexamplesourcebucket",
#                 "arn:aws:s3:::awsexamplesourcebucket/*"
#             ]
#         },
#         {
#             "Effect": "Allow",
#             "Action": [
#                 "s3:ListBucket",
#                 "s3:PutObject",
#                 "s3:PutObjectAcl"
#             ],
#             "Resource": [
#                 "arn:aws:s3:::awsexampledestinationbucket",
#                 "arn:aws:s3:::awsexampledestinationbucket/*"
#             ]
#         }
#     ]
# }

# aws --profile OLDPROFILE s3 cp s3://mybucket/test.txt s3://mybucket2/
