AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
    TriggerServerEvent('SonoranCms:JobSync:PlayerSpawned')
end)