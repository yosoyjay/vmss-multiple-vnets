#!/bin/bash
# Deploy a single VMSS with multiple VNets while maintaining InfiniBand connectivity
# Process:
# - Create 20 VMSS
# - Iterate over VMSS #2 to #20
#    - Update the "main" VMSS (the one which will be scaled out) to use the NSG, Load Balancer, and Subnet from the current VMSS
#    - Scale out the "main" VMSS

REGION='eastus'
RESOURCE_GROUP='jesse-test-vnets-05'
IMAGE='microsoft-dsvm:ubuntu-hpc:2204:latest'
VM_SKU='Standard_HB120rs_v3'
SSH_KEY_PATH='/Users/jesse/.ssh/azure/jlo-azure-ssh-key.pub'
NUM_VMSS=20
NUM_VMS_PER_VMSS=50
MAIN_VMSS='vmss-1'

az group create --name $RESOURCE_GROUP --location $REGION

# Create 20 VMSS
# Used for address prefix in VNets.  Each VMSS will have a unique address prefix of the form 10.<IP_OCTET>.0.0/16
IP_START=173 # Starting index for the VNet address space in second octet
for i in $(seq 1 $NUM_VMSS); do
    VMSS_NAME="vmss-${i}"
    VNET_NAME="vnet-${i}"
    IP_OCTET=$(($IP_START + $i - 1))

    az vmss create \
        --resource-group $RESOURCE_GROUP \
        --name $VMSS_NAME \
        --image $IMAGE \
        --instance-count 0 \
        --platform-fault-domain-count 1 \
        --single-placement-group false \
        --accelerated-networking true \
        --vm-sku $VM_SKU \
        --ssh-key-values $SSH_KEY_PATH \
        --admin-username azureuser \
        --location $REGION \
        --vnet-name $VNET_NAME \
        --vnet-address-prefix "10.${IP_OCTET}.0.0/16" \
        --subnet default \
        --subnet-address-prefix "10.${IP_OCTET}.0.0/24" \
        --orchestration-mode Flexible
done

# Scale out pattern
# 0. Scale out in 1st VMSS
az vmss scale --resource-group $RESOURCE_GROUP --name $MAIN_VMSS --new-capacity $NUM_VMS_PER_VMSS

# Iterate over the remainder of the VMSS that have been provisioned
# 1. Update VMSS "model"
# 2. Scale out in the VMSS
for i in $(seq 2 $NUM_VMSS); do
    VMSS_NAME="vmss-${i}"
    VNET_NAME="vnet-${i}"

    # Update the VMSS "model" - Update the First VMSS to use the NSG, Load Balancer, and Subnet from the Second VMSS
    subnet_id=$(az network vnet subnet show --resource-group $RESOURCE_GROUP --vnet-name $VNET_NAME --name default --query id -o tsv)
    nsg_id=$(az network nsg list --resource-group $RESOURCE_GROUP --query "[?contains(name, '$VMSS_NAME')].id" -o tsv)
    lb_bep_id=$(az network lb list --resource-group $RESOURCE_GROUP --query "[?contains(name, '$VMSS_NAME')].backendAddressPools[0].id" -o tsv)

    az vmss update \
        --resource-group $RESOURCE_GROUP \
        --name $MAIN_VMSS \
        --set "virtualMachineProfile.networkProfile.networkInterfaceConfigurations[0].ipConfigurations[0].subnet.id=$subnet_id" \
        --set "virtualMachineProfile.networkProfile.networkInterfaceConfigurations[0].ipConfigurations[0].loadBalancerBackendAddressPools[0].id=$lb_bep_id" \
        --set "virtualMachineProfile.networkProfile.networkInterfaceConfigurations[0].networkSecurityGroup.id=$nsg_id"

    # Scale out in main VMSS
    # - 'new-capacity' is the total number of VMs, not the number of VMs to add
    NEW_VM_CAPACITY=$(($i * $NUM_VMS_PER_VMSS))
    az vmss scale --resource-group $RESOURCE_GROUP --name $MAIN_VMSS --new-capacity $NEW_VM_CAPACITY
done
