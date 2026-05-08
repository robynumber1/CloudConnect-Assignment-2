// Ressourcen-Definitionen
param location string = resourceGroup().location
param acrName string = 'cloudconnectacr${uniqueString(resourceGroup().id)}'
param dbDnsLabel string = 'cloudconnect-db-${uniqueString(resourceGroup().id)}'
@secure()
param dbPassword string

// 1. Azure Container Registry (Basic) [cite: 65]
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  sku: { name: 'Basic' }
  properties: { adminUserEnabled: true }
}

// 2. App Service Plan (Linux, B1) [cite: 76]
resource appServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: 'asp-cloudconnect'
  location: location
  kind: 'linux'
  sku: { name: 'B1' }
  properties: { reserved: true }
}

// 3. Web App - Backend [cite: 77]
resource backendApp 'Microsoft.Web/sites@2022-09-01' = {
  name: 'app-backend-${uniqueString(resourceGroup().id)}'
  location: location
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      linuxFxVersion: 'DOCKER|${acr.name}.azurecr.io/cloudconnect-backend:v1'
      appSettings: [
        { name: 'DB_HOST', value: '${dbDnsLabel}.${location}.azurecontainer.io' }
        { name: 'DB_USER', value: 'postgres' }
        { name: 'DB_PASSWORD', value: dbPassword }
        { name: 'DB_NAME', value: 'cloudconnect' }
        { name: 'DOCKER_REGISTRY_SERVER_URL', value: 'https://${acr.name}.azurecr.io' }
        { name: 'DOCKER_REGISTRY_SERVER_USERNAME', value: acr.name }
        { name: 'DOCKER_REGISTRY_SERVER_PASSWORD', value: acr.listCredentials().passwords[0].value }
      ]
    }
  }
}

// 4. Web App - Frontend [cite: 77]
resource frontendApp 'Microsoft.Web/sites@2022-09-01' = {
  name: 'app-frontend-${uniqueString(resourceGroup().id)}'
  location: location
  properties: {
    serverFarmId: appServicePlan.id
    siteConfig: {
      linuxFxVersion: 'DOCKER|${acr.name}.azurecr.io/cloudconnect-frontend:v1'
      appSettings: [
        { name: 'DOCKER_REGISTRY_SERVER_URL', value: 'https://${acr.name}.azurecr.io' }
        { name: 'DOCKER_REGISTRY_SERVER_USERNAME', value: acr.name }
        { name: 'DOCKER_REGISTRY_SERVER_PASSWORD', value: acr.listCredentials().passwords[0].value }
      ]
    }
  }
}

// 5. Database (ACI) [cite: 82]
resource postgresContainer 'Microsoft.ContainerInstance/containerGroups@2023-05-01' = {
  name: 'aci-postgres'
  location: location
  properties: {
    containers: [
      {
        name: 'postgres'
        properties: {
          image: '${acr.name}.azurecr.io/postgres:15-alpine'
          resources: { requests: { cpu: 1, memoryInGB: 2 } }
          environmentVariables: [
            { name: 'POSTGRES_DB', value: 'cloudconnect' }
            { name: 'POSTGRES_USER', value: 'postgres' }
            { name: 'POSTGRES_PASSWORD', value: dbPassword }
          ]
          ports: [{ port: 5432 }]
        }
      }
    ]
    osType: 'Linux'
    imageRegistryCredentials: [
      {
        server: '${acr.name}.azurecr.io'
        username: acr.name
        password: acr.listCredentials().passwords[0].value
      }
    ]
    ipAddress: {
      type: 'Public'
      dnsNameLabel: dbDnsLabel
      ports: [{ protocol: 'TCP', port: 5432 }]
    }
  }
}

// 6. Application Gateway (Basic) [cite: 101]
// Hier wird das Netzwerk für das Gateway benötigt
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: 'vnet-appgw'
  location: location
  properties: {
    addressSpace: { addressPrefixes: ['10.0.0.0/16'] }
    subnets: [
      { name: 'subnet-gateway', properties: { addressPrefix: '10.0.1.0/24' } }
    ]
  }
}

resource publicIP 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: 'pip-appgw'
  location: location
  sku: { name: 'Standard' }
  properties: { publicIPAllocationMethod: 'Static' }
}

resource appGateway 'Microsoft.Network/applicationGateways@2023-05-01' = {
  name: 'agw-cloudconnect'
  location: location
  properties: {
    sku: { name: 'Standard_v2', tier: 'Standard_v2', capacity: 1 }
    gatewayIPConfigurations: [
      {
        name: 'ip-config'
        properties: { subnet: { id: vnet.properties.subnets[0].id } }
      }
    ]
    frontendIPConfigurations: [
      { name: 'frontend-ip', properties: { publicIPAddress: { id: publicIP.id } } }
    ]
    frontendPorts: [
      { name: 'port-80', properties: { port: 80 } }
    ]
    backendAddressPools: [
      { name: 'pool-frontend', properties: { backendAddresses: [{ fqdn: frontendApp.properties.defaultHostName }] } }
      { name: 'pool-backend', properties: { backendAddresses: [{ fqdn: backendApp.properties.defaultHostName }] } }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'http-settings'
        properties: {
          port: 80
          protocol: 'Http'
          cookieBasedAffinity: 'Disabled'
          pickHostNameFromBackendAddress: true // Wichtig für App Service [cite: 102]
        }
      }
    ]
    httpListeners: [
      {
        name: 'listener-http'
        properties: {
          frontendIPConfiguration: { id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', 'agw-cloudconnect', 'frontend-ip') }
          frontendPort: { id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', 'agw-cloudconnect', 'port-80') }
          protocol: 'Http'
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'rule-path-based'
        properties: {
          ruleType: 'PathBasedRouting'
          httpListener: { id: resourceId('Microsoft.Network/applicationGateways/httpListeners', 'agw-cloudconnect', 'listener-http') }
          urlPathMap: { id: resourceId('Microsoft.Network/applicationGateways/urlPathMaps', 'agw-cloudconnect', 'path-map') }
          priority: 10
        }
      }
    ]
    urlPathMaps: [
      {
        name: 'path-map'
        properties: {
          defaultBackendAddressPool: { id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', 'agw-cloudconnect', 'pool-frontend') }
          defaultBackendHttpSettings: { id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', 'agw-cloudconnect', 'http-settings') }
          pathRules: [
            {
              name: 'api-rule'
              properties: {
                paths: ['/api/*'] // Routing für das Backend [cite: 102]
                backendAddressPool: { id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', 'agw-cloudconnect', 'pool-backend') }
                backendHttpSettings: { id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', 'agw-cloudconnect', 'http-settings') }
              }
            }
          ]
        }
      }
    ]
  }
}
