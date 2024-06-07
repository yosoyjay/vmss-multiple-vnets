# Deploy a VMSS with multiple VNets

## Summary

The steps outline in this document and implemented in the accompanying `deploy-vmss.sh` script are the only verified means of provisioning
a VMSS with multiple virtual networks for front-end networking while maintaining InfiniBand connectivity.

It is essential that the steps be followed exactly.

## Provision the VMSS

The accompanying script `deploy-vmss.sh` results in the desired end state of a single VMSS ('vmss-1') with 1000 VMs attached to 20 different VNets.

The deployment described here *requires* the provisioning of 20 distinct VMSS including the required VNets, LoadBalancers, and NSGs each with an initial instance count of 0.

Following the provisioning of the VMSS, 'vmss-1' is scaled out resulting in 50 VMs being provisioned that are associated with 'vnet-1'.

Next, the process is to update the configuration of 'vmss-1' to use the 'subnetId', 'NSG', and 'loadBalancer backendAddressPools' provisioned in the other VMSS and to then scale out.

For example, after the initial scaling out, 'vmss-1' is updated to use the 'subnetId', 'NSG', and 'loadBalancer backendAddressPools' created with 'vmss-2'.  Once updated, 'vmss-1' is then scaled out to 100 VMs.  VMs 1-50 will be associated with 'vnet-1'.  VMs 51-100 will be associated with 'vnet-1'.  All VMs (1-100) will retain InfiniBand connectivity.

In the next iteration, 'vmss-1' is updated with the 'subnetId', 'NSG', and 'loadBalancer backendAddressPools' created with 'vmss-3'.  Once updated, 'vmss-1' is then scaled out to 150 VMs.  This process continues until all of the VMs are allocated across the VNets.

## Verification

You can verify connectivity over InfiniBand by SSHing between machines, or running an MPI job over InfiniBand.

## MPI usage notes

The provisioned VMs will all be associated with 'vmss-1' and will share the InfiniBand network but there will be no front-end connectivity which is normally used to start an MPI application.  Instead, you can use the OpenMPI flag, or equivalent, `--mca oob_tcp_if_include ib0` launch jobs.  This will also require the creation of a hostlist file with the InfiniBand addresses of the other VMs.  Additionally, if hostnames are to be used, the hosts and IP addresses in /etc/host will need to configured.

For example, running NCCL allreduce on two nodes, 16 GPUs, can be invoked by

```bash
mpirun --hostfile hostfile.txt \
    -np 16 \
    --bind-to none \
    --map-by ppr:8:node \
    --mca oob_tcp_if_include ib0 \
    -x SHARP_SMX_UCX_INTERFACE=mlx5_ib0:1 \
    -x LD_LIBRARY_PATH \
    --mca plm_rsh_no_tree_spawn 1 \
    --mca plm_rsh_num_concurrent 800 \
    --mca coll_hcoll_enable 0 \
    -x UCX_TLS=rc \
    -x UCX_NET_DEVICES=mlx5_0:1 \
    -x CUDA_DEVICE_ORDER=PCI_BUS_ID \
    -x NCCL_SOCKET_IFNAME=ib0 \
    -x NCCL_DEBUG=warn \
    -x NCCL_NET_GDR_LEVEL=5 \
    -x NCCL_MIN_NCHANNELS=32 \
    -x NCCL_TOPO_FILE=/opt/microsoft/ndv5-topo.xml \
    -x NCCL_COLLNET_ENABLE=1 \
    -x NCCL_ALGO=CollnetChain,NVLS \
    -x SHARP_COLL_ENABLE_SAT=1 \
    -x SHARP_COLL_LOG_LEVEL=3 \
    -x SHARP_COLL_ENABLE_PCI_RELAXED_ORDERING=1 \
    /opt/nccl-tests/build/all_reduce_perf -b1K -f 2 -g1 -e 2G
```

where `hostfile.txt` contains InfiniBand IPs for each host.


Note: Ensure references to InfiniBand devices such as those specified for NCCL_SOCKET_IFNAME are correct for your environment and that NCCL_TOPO_FILE points to the correct path, if required.

## Connecting the Front-End Networks

The options to connect the front-end networks are to use peering setup between all the VNETs or using the hub-spoke setup with a Network Virtual Appliance (e.g. Azure Firewall) to route the traffic. These options are discussed here: Hub-spoke network topology in Azure - Azure Architecture Center | Microsoft Learn.