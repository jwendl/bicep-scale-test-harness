param resourceGroupLocation string = 'westus2'
param resourcePrefix string
param resourceSuffix string
param currentUserObjectId string

resource akv 'Microsoft.KeyVault/vaults@2019-09-01' = {
  name: '${resourcePrefix}akv${resourceSuffix}'
  location: '${resourceGroupLocation}'
  properties: {
      sku: {
          name: 'standard'
          family: 'A'
      }
      accessPolicies: [
        {
            tenantId: subscription().tenantId
            objectId: currentUserObjectId

            permissions: {
                secrets: [
                    'list'
                    'get'
                    'set'
                ]
            }
        }
      ]
      enableSoftDelete: false
      tenantId: subscription().tenantId
  }
}

resource acr 'Microsoft.ContainerRegistry/registries@2019-05-01' = {
  name: '${resourcePrefix}acr${resourceSuffix}'
  location: '${resourceGroupLocation}'
  sku: {
      name: 'Premium'
  }
}

resource lumi 'Microsoft.ManagedIdentity/userAssignedIdentities@2018-11-30' = {
  name: '${resourcePrefix}aumi${resourceSuffix}'
  location: '${resourceGroupLocation}'
}
