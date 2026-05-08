param location string = resourceGroup().location

@description('Präfix für alle Ressourcennamen')
param prefix string = 'cloudconnect'

@description('Eindeutiger Name für die ACR')
param acrName string = '${prefix}acr${uniqueString(resourceGroup().id)}'

@description('DNS Label für die Datenbank (ACI)')
param dbDnsLabel string = '${prefix}-db-${uniqueString(resourceGroup().id)}'

@secure()
@description('Passwort für PostgreSQL')
param dbPassword string
