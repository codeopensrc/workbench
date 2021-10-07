#!/bin/bash

############
############
#### NOTE: HASNT BEEN REVIEWED IN SOME TIME. USED AT LEAST 2 MAJOR TERRAFORM UPDATES AGO
########
########

# NOTE: We want to do admin LAST due us removing /tmp/consul each time we re-provision consul_file_admin
# Types:     admin, leader, db        build? web? dev? mongo? pg? redis? legacy? not tested yet
PROVISIONER_TYPE=admin
if [ -z "$PROVISIONER_TYPE" ]; then echo "Please choose a type of provisioner."; exit; fi

# If there's more than one resource, set a specific resource num in the form of   ".RESOURCE_NUM"
# Ex.   RESOURCE_NUM=".1"
RESOURCE_NUM=""

# Can swap between taint and untaint
TAINT_CMD="taint"


if [ "$PROVISIONER_TYPE" == "leader" ]; then
    terraform $TAINT_CMD -module=do.do_"$PROVISIONER_TYPE"_provisioners null_resource.consul_file_leader$RESOURCE_NUM
fi

# NOTE: We want to do admin LAST due us removing /tmp/consul each time we re-provision consul_file_admin
if [ "$PROVISIONER_TYPE" == "admin" ]; then
    terraform $TAINT_CMD -module=do.do_"$PROVISIONER_TYPE"_provisioners null_resource.consul_file_admin$RESOURCE_NUM
fi

if [ "$PROVISIONER_TYPE" != "leader" ] && [ "$PROVISIONER_TYPE" != "admin" ];  then
    terraform $TAINT_CMD -module=do.do_"$PROVISIONER_TYPE"_provisioners null_resource.consul_file$RESOURCE_NUM
fi

terraform $TAINT_CMD -module=do.do_"$PROVISIONER_TYPE"_provisioners null_resource.consul_install$RESOURCE_NUM

#terraform $TAINT_CMD -module=do.do_"$PROVISIONER_TYPE"_provisioners null_resource.consul_service$RESOURCE_NUM
