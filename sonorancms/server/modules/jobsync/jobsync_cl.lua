RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    TriggerServerEvent('SonoranCms:JobSync:PlayerSpawned')
end)

RegisterNetEvent('QBCore:Client:OnJobUpdate', function(JobInfo)
    TriggerServerEvent('SonoranCms:JobSync:JobUpdate', JobInfo)
end)