# ############## Creating VM using Service Now #############################

resource "azurerm_resource_group" "RG" {
  name     = "Window_Servers_Prodyut"
  location = "West Europe"
}

resource "azurerm_network_security_group" "NSG" {
  name                = "prodyut-nsg"
  location            = azurerm_resource_group.RG.location
  resource_group_name = azurerm_resource_group.RG.name

  # Inbound RDP Rule (Port 3389)
  security_rule {
    name                       = "allow-rdp"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Inbound HTTP Rule (Port 80)
  security_rule {
    name                       = "allow-http"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Inbound HTTPS Rule (Port 443)
  security_rule {
    name                       = "allow-https"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_virtual_network" "VN" {
  name                = "prodyut-network"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.RG.location
  resource_group_name = azurerm_resource_group.RG.name
}

resource "azurerm_subnet" "internal" {
  name                 = "internal"
  resource_group_name  = azurerm_resource_group.RG.name
  virtual_network_name = azurerm_virtual_network.VN.name
  address_prefixes     = ["10.0.0.0/24"]
}

resource "azurerm_public_ip" "public_ip" {
  name                = "prodyut-network-publicIP"
  resource_group_name = azurerm_resource_group.RG.name
  location            = azurerm_resource_group.RG.location
  allocation_method   = "Static"
}

resource "azurerm_network_interface" "NI" {
  name                = "prodyut-network-nic"
  location            = azurerm_resource_group.RG.location
  resource_group_name = azurerm_resource_group.RG.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.internal.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public_ip.id
  }
}

resource "azurerm_network_interface_security_group_association" "network_interface_security_group_association" {
  network_interface_id      = azurerm_network_interface.NI.id
  network_security_group_id = azurerm_network_security_group.NSG.id
}

resource "azurerm_windows_virtual_machine" "machin" {
  name                = "testprodyut"
  resource_group_name = azurerm_resource_group.RG.name
  location            = "West Europe"
  size                = "Standard_G2"
  admin_username      = "adminuser"
  admin_password      = "P@$$w0rd1234!"
  enable_automatic_updates = false
  provision_vm_agent = true
  network_interface_ids = [
    azurerm_network_interface.NI.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = "512"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }

  tags = {
    "Patch Group ID" = "T02-NONPROD-WEU-GR0"
  }
}

resource "azurerm_monitor_action_group" "main" {
  name                = "Aztiongroup-Cpu-Utlization"
  resource_group_name = azurerm_resource_group.RG.name
  short_name          = "exampleact"

  webhook_receiver {
    name        = "callmyapi"
    service_uri = "http://example.com/alert"
  }
}

resource "azurerm_monitor_metric_alert" "alert_cpu_utlization" {
  name                  = "Alert_Cpu-Utlization"
  resource_group_name   = azurerm_resource_group.RG.name
  scopes                = [azurerm_resource_group.RG.id]
  description           = "description"
  target_resource_type  = "Microsoft.Compute/virtualMachines"
  target_resource_location = "West Europe"
  window_size           = "PT15M" #lookback period#
  frequency             = "PT5M" #check every#
  severity              = 0

  
  criteria { 
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Percentage CPU"
    aggregation      = "Maximum"
    operator         = "GreaterThan"
    threshold        = 40
    #skip_metric_validation = true
  }

  action {
    action_group_id = azurerm_monitor_action_group.main.id
  }
}


resource "azurerm_managed_disk" "data_disk" {
  name                 = "DataDisk-Window-VM-disk1"
  location             = azurerm_resource_group.RG.location
  resource_group_name  = azurerm_resource_group.RG.name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = "128"
}

resource "azurerm_virtual_machine_data_disk_attachment" "data_disk-att" {
  managed_disk_id    = azurerm_managed_disk.data_disk.id
  virtual_machine_id = azurerm_windows_virtual_machine.machin.id
  lun                = "0"
  caching            = "ReadWrite"
}

# resource "azurerm_policy_definition" "patch_group_id_policy" {
#   name         = "enforce-patch-group-id-tag"
#   policy_type  = "Custom"
#   mode         = "Indexed"
#   display_name = "Enforce Patch Group ID Tag"
#   description  = "Ensures all resources have a 'Patch Group ID' tag with a value."

#   policy_rule = <<POLICY
# {
#   "if": {
#     "not": {
#       "field": "tags['Patch Group ID']",
#       "exists": true
#     }
#   },
#   "then": {
#     "effect": "deny"
#   }
# }
# POLICY

#   metadata = <<METADATA
#     {
#       "category": "Tags"
#     }
#   METADATA
# }

# resource "azurerm_subscription_policy_assignment" "patch_group_id_policy_assignment" {
#   name                 = "enforce-patch-group-id-tag"
#   policy_definition_id = azurerm_policy_definition.patch_group_id_policy.id
#   subscription_id = "/subscriptions/eb245505-9f45-4074-9d46-7e88e7159837"
# }


resource "azurerm_resource_group" "Patching_RG" {
  name     = "Patching_Windows"
  location = "West Europe"
}

resource "azurerm_maintenance_configuration" "maintenance_configuration" {
  for_each = { for Patch_Group_ID, properties in var.Patch_Group_ID : Patch_Group_ID => properties }
  name  = each.key
  resource_group_name  = azurerm_resource_group.Patching_RG.name
  location  = "West Europe"
  scope = "InGuestPatch"
  in_guest_user_patch_mode = "User"

  window {
    start_date_time = var.start_date_time
    expiration_date_time  = var.expiration_date_time
    duration  = "02:00"
    time_zone = "India Standard Time"
    recur_every = each.value.recur_every
  }

  install_patches {
    windows {
      classifications_to_include  = var.classifications_to_include
      kb_numbers_to_exclude  = var.kb_number_to_exclude
      kb_numbers_to_include  = var.kb_number_to_include
    }
    reboot  = "Always"
  }
  #tags = var.tags
}


resource "azurerm_maintenance_assignment_dynamic_scope" "maintenance_assignment_dynamic" {
  for_each = { for Patch_Group_ID, properties in var.Patch_Group_ID : Patch_Group_ID => properties }
  name = "scope-${each.key}"
  maintenance_configuration_id = azurerm_maintenance_configuration.maintenance_configuration[each.key].id

  filter {
    locations = ["East US"]
    os_types = ["Windows"]
    resource_groups = ["azurerm_resource_group.RG.name"]
    resource_types = ["Microsoft.Compute/virtualMachines"]
    tags {
      tag = "Patch Group ID"
      values = [each.key]
    }
  }
}
