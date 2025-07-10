targetScope = 'resourceGroup'

@minLength(1)
param localDNSForwardingRulesetName string

@minLength(79)
param remoteVirtualNetworkId string

resource localDnsForwardingRuleset 'Microsoft.Network/dnsForwardingRulesets@2022-07-01' existing = {
  name: localDNSForwardingRulesetName
}

resource link 'Microsoft.Network/dnsForwardingRulesets/virtualNetworkLinks@2022-07-01' = {
  name: 'spoke-resolver-lnk'
  parent: localDnsForwardingRuleset
  properties: {
    virtualNetwork: {
      id: remoteVirtualNetworkId
    }
  }
}
