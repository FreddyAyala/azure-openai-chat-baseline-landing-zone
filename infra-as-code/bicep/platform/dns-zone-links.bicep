targetScope = 'resourceGroup'

@description('The spoke VNet ID to link to the DNS zones')
param spokeVirtualNetworkId string

@description('The spoke VNet name for the link name')
param spokeVirtualNetworkName string

// Existing Private DNS Zones
resource cognitiveservicesDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.cognitiveservices.azure.com'
}

resource aiservicesDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.services.ai.azure.com'
}

resource openaiDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.openai.azure.com'
}

resource searchDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.search.windows.net'
}

resource blobDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.blob.core.windows.net'
}

resource cosmosdbDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.documents.azure.com'
}

resource keyvaultDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.vaultcore.azure.net'
}

resource websitesDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.azurewebsites.net'
}

// Link private DNS zones to spoke VNet
resource cognitiveservicesDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  name: 'link-to-${spokeVirtualNetworkName}'
  parent: cognitiveservicesDnsZone
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: spokeVirtualNetworkId }
  }
}

resource aiservicesDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  name: 'link-to-${spokeVirtualNetworkName}'
  parent: aiservicesDnsZone
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: spokeVirtualNetworkId }
  }
}

resource openaiDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  name: 'link-to-${spokeVirtualNetworkName}'
  parent: openaiDnsZone
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: spokeVirtualNetworkId }
  }
}

resource searchDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  name: 'link-to-${spokeVirtualNetworkName}'
  parent: searchDnsZone
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: spokeVirtualNetworkId }
  }
}

resource blobDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  name: 'link-to-${spokeVirtualNetworkName}'
  parent: blobDnsZone
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: spokeVirtualNetworkId }
  }
}

resource cosmosdbDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  name: 'link-to-${spokeVirtualNetworkName}'
  parent: cosmosdbDnsZone
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: spokeVirtualNetworkId }
  }
}

resource keyvaultDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  name: 'link-to-${spokeVirtualNetworkName}'
  parent: keyvaultDnsZone
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: spokeVirtualNetworkId }
  }
}

resource websitesDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  name: 'link-to-${spokeVirtualNetworkName}'
  parent: websitesDnsZone
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: { id: spokeVirtualNetworkId }
  }
} 
