# sonorancms_core
This resource is a core resource required by first party Sonoran CMS integrations for FiveM TM.

## Installation
[Click to view the installation guide](https://info.sonorancms.com/integration-capabilities/in-game-integration-resources/gta-rp-integrations/available-resources/core)

## If you facew any Issue Regurding Garage please follow this Steps :

Add Those Lines on your Garage Script >> Server >> Main.lua At the End 

```
local function getAllGarages()
    local garages = {}
    for k, v in pairs(Config.Garages) do
        garages[#garages+1] = {
            name = k,
            label = v.label,
            type = v.type,
            takeVehicle = v.takeVehicle,
            putVehicle = v.putVehicle,
            spawnPoint = v.spawnPoint,
            showBlip = v.showBlip,
            blipName = v.blipName,
            blipNumber = v.blipNumber,
            blipColor = v.blipColor,
            vehicle = v.vehicle
        }
    end
    return garages
end

exports('getAllGarages', getAllGarages)
```

### Planned Features
[ ] Priority Based Queue
