# Azure AI Agent Service Mini Azure Platform Landing Zone - Test Environment

This test environment provides a complete **Hub-Spoke architecture** ready for Azure AI Agent Service deployment. It demonstrates the network infrastructure patterns required for the full Azure AI Agent Service migration.

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        HUB VNET (10.0.0.0/16)                  │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │ Azure Firewall  │  │ Private DNS     │  │ Azure Bastion   │  │
│  │ (10.0.1.4)      │  │ Resolver        │  │ + Jump Box      │  │
│  │                 │  │ (10.0.3.4)      │  │                 │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                                │
                         VNet Peering
                                │
┌─────────────────────────────────────────────────────────────────┐
│                    SPOKE VNET (192.168.0.0/16)                 │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │ App Services    │  │ Private         │  │ AI Agents       │  │
│  │ Subnet          │  │ Endpoints       │  │ Egress Subnet   │  │
│  │ (192.168.0.0/24)│  │ (192.168.2.0/27)│  │ (192.168.3.0/24)│  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## 🎯 What This Environment Provides

### **Hub Infrastructure (rg-hub-test)**
- ✅ **Azure Firewall Basic** - Centralized egress control
- ✅ **Private DNS Resolver** - DNS resolution for private endpoints
- ✅ **Azure Bastion + Jump Box** - Secure management access
- ✅ **Private DNS Zones** - For all AI services
- ✅ **Route Tables** - Traffic routing through firewall

### **Spoke Infrastructure (rg-spoke-test)**
- ✅ **192.168.x.x Network** - Required for Azure AI Agent Service
- ✅ **VNet Peering** - Bidirectional connectivity to hub
- ✅ **DNS Configuration** - Points to hub DNS Resolver
- ✅ **Subnets Ready for AI Services**:
  - `snet-appServices` - App Service delegation
  - `snet-privateEndpoints` - Private endpoints
  - `snet-aiAgentsEgress` - AI Agent Service delegation
  - `snet-buildAgents` - Build agents
  - `snet-appGateway` - Application Gateway

## 🚀 Quick Start

### **Option 1: Automated Deployment**
```powershell
# Run the automated deployment script
.\deploy.ps1
```

### **Option 2: Manual Deployment**
```bash
# 1. Create hub resource group
RESOURCE_GROUP_HUB=$RESOURCE_GROUP-hub
RESOURCE_GROUP_SPOKE=$RESOURCE_GROUP-spoke

az group create --name $RESOURCE_GROUP_HUB --location $LOCATION

# 2. Deploy hub infrastructure
az deployment group create \
  --resource-group $RESOURCE_GROUP_HUB \
  --template-file test-hub-vnet.bicep \
  -p hubBaseName=$BASE_NAME

# 3. Create spoke resource group
az group create --name $RESOURCE_GROUP_SPOKE --location $LOCATION

# 4. Get hub outputs
HUB_VNET_ID=$(az deployment group show --resource-group $RESOURCE_GROUP_HUB --name test-hub-vnet --query "properties.outputs.hubVirtualNetworkId.value" -o tsv)
DNS_RESOLVER_IP=$(az deployment group show --resource-group $RESOURCE_GROUP_HUB --name test-hub-vnet --query "properties.outputs.dnsResolverInboundEndpointIp.value" -o tsv)
FIREWALL_IP=$(az deployment group show --resource-group $RESOURCE_GROUP_HUB --name test-hub-vnet --query "properties.outputs.azureFirewallPrivateIp.value" -o tsv)

# 5. Deploy spoke infrastructure
az deployment group create \
  --resource-group $RESOURCE_GROUP_SPOKE \
  --template-file test-spoke-vnet.bicep \
  --parameters spokeBaseName=spoke \
               hubVirtualNetworkId="$HUB_VNET_ID" \
               hubDnsResolverIp="$DNS_RESOLVER_IP" \
               hubFirewallPrivateIp="$FIREWALL_IP" \
               spokeBaseName=$BASE_NAME
```

## 📋 Prerequisites

- **Azure CLI** installed and authenticated
- **PowerShell 7+** (for automation scripts)
- **Azure subscription** with Contributor access
- **Region**: eastus2 (or update scripts for your preferred region)

## 🔧 Configuration

### **Default Parameters**
- **Hub Base Name**: `hub`
- **Spoke Base Name**: `spoke`
- **Location**: `eastus2`
- **Jump Box Admin**: `vmadmin`
- **Jump Box Password**: `SecurePassword123!` (change in production)

### **Network Ranges**
- **Hub VNet**: `10.0.0.0/16`
- **Spoke VNet**: `192.168.0.0/16` (required for AI Agent Service)

## 🧪 Testing Connectivity

### **1. Test DNS Resolution**
```bash
# Connect to jump box via Bastion and test DNS
nslookup privatelink.cognitiveservices.azure.com
# Should resolve to hub DNS Resolver IP: 10.0.3.4
```

### **2. Test VNet Peering**
```bash
# Check peering status
az network vnet peering list --resource-group $RESOURCE_GROUP_HUB --vnet-name vnet-hub --output table
az network vnet peering list --resource-group $RESOURCE_GROUP_SPOKE --vnet-name vnet-spoke --output table
# Both should show "Connected" and "FullyInSync"
```

