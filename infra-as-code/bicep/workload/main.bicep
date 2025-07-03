targetScope = 'resourceGroup'

@description('The region in which this architecture is deployed. Should match the region of the resource group.')
@minLength(1)
param location string = resourceGroup().location

@description('This is the base name for each Azure resource name (6-8 chars)')
@minLength(6)
@maxLength(8)
param baseName string

@description('Domain name to use for App Gateway')
@minLength(3)
param customDomainName string = 'contoso.com'

@description('The certificate data for app gateway TLS termination. The value is base64 encoded.')
@secure()
@minLength(1)
param appGatewayListenerCertificate string

@description('The name of the web deploy file. The file should reside in a deploy container in the Azure Storage account. Defaults to chatui.zip')
@minLength(5)
param publishFileName string = 'chatui.zip'

@description('Assign your user some roles to support fluid access when working in the Azure AI Foundry portal and its dependencies.')
@maxLength(36)
@minLength(36)
param yourPrincipalId string

@description('Set to true to opt-out of deployment telemetry.')
param telemetryOptOut bool = false

@description('The name of the Log Analytics workspace in the hub')
param hubLogAnalyticsWorkspaceName string

@description('The resource group name of the hub')
param hubResourceGroupName string

@description('The resource ID of the agent subnet in the spoke VNet')
param agentSubnetResourceId string

@description('The resource ID of the private endpoints subnet in the spoke VNet')
param privateEndpointSubnetResourceId string

@description('The resource ID of the app services subnet in the spoke VNet')
param appServicesSubnetResourceId string

@description('The resource ID of the app gateway subnet in the spoke VNet')
param appGatewaySubnetResourceId string

@description('The resource ID of the build agents subnet in the spoke VNet')
param buildAgentsSubnetResourceId string

@description('The resource ID of the spoke VNet')
param spokeVirtualNetworkId string

@description('The resource group name of the spoke where the VNet exists')
param spokeResourceGroupName string = 'rg-spoke-landingzone'

// Customer Usage Attribution Id
var varCuaid = 'a52aa8a8-44a8-46e9-b7a5-189ab3a64409'

// Get the Log Analytics workspace resource ID
var hubLogAnalyticsWorkspaceId = resourceId(hubResourceGroupName, 'Microsoft.OperationalInsights/workspaces', hubLogAnalyticsWorkspaceName)

// Extract resource names from resource IDs
var spokeVnetName = last(split(spokeVirtualNetworkId, '/'))
var agentSubnetName = last(split(agentSubnetResourceId, '/'))
var privateEndpointSubnetName = last(split(privateEndpointSubnetResourceId, '/'))
var appServicesSubnetName = last(split(appServicesSubnetResourceId, '/'))
var appGatewaySubnetName = last(split(appGatewaySubnetResourceId, '/'))
var buildAgentsSubnetName = last(split(buildAgentsSubnetResourceId, '/'))

// ---- New resources ----

@description('Deploy an example set of Azure Policies to help you govern your workload. Expand the policy set as desired.')
module applyAzurePolicies 'azure-policies.bicep' = {
  scope: resourceGroup()
  params: {
    baseName: baseName
  }
}

// Deploy the Azure AI Foundry account and Azure AI Agent service components.

@description('Deploy Azure AI Foundry with Azure AI Agent capability. No projects yet deployed.')
module deployAzureAIFoundry 'ai-foundry.bicep' = {
  scope: resourceGroup()
  params: {
    location: location
    baseName: baseName
    logAnalyticsWorkspaceName: hubLogAnalyticsWorkspaceName
    hubResourceGroupName: hubResourceGroupName
    agentSubnetResourceId: agentSubnetResourceId
    privateEndpointSubnetResourceId: privateEndpointSubnetResourceId
    aiFoundryPortalUserPrincipalId: yourPrincipalId
  }
}

@description('Deploys the Azure AI Agent dependencies, Azure Storage, Azure AI Search, and Cosmos DB.')
module deployAIAgentServiceDependencies 'ai-agent-service-dependencies.bicep' = {
  scope: resourceGroup()
  params: {
    location: location
    baseName: baseName
    logAnalyticsWorkspaceName: hubLogAnalyticsWorkspaceName
    hubResourceGroupName: hubResourceGroupName
    debugUserPrincipalId: yourPrincipalId
    privateEndpointSubnetResourceId: privateEndpointSubnetResourceId
  }
}

@description('Deploy the Bing account for Internet grounding data to be used by agents in the Azure AI Agent service.')
module deployBingAccount 'bing-grounding.bicep' = {
  scope: resourceGroup()
  params: {
    baseName: baseName
  }
}

@description('Create a managed identity for deployment scripts to wait for capability hosts.')
resource deploymentScriptManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: 'id-${baseName}-deployment-script'
  location: location
}

@description('Assign the managed identity Contributor role for deployment script operations.')
resource deploymentScriptRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(deploymentScriptManagedIdentity.id, resourceGroup().id, 'Contributor')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor
    principalId: deploymentScriptManagedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

