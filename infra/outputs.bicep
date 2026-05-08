output acrLoginServer string = acr.properties.loginServer
output applicationGatewayUrl string = 'http://${publicIP.properties.ipAddress}'
output databaseFQDN string = '${dbDnsLabel}.${location}.azurecontainer.io'