### **3. Test Hub-to-Spoke Connectivity**
```bash
# From jump box, test connectivity to spoke VNet
# This should work directly (not through firewall) due to VnetLocal route
ping 192.168.0.1  # Should reach spoke VNet directly
tracert 192.168.0.1  # Should show direct path, not via firewall
```

### **4. Test Firewall Routing**
```bash
# Check effective routes on spoke subnets
az network nic show-effective-route-table --resource-group rg-spoke-test --name <nic-name>
# Should show 0.0.0.0/0 -> 10.0.1.4 (firewall IP)
# Should show 10.0.0.0/16 -> VnetLocal (direct to hub)

# Check effective routes on hub subnets
az network nic show-effective-route-table --resource-group rg-hub-test --name nic-jumpbox
# Should show 0.0.0.0/0 -> 10.0.1.4 (firewall IP)
# Should show 192.168.0.0/16 -> VnetLocal (direct to spoke)
```

## 📁 File Structure

```
test/
├── README.md                 # This documentation
├── deploy.ps1               # Automated deployment script
├── cleanup.ps1              # Cleanup script
├── test-hub-vnet.bicep      # Hub infrastructure template
└── test-spoke-vnet.bicep    # Spoke infrastructure template
```

## 🔄 Next Steps: Deploy AI Services

After the infrastructure is ready, you can deploy AI services in the spoke VNet:

1. **Azure AI Foundry** (with AI Agent Service capability)
2. **Azure AI Search**
3. **Cosmos DB** (for thread storage)
4. **Storage Account** (for blob storage)
5. **Private Endpoints** (in spoke's private endpoints subnet)

## 🧹 Cleanup

### **Automated Cleanup**
```powershell
.\cleanup.ps1
```

### **Manual Cleanup**
```bash
# Delete resource groups (this removes all resources)
az group delete --name rg-hub-test --yes --no-wait
az group delete --name rg-spoke-test --yes --no-wait
```

## 🚨 Important Notes

### **Network Requirements**
- **192.168.x.x ranges are MANDATORY** for Azure AI Agent Service
- **Private DNS Resolver** is required for proper DNS resolution
- **Azure Firewall** provides centralized egress control

### **Security**
- All subnets route through Azure Firewall for egress
- Private endpoints use dedicated subnet with NSG protection
- AI Agent egress subnet has restrictive NSG rules

### **Cost Optimization**
- Uses **Azure Firewall Basic** tier (lower cost)
- **Standard** VMs and storage for cost efficiency
- **Private DNS Resolver** instead of firewall DNS proxy

## 🔍 Troubleshooting

### **Common Issues**

1. **Deployment Fails with "FirewallPolicyHigherTierOnlyProperties"**
   - Ensure using Basic tier firewall
   - Remove DNS proxy settings from firewall policy

2. **VNet Peering Not Connected**
   - Check both directions of peering are created
   - Verify resource IDs are correct

3. **DNS Resolution Not Working**
   - Verify DNS Resolver is deployed and running
   - Check VNet DNS settings point to resolver IP (10.0.3.4)

4. **Private Endpoints Can't Resolve**
   - Ensure private DNS zones are linked to both VNets
   - Verify DNS Resolver has proper forwarding rules

### **Useful Commands**
```bash
# Check deployment status
az deployment group list --resource-group $RESOURCE_GROUP_HUB --output table
az deployment group list --resource-group $RESOURCE_GROUP_SPOKE --output table

# View deployment errors
az deployment operation group list --resource-group $RESOURCE_GROUP_HUB --name test-hub-vnet

# Test connectivity from jump box
az network bastion ssh --name bastion-hub --resource-group $RESOURCE_GROUP_HUB --target-resource-id <vm-resource-id> --auth-type password --username vmadmin
```

## 📚 References

- [Azure AI Agent Service Documentation](https://docs.microsoft.com/azure/ai-services/agents/)
- [Azure Private DNS Resolver](https://docs.microsoft.com/azure/dns/dns-private-resolver-overview)
- [Azure Firewall Basic](https://docs.microsoft.com/azure/firewall/basic-features)
- [VNet Peering](https://docs.microsoft.com/azure/virtual-network/virtual-network-peering-overview)

## 🎉 DEPLOYMENT COMPLETED SUCCESSFULLY!
═══════════════════════════════════════════════════════════════════════════════

📦 Resource Groups Created:
   • rg-hub-test (Hub infrastructure)
   • rg-spoke-test (Spoke infrastructure)

🌐 Network Configuration:
   • Hub VNet: $($HubOutputs.VNetName) (10.0.0.0/16)
   • Spoke VNet: $($SpokeOutputs.VNetName) (192.168.0.0/16)
   • VNet Peering: ✅ Connected

🔧 Key Infrastructure Components:
   • Azure Firewall Private IP: $($HubOutputs.FirewallPrivateIp)
   • DNS Resolver Inbound IP: $($HubOutputs.DnsResolverIp)
   • Azure Bastion: bastion-$HubBaseName
   • Jump Box VM: vm-jumpbox-$HubBaseName

🧪 Testing Your Environment:
   1. Connect to jump box via Azure Bastion
   2. Test DNS resolution: nslookup privatelink.cognitiveservices.azure.com
   3. Verify internet access through firewall

🔄 Next Steps:
   1. Deploy Azure AI Foundry in the spoke VNet
   2. Create private endpoints in snet-privateEndpoints
   3. Deploy AI Agent Service in snet-aiAgentsEgress

🧹 Cleanup:
   Run .\cleanup.ps1 to remove all resources when done