@description('Deploy the Azure AI Foundry project into the AI Foundry account. This is the project is the home of the Azure AI Agent service.')
module deployAzureAiFoundryProject 'ai-foundry-project.bicep' = {
  scope: resourceGroup()
  params: {
    location: location
    existingAiFoundryName: deployAzureAIFoundry.outputs.aiFoundryName
    existingAISearchAccountName: deployAIAgentServiceDependencies.outputs.aiSearchName
    existingCosmosDbAccountName: deployAIAgentServiceDependencies.outputs.cosmosDbAccountName
    existingStorageAccountName: deployAIAgentServiceDependencies.outputs.storageAccountName
    existingBingAccountName: deployBingAccount.outputs.bingAccountName
    existingWebApplicationInsightsResourceName: deployApplicationInsights.outputs.applicationInsightsName
    existingManagedIdentityId: deploymentScriptManagedIdentity.id
  }
  dependsOn: [
    deploymentScriptRoleAssignment // Ensure the managed identity has proper permissions before using it
  ]
}

// Deploy the Azure Web App resources for the chat UI.

@description('Deploy an Azure Storage account that is used by the Azure Web App for the deployed application code.')
module deployWebAppStorage 'web-app-storage.bicep' = {
  scope: resourceGroup()
  params: {
    location: location
    baseName: baseName
    logAnalyticsWorkspaceName: hubLogAnalyticsWorkspaceName
    hubResourceGroupName: hubResourceGroupName
    spokeResourceGroupName: spokeResourceGroupName
    virtualNetworkName: spokeVnetName
    privateEndpointsSubnetName: privateEndpointSubnetName
    debugUserPrincipalId: yourPrincipalId
  }
  dependsOn: [
    deployAIAgentServiceDependencies // There is a Storage account in the AI Agent dependencies module, both will be updating the same private DNS zone, want to run them in series to avoid conflict errors.
  ]
}

@description('Deploy Azure Key Vault. In this architecture, it\'s used to store the certificate for the Application Gateway.')
module deployKeyVault 'key-vault.bicep' = {
  scope: resourceGroup()
  params: {
    location: location
    baseName: baseName
    logAnalyticsWorkspaceName: hubLogAnalyticsWorkspaceName
    hubResourceGroupName: hubResourceGroupName
    spokeResourceGroupName: spokeResourceGroupName
    virtualNetworkName: spokeVnetName
    privateEndpointsSubnetName: privateEndpointSubnetName
    appGatewayListenerCertificate: appGatewayListenerCertificate
  }
}

@description('Deploy Application Insights. Used by the Azure Web App to monitor the deployed application and connected to the Azure AI Foundry project.')
module deployApplicationInsights 'application-insights.bicep' = {
  scope: resourceGroup()
  params: {
    location: location
    baseName: baseName
    logAnalyticsWorkspaceName: hubLogAnalyticsWorkspaceName
    hubResourceGroupName: hubResourceGroupName
  }
}

@description('Deploy the web app for the front end demo UI. The web application will call into the Azure AI Agent service.')
module deployWebApp 'web-app.bicep' = {
  scope: resourceGroup()
  params: {
    location: location
    baseName: baseName
    logAnalyticsWorkspaceName: hubLogAnalyticsWorkspaceName
    hubResourceGroupName: hubResourceGroupName
    spokeResourceGroupName: spokeResourceGroupName
    publishFileName: publishFileName
    virtualNetworkName: spokeVnetName
    appServicesSubnetName: appServicesSubnetName
    privateEndpointsSubnetName: privateEndpointSubnetName
    existingWebAppDeploymentStorageAccountName: deployWebAppStorage.outputs.appDeployStorageName
    existingWebApplicationInsightsResourceName: deployApplicationInsights.outputs.applicationInsightsName
    existingAzureAiFoundryResourceName: deployAzureAIFoundry.outputs.aiFoundryName
    existingAzureAiFoundryProjectName: deployAzureAiFoundryProject.outputs.aiAgentProjectName
  }
}

@description('Deploy an Azure Application Gateway with WAF and a custom domain name + TLS cert.')
module deployApplicationGateway 'application-gateway.bicep' = {
  scope: resourceGroup()
  params: {
    location: location
    baseName: baseName
    logAnalyticsWorkspaceName: hubLogAnalyticsWorkspaceName
    hubResourceGroupName: hubResourceGroupName
    spokeResourceGroupName: spokeResourceGroupName
    customDomainName: customDomainName
    appName: deployWebApp.outputs.appName
    virtualNetworkName: spokeVnetName
    applicationGatewaySubnetName: appGatewaySubnetName
    keyVaultName: deployKeyVault.outputs.keyVaultName
    gatewayCertSecretKey: deployKeyVault.outputs.gatewayCertSecretKey
  }
}

// Optional Deployment for Customer Usage Attribution
module customerUsageAttributionModule 'customerUsageAttribution/cuaIdResourceGroup.bicep' = if (!telemetryOptOut) {
  #disable-next-line no-loc-expr-outside-params // Only to ensure telemetry data is stored in same location as deployment. See https://github.com/Azure/ALZ-Bicep/wiki/FAQ#why-are-some-linter-rules-disabled-via-the-disable-next-line-bicep-function for more information
  name: 'pid-${varCuaid}-${uniqueString(resourceGroup().location)}'
  scope: resourceGroup()
  params: {}
}
