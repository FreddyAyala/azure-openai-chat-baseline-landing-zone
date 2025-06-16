# Azure OpenAI Agent Service Chat Baseline Reference Implementation in an Application Landing Zone

This reference implementation extends the foundation set in the [Azure OpenAI end-to-end chat baseline](https://github.com/Azure-Samples/openai-end-to-end-baseline/) reference implementation. Specifically, this repository takes that reference implementation and deploys it within an application landing zone using Azure AI Agent service as the orchestrator.

If you haven't yet, you should start by reviewing the [Azure OpenAI chat baseline architecture in an Azure landing zone](https://learn.microsoft.com/azure/architecture/ai-ml/architecture/azure-openai-baseline-landing-zone) article on Microsoft Learn. It sets important context for this implementation.

## Azure Landing Zone Integration

This application landing zone deployment assumes you are using a typical Azure landing zone approach with platform and workload separation. This deployment assumes many pre-existing platform resources and deploys nothing outside of the scope of the application landing zone. To fully deploy this repo, it must be done as part of your organization's actual subscription vending process.

Key differences when integrating into an application landing zone:

- **Virtual Network**: Deployed and configured by the platform team, including UDR and DNS configuration
- **DNS Forwarding**: Uses central DNS servers like Azure Firewall DNS Proxy or Azure Private DNS Resolver
- **Bastion Host**: Uses centralized bastion service from platform landing zone subscriptions
- **Private DNS Zones**: Integrates with centralized private DNS zones at platform level
- **Network Virtual Appliance (NVA)**: Outbound connectivity through centralized NVA with UDRs
- **Compliance**: Must adhere to centralized governance policies

## Architecture

The implementation covers three main scenarios:

1. **Setting up Azure AI Foundry to host agents** - Azure AI Foundry hosts Azure AI Agent service with private endpoints and egress through a delegated subnet routed via Azure Firewall.

2. **Deploying an agent into Azure AI Agent service** - Agents can be created via Azure AI Foundry portal, SDK, or REST API from within the private network.

3. **Invoking the agent from .NET code in Azure App Service** - A chat UI application deployed in private Azure App Service, accessed through Application Gateway (WAF).

## Deployment Guide

### Prerequisites

- An application landing zone subscription with:
  - One virtual network (spoke) - At least a `/22`, DNS configured for hub resolution
  - One unassociated route table for Internet-bound traffic
  - Private endpoint DNS registration mechanism
  - Required quota and resource provider registrations

- Platform-provided resources:
  - Virtual network with hub/spoke peering
  - DNS configuration
  - Bastion service
  - Private DNS zones
  - Network Virtual Appliance

- The subscription must have the following resource providers registered:
  - `Microsoft.AlertsManagement`
  - `Microsoft.App`
  - `Microsoft.Bing`
  - `Microsoft.CognitiveServices`
  - `Microsoft.Compute`
  - `Microsoft.DocumentDB`
  - `Microsoft.Insights`
  - `Microsoft.KeyVault`
  - `Microsoft.ManagedIdentity`
  - `Microsoft.Network`
  - `Microsoft.OperationalInsights`
  - `Microsoft.Search`
  - `Microsoft.Storage`
  - `Microsoft.Web`

- The subscription must have the following quota available:
  - Application Gateways: 1 WAF_v2 tier instance
  - App Service Plans: P1v3 (AZ), 3 instances
  - Azure AI Search (S - Standard): 1
  - Azure Cosmos DB: 1 account
  - OpenAI model: GPT-4 model deployment with 50k TPM capacity
  - DDoS Protection Plans: 1
  - Public IPv4 Addresses - Standard: 4
  - Standard DSv3 Family vCPU: 2
  - Storage Accounts: 2

- Your deployment user must have:
  - Ability to assign Azure roles on newly created resources
  - Ability to purge deleted AI services resources

- Required tools:
  - Azure CLI
  - OpenSSL CLI

### 1. Deploy Infrastructure

1. Clone this repository:
   ```bash
   git clone https://github.com/Azure-Samples/azure-openai-chat-baseline-landing-zone
   cd azure-openai-chat-baseline-landing-zone
   ```

2. Log in and set subscription:
   ```bash
   az login
   az account set --subscription xxxxx
   ```

3. Generate App Gateway certificate:
   ```bash
   DOMAIN_NAME_APPSERV="contoso.com"
   openssl req -x509 -nodes -days 365 -newkey rsa:2048 -out appgw.crt -keyout appgw.key -subj "/CN=${DOMAIN_NAME_APPSERV}/O=Contoso" -addext "subjectAltName = DNS:${DOMAIN_NAME_APPSERV}" -addext "keyUsage = digitalSignature" -addext "extendedKeyUsage = serverAuth"
   openssl pkcs12 -export -out appgw.pfx -in appgw.crt -inkey appgw.key -passout pass:
   APP_GATEWAY_LISTENER_CERTIFICATE=$(cat appgw.pfx | base64 | tr -d '\n')
   ```

4. Update the **parameters.alz.json** file with your platform team's provided resources:
   - `existingResourceIdForSpokeVirtualNetwork`
   - `existingResourceIdForUdrForInternetTraffic`
   - `bastionSubnetAddresses`
   - Subnet address prefixes

5. Set deployment variables:
   ```bash
   LOCATION=eastus
   BASE_NAME=<unique 6-8 character name>
   RESOURCE_GROUP="rg-chat-alz-baseline-${LOCATION}"
   ```

6. Deploy resources:
   ```bash
   az group create -l $LOCATION -n $RESOURCE_GROUP
   PRINCIPAL_ID=$(az ad signed-in-user show --query id -o tsv)

   az deployment sub create -f ./infra-as-code/bicep/main.bicep \
     -n chat-baseline-000 \
     -l $LOCATION \
     -p @./infra-as-code/bicep/parameters.alz.json \
     -p workloadResourceGroupName=${RESOURCE_GROUP} \
     -p appGatewayListenerCertificate=${APP_GATEWAY_LISTENER_CERTIFICATE} \
     -p baseName=${BASE_NAME} \
     -p yourPrincipalId=${PRINCIPAL_ID}
   ```

### 2. Deploy Agent in Azure AI Agent Service

1. Connect to your network via platform-provided access method (Bastion/VPN/etc.)

2. From a network-connected terminal:
   ```powershell
   $BASE_NAME="<same value as before>"
   $RESOURCE_GROUP="rg-chat-alz-baseline-${BASE_NAME}"
   $AI_FOUNDRY_NAME="aif${BASE_NAME}"
   $BING_CONNECTION_NAME="bingaiagent"
   $AI_FOUNDRY_PROJECT_NAME="projchat"
   $MODEL_CONNECTION_NAME="agent-model"
   $BING_CONNECTION_ID="$(az cognitiveservices account show -n $AI_FOUNDRY_NAME -g $RESOURCE_GROUP --query 'id' --out tsv)/projects/${$AI_FOUNDRY_PROJECT_NAME}$/connections/${BING_CONNECTION_NAME}"
   $AI_FOUNDRY_AGENT_CREATE_URL="https://${AI_FOUNDRY_NAME}.services.ai.azure.com/api/projects/${AI_FOUNDRY_PROJECT_NAME}/assistants?api-version=2025-05-15-preview"
   ```

3. Deploy the agent:
   ```powershell
   Invoke-WebRequest -Uri "https://github.com/Azure-Samples/azure-openai-chat-baseline-landing-zone/raw/main/agents/chat-with-bing.json" -OutFile "chat-with-bing.json"
   ${c:chat-with-bing-output.json} = ${c:chat-with-bing.json} -replace 'MODEL_CONNECTION_NAME', $MODEL_CONNECTION_NAME -replace 'BING_CONNECTION_ID', $BING_CONNECTION_ID
   az rest -u $AI_FOUNDRY_AGENT_CREATE_URL -m "post" --resource "https://ai.azure.com" -b @chat-with-bing-output.json
   $AGENT_ID="$(az rest -u $AI_FOUNDRY_AGENT_CREATE_URL -m 'get' --resource 'https://ai.azure.com' --query 'data[0].id' -o tsv)"
   ```

### 3. Deploy Chat Front-end Web App

1. Download and upload the web UI:
   ```powershell
   Invoke-WebRequest -Uri https://github.com/Azure-Samples/azure-openai-chat-baseline-landing-zone/raw/main/website/chatui.zip -OutFile chatui.zip
   az storage blob upload -f chatui.zip --account-name "stwebapp${BASE_NAME}" --auth-mode login -c deploy -n chatui.zip
   ```

2. Configure and restart the web app:
   ```powershell
   az webapp config appsettings set -n "app-${BASE_NAME}" -g $RESOURCE_GROUP --settings AIAgentId="${AGENT_ID}"
   az webapp restart --name "app-${BASE_NAME}" --resource-group $RESOURCE_GROUP
   ```

### 4. Test the Deployment

1. Get the Application Gateway IP:
   ```bash
   APPGW_PUBLIC_IP=$(az network public-ip show -g $RESOURCE_GROUP -n "pip-$BASE_NAME" --query [ipAddress] --output tsv)
   ```

2. Add DNS record (or modify hosts file):
   ```
   ${APPGW_PUBLIC_IP} www.${DOMAIN_NAME_APPSERV}
   ```

3. Access the site at `https://www.${DOMAIN_NAME_APPSERV}`

## Clean Up Resources

Most Azure resources deployed will incur ongoing charges unless removed. This deployment typically costs over $100/day. To clean up:

```bash
az group delete -n $RESOURCE_GROUP -y

az keyvault purge -n kv-${BASE_NAME}
az cognitiveservices account purge -g $RESOURCE_GROUP -l $LOCATION -n aif-${BASE_NAME}
```

## Contributions

Please see our [Contributor guide](./CONTRIBUTING.md).

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).

With :heart: from Azure Patterns & Practices, [Azure Architecture Center](https://azure.com/architecture).