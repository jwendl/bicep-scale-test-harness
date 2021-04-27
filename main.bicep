param resourceGroupLocation string = 'westus2'
param resourcePrefix string
param resourceSuffix string
param currentUserObjectId string
param clusterVmSize string = 'Standard_D4_v3'
param sshKeyPath string
param sshPublicKey string
param principalClientId string
param versionTag string

resource lmainvnet 'Microsoft.Network/virtualNetworks@2020-06-01' = {
  name: '${resourcePrefix}vnet${resourceSuffix}'
  location: '${resourceGroupLocation}'
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.1.0.0/16'
      ]
    }
    subnets: [
      {
        name: '${resourcePrefix}vsub${resourceSuffix}'
        properties: {
          addressPrefix: '10.1.5.0/24'
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: '10.1.6.0/24'
        }
      }
    ]
  }
}

resource lmainnic 'Microsoft.Network/networkInterfaces@2020-06-01' = {
  name: '${resourcePrefix}mnic${resourceSuffix}'
  location: '${resourceGroupLocation}'
  properties: {
    networkSecurityGroup: {
      id: lmainsng.id
    }
    ipConfigurations: [
      {
        name: '${resourcePrefix}mnip${resourceSuffix}'
        properties: {
          publicIPAddress: {
            id: lmainpip.id
          }
          subnet: {
            id: lmainvnet.properties.subnets[0].id
          }
        }
      }
    ]
  }
}

resource lmainbas 'Microsoft.Network/bastionHosts@2020-06-01' = {
  name: '${resourcePrefix}mbas${resourceSuffix}'
  location: '${resourceGroupLocation}'
  properties: {
    ipConfigurations: [
      {
        name: 'IpConf'
        properties: {
          subnet: {
            id: lmainvnet.properties.subnets[1].id
          }
          publicIPAddress: {
            id: lmainbaspip.id
          }
        }
      }
    ]
  }
}

resource lmainsng 'Microsoft.Network/networkSecurityGroups@2020-06-01' = {
  name: '${resourcePrefix}mnsg${resourceSuffix}'
  location: '${resourceGroupLocation}'
  properties: {
    securityRules: [
      {
        name: 'web'
        properties: {
          priority: 1000
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '8089'
        }
      }
      {
        name: 'distributed'
        properties: {
          priority: 1100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '5557'
        }
      }
      {
        name: 'outbound-tcp'
        properties: {
          priority: 1200
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
      {
        name: 'outbound-udp'
        properties: {
          priority: 1300
          protocol: 'Udp'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '*'
        }
      }
    ]
  }
}

resource lmainpip 'Microsoft.Network/publicIPAddresses@2020-06-01' = {
  name: '${resourcePrefix}mpip${resourceSuffix}'
  location: '${resourceGroupLocation}'
  sku: {
    name: 'Basic'
  }
  properties: {
    publicIPAllocationMethod: 'Dynamic'
    publicIPAddressVersion: 'IPv4'
    dnsSettings: {
      domainNameLabel: '${resourcePrefix}mavm${resourceSuffix}'
    }
  }
}

resource lmainbaspip 'Microsoft.Network/publicIPAddresses@2020-06-01' = {
  name: '${resourcePrefix}bpip${resourceSuffix}'
  location: '${resourceGroupLocation}'
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
    dnsSettings: {
      domainNameLabel: '${resourcePrefix}bpip${resourceSuffix}'
    }
  }
}

resource lmain 'Microsoft.Compute/virtualMachines@2020-06-01' = {
  name: '${resourcePrefix}mavm${resourceSuffix}'
  location: '${resourceGroupLocation}'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${subscription().id}/resourceGroups/${resourceGroup().name}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${resourcePrefix}aumi${resourceSuffix}': {}
    }
  }
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_D8s_v3'
    }
    storageProfile: {
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-focal'
        sku: '20_04-lts-gen2'
        version: 'latest'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: lmainnic.id
        }
      ]
    }
    osProfile: {
      computerName: '${resourcePrefix}mavm${resourceSuffix}'
      adminUsername: 'azureuser'
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '${sshKeyPath}'
              keyData: '${sshPublicKey}'
            }
          ]
        }
      }
    }
  }
}

resource lmainext 'Microsoft.Compute/virtualMachines/extensions@2020-06-01' = {
  name: '${resourcePrefix}mavm${resourceSuffix}/${resourcePrefix}msext${resourceSuffix}'
  location: '${resourceGroupLocation}'
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.0'
    autoUpgradeMinorVersion: true
    forceUpdateTag: '${versionTag}'
    protectedSettings: {
      script: base64(concat('''
        export DEBIAN_FRONTEND=noninteractive;
        rm -rf /var/lib/dpkg/lock-frontend;
        rm -rf /var/lib/dpkg/lock;
        dpkg --configure -a;
        apt-get update;
        apt-get install ca-certificates curl apt-transport-https lsb-release --yes;
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --no-tty --yes --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg;
        curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --no-tty --yes --dearmor | tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null;
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null;
        echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/azure-cli.list > /dev/null;
        rm -rf /var/lib/dpkg/lock-frontend;
        rm -rf /var/lib/dpkg/lock;
        dpkg --configure -a;
        apt-get update;
        apt-get install azure-cli --yes;
        apt-get install docker-ce docker-ce-cli containerd.io --yes;
        groupadd -f docker;
        usermod -aG docker azureuser;
        az login --identity --username ''', '${principalClientId}', ''';
        az acr login -n ''', '${resourcePrefix}acr${resourceSuffix}', ''';
        docker kill $(docker ps -aq) 2> /dev/null;
        docker rm $(docker ps -aq) 2> /dev/null;
        docker rmi $(docker images -aq) 2> /dev/null;
        docker pull ''', '${resourcePrefix}acr${resourceSuffix}', '''.azurecr.io/locust-main:latest 2> /dev/null;
        docker run -d --name locust -p 5557:5557 -p 8089:8089 ''', '${resourcePrefix}acr${resourceSuffix}', '''.azurecr.io/locust-main:latest;
        docker ps -a;
      '''))
    }
  }
  dependsOn: [
    lmain
  ]
}

param secondaryCount int = 5
resource lsecondnic 'Microsoft.Network/networkInterfaces@2020-06-01' = [for index in range(0, secondaryCount): {
  name: concat('${resourcePrefix}snic${resourceSuffix}', index)
  location: '${resourceGroupLocation}'
  properties: {
    ipConfigurations: [
      {
        name: '${resourcePrefix}snip${resourceSuffix}'
        properties: {
          subnet: {
            id: lmainvnet.properties.subnets[0].id
          }
        }
      }
    ]
  }
}]

resource lsecondary 'Microsoft.Compute/virtualMachines@2020-06-01' = [for index in range(0, secondaryCount): {
  name: concat('${resourcePrefix}savm${resourceSuffix}', index)
  location: '${resourceGroupLocation}'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${subscription().id}/resourceGroups/${resourceGroup().name}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${resourcePrefix}aumi${resourceSuffix}': {}
    }
  }
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_D8s_v3'
    }
    storageProfile: {
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-focal'
        sku: '20_04-lts-gen2'
        version: 'latest'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: lsecondnic[index].id
        }
      ]
    }
    osProfile: {
      computerName: concat('${resourcePrefix}savm${resourceSuffix}', index)
      adminUsername: 'azureuser'
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '${sshKeyPath}'
              keyData: '${sshPublicKey}'
            }
          ]
        }
      }
    }
  }
}]

resource lsecondaryext 'Microsoft.Compute/virtualMachines/extensions@2020-06-01' = [for index in range(0, secondaryCount): {
  name: concat('${resourcePrefix}savm${resourceSuffix}', index, '/', '${resourcePrefix}ssext${resourceSuffix}', index)
  location: '${resourceGroupLocation}'
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.0'
    autoUpgradeMinorVersion: true
    forceUpdateTag: '${versionTag}'
    protectedSettings: {
      script: base64(concat('''
        export DEBIAN_FRONTEND=noninteractive;
        rm -rf /var/lib/dpkg/lock-frontend;
        rm -rf /var/lib/dpkg/lock;
        dpkg --configure -a;
        apt-get update;
        apt-get install ca-certificates curl apt-transport-https lsb-release --yes;
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --no-tty --yes --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg;
        curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --no-tty --yes --dearmor | tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null;
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null;
        echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/azure-cli.list > /dev/null;
        rm -rf /var/lib/dpkg/lock-frontend;
        rm -rf /var/lib/dpkg/lock;
        dpkg --configure -a;
        apt-get update;
        apt-get install azure-cli --yes;
        apt-get install docker-ce docker-ce-cli containerd.io --yes;
        groupadd -f docker;
        usermod -aG docker "azureuser";
        az login --identity --username ''', '${principalClientId}', ''';
        az acr login -n ''', '${resourcePrefix}acr${resourceSuffix}', ''';
        docker kill $(docker ps -aq) 2> /dev/null;
        docker rm $(docker ps -aq) 2> /dev/null;
        docker rmi $(docker images -aq) 2> /dev/null;
        docker pull ''', '${resourcePrefix}acr${resourceSuffix}', '''.azurecr.io/locust-secondary:latest 2> /dev/null;
        docker run -d --name locust -e "MAINHOST=''', '${resourcePrefix}mavm${resourceSuffix}', '''" -p 8089:8089 ''', '${resourcePrefix}acr${resourceSuffix}', '''.azurecr.io/locust-secondary:latest;
        docker ps -a;
      '''))
    }
  }
  dependsOn: [
    lsecondary[index]
  ]
}]
