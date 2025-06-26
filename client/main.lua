local ESX = nil
local QBCore = nil
local QBox = nil
local medicCalled = false
local medicPed = nil
local ambulanceVehicle = nil
local drivingToPlayer = false
local medicBlip = nil

if Config.Framework == 'auto' then
    if GetResourceState('es_extended') == 'started' then
        ESX = exports['es_extended']:getSharedObject()
        Config.Framework = 'esx'
    elseif GetResourceState('qb-core') == 'started' then
        QBCore = exports['qb-core']:GetCoreObject()
        Config.Framework = 'qb'
    elseif GetResourceState('qbx_core') == 'started' then
        QBox = exports.qbx_core
        Config.Framework = 'qbox'
    end
elseif Config.Framework == 'esx' then
    ESX = exports['es_extended']:getSharedObject()
elseif Config.Framework == 'qb' then
    QBCore = exports['qb-core']:GetCoreObject()
elseif Config.Framework == 'qbox' then
    QBox = exports.qbx_core
end

function IsPlayerAllowed()
    if #Config.AllowedJobs == 0 then
        return true
    end
    
    local playerJob = nil
    
    if Config.Framework == 'esx' then
        if ESX.PlayerData and ESX.PlayerData.job then
            playerJob = ESX.PlayerData.job.name
        end
    elseif Config.Framework == 'qb' then
        local PlayerData = QBCore.Functions.GetPlayerData()
        if PlayerData and PlayerData.job then
            playerJob = PlayerData.job.name
        end
    elseif Config.Framework == 'qbox' then
        local PlayerData = QBox:GetPlayerData()
        if PlayerData and PlayerData.job then
            playerJob = PlayerData.job.name
        end
    end
    
    if not playerJob then
        return true
    end
    
    for _, job in pairs(Config.AllowedJobs) do
        if job == playerJob then
            return true
        end
    end
    
    return false
end

function IsPlayerDead()
    local playerPed = PlayerPedId()
    local health = GetEntityHealth(playerPed)
    
    if Config.Framework == 'esx' then
        if ESX.PlayerData and ESX.PlayerData.dead then
            return true
        end
        
        if GetResourceState('wasabi_ambulance') == 'started' and exports.wasabi_ambulance and exports.wasabi_ambulance:isPlayerDead() then
            return true
        end
        
        if health <= 0 or health <= 100 then
            return true
        end
        
        return false
    elseif Config.Framework == 'qb' then
        local PlayerData = QBCore.Functions.GetPlayerData()
        
        if PlayerData and PlayerData.metadata and (PlayerData.metadata['isdead'] or PlayerData.metadata['inlaststand']) then
            return true
        end
        
        if GetResourceState('wasabi_ambulance') == 'started' and exports.wasabi_ambulance and exports.wasabi_ambulance:isPlayerDead() then
            return true
        end
        
        return false
    elseif Config.Framework == 'qbox' then
        local PlayerData = QBox:GetPlayerData()
        
        if PlayerData and PlayerData.metadata and (PlayerData.metadata['isdead'] or PlayerData.metadata['inlaststand']) then
            return true
        end
        
        if GetResourceState('wasabi_ambulance') == 'started' and exports.wasabi_ambulance and exports.wasabi_ambulance:isPlayerDead() then
            return true
        end
        
        return false
    else
        if GetResourceState('wasabi_ambulance') == 'started' and exports.wasabi_ambulance and exports.wasabi_ambulance:isPlayerDead() then
            return true
        end
        
        return health <= 0
    end
end

function HasMoney()
    local hasMoney = false
    local received = false
    
    TriggerServerCallback('fearx-npcmedic:checkMoney', function(result)
        hasMoney = result
        received = true
    end)
    
    while not received do
        Wait(1)
    end
    
    return hasMoney
end

function TriggerServerCallback(name, cb, ...)
    if Config.Framework == 'esx' then
        ESX.TriggerServerCallback(name, cb, ...)
    elseif Config.Framework == 'qb' then
        QBCore.Functions.TriggerCallback(name, cb, ...)
    elseif Config.Framework == 'qbox' then
        QBox:TriggerCallback(name, cb, ...)
    else
        local p = promise.new()
        TriggerServerEvent(name, ...)
        RegisterNetEvent(name .. ':callback', function(result)
            p:resolve(result)
        end)
        cb(Citizen.Await(p))
    end
end

function ShowNotification(message)
    lib.notify({
        title = 'Emergency Services',
        description = message,
        type = 'info'
    })
end

function ShowMedicMenu()
    local options = {
        {
            title = 'Call Medic',
            description = 'Request emergency medical assistance ($' .. Config.Cost .. ')',
            icon = 'fas fa-ambulance',
            onSelect = function()
                CallMedic()
            end
        },
        {
            title = 'Reset Medic Script',
            description = 'Fix any bugs with the medic system',
            icon = 'fas fa-refresh',
            onSelect = function()
                ResetMedicScript()
            end
        },
        {
            title = 'Close Menu',
            description = 'Close this menu',
            icon = 'fas fa-times',
            onSelect = function()
                lib.hideContext()
            end
        }
    }

    lib.registerContext({
        id = 'fearx_medic_menu',
        title = 'Emergency Services',
        options = options
    })

    lib.showContext('fearx_medic_menu')
end

function CallMedic()
    if not IsPlayerAllowed() then
        ShowNotification(Config.Messages.notAllowed)
        return
    end
    
    if medicCalled then
        ShowNotification(Config.Messages.alreadyCalled)
        return
    end
    
    if not IsPlayerDead() then
        ShowNotification(Config.Messages.notDead)
        return
    end
    
    if not HasMoney() then
        ShowNotification(Config.Messages.noMoney)
        return
    end
    
    TriggerServerEvent('fearx-npcmedic:logUsage')
    
    medicCalled = true
    ShowNotification(Config.Messages.calling)
    
    SetTimeout(Config.WaitTime * 1000, function()
        if Config.Ambulance.enabled then
            SpawnAmbulanceAndDrive()
        else
            SpawnMedic()
        end
    end)
end

function ResetMedicScript()
    if DoesEntityExist(medicPed) then
        DeleteEntity(medicPed)
    end
    
    if DoesEntityExist(ambulanceVehicle) then
        DeleteEntity(ambulanceVehicle)
    end
    
    if lib.progressActive() then
        lib.cancelProgress()
    end
    
    if DoesBlipExist(medicBlip) then
        RemoveBlip(medicBlip)
        medicBlip = nil
    end
    
    medicCalled = false
    medicPed = nil
    ambulanceVehicle = nil
    drivingToPlayer = false
    
    ShowNotification('Medic script has been reset successfully!')
end

function GetSpawnPoint()
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local spawnDistance = 200.0
    local foundSpawn = false
    local spawnCoords = nil
    local spawnHeading = 0.0
    
    for i = 1, 50 do
        local angle = math.random() * 2 * math.pi
        local x = playerCoords.x + math.cos(angle) * spawnDistance
        local y = playerCoords.y + math.sin(angle) * spawnDistance
        local z = playerCoords.z
        
        local found, groundZ = GetGroundZFor_3dCoord(x, y, z + 50.0, false)
        if found and groundZ and groundZ > 0 then
            local testCoords = vector3(x, y, groundZ)
            local roadExists, roadCoords, heading = GetClosestRoad(testCoords.x, testCoords.y, testCoords.z, 1, 1, false, true, false)
            
            if roadExists and #(roadCoords - testCoords) < 30.0 then
                spawnCoords = roadCoords
                spawnHeading = heading
                foundSpawn = true
                break
            end
        end
    end
    
    if not foundSpawn then
        local roadExists, roadCoords, heading = GetClosestRoad(playerCoords.x, playerCoords.y, playerCoords.z, 0, 1, false, true, false)
        if roadExists then
            spawnCoords = roadCoords
            spawnHeading = heading
        else
            spawnCoords = vector3(playerCoords.x + 50.0, playerCoords.y + 50.0, playerCoords.z)
            spawnHeading = 0.0
        end
    end
    
    return spawnCoords, spawnHeading
end

function SpawnAmbulanceAndDrive()
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local spawnCoords, spawnHeading = GetSpawnPoint()
    
    local vehicleHash = GetHashKey(Config.AmbulanceModel)
    local pedHash = GetHashKey(Config.MedicModel)
    
    RequestModel(vehicleHash)
    RequestModel(pedHash)
    
    while not HasModelLoaded(vehicleHash) or not HasModelLoaded(pedHash) do
        Wait(1)
    end
    
    ambulanceVehicle = CreateVehicle(vehicleHash, spawnCoords.x, spawnCoords.y, spawnCoords.z, spawnHeading, true, false)
    SetEntityAsMissionEntity(ambulanceVehicle, true, true)
    SetVehicleOnGroundProperly(ambulanceVehicle)
    SetVehicleEngineOn(ambulanceVehicle, true, true, false)
    SetVehicleLights(ambulanceVehicle, 2)
    SetVehicleSiren(ambulanceVehicle, true)
    
    medicPed = CreatePedInsideVehicle(ambulanceVehicle, 26, pedHash, -1, true, false)
    SetEntityAsMissionEntity(medicPed, true, true)
    SetBlockingOfNonTemporaryEvents(medicPed, true)
    SetPedCanRagdoll(medicPed, false)
    SetDriverAbility(medicPed, 1.0)
    SetDriverAggressiveness(medicPed, 0.0)
    
    SetVehicleIsConsideredByPlayer(ambulanceVehicle, false)
    SetEntityInvincible(ambulanceVehicle, true)
    SetVehicleCanBeVisiblyDamaged(ambulanceVehicle, false)
    
    medicBlip = AddBlipForEntity(ambulanceVehicle)
    SetBlipSprite(medicBlip, 23)
    SetBlipColour(medicBlip, 1)
    SetBlipScale(medicBlip, 0.8)
    SetBlipAsShortRange(medicBlip, false)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Emergency Medic")
    EndTextCommandSetBlipName(medicBlip)
    
    ShowNotification(Config.Messages.medicDriving)
    
    drivingToPlayer = true
    TaskVehicleDriveToCoord(medicPed, ambulanceVehicle, playerCoords.x, playerCoords.y, playerCoords.z, Config.Ambulance.speed, 1, vehicleHash, 2883621, 5.0, true)
    
    local startTime = GetGameTimer()
    local timeoutReached = false
    
    CreateThread(function()
        while drivingToPlayer and not timeoutReached do
            local currentCoords = GetEntityCoords(ambulanceVehicle)
            local distance = #(currentCoords - playerCoords)
            
            SetVehicleUndriveable(ambulanceVehicle, false)
            ClearAreaOfVehicles(currentCoords.x, currentCoords.y, currentCoords.z, 15.0, false, false, false, false, false)
            
            local nearbyVehicles = GetNearbyVehicles(currentCoords, 20.0)
            for _, vehicle in pairs(nearbyVehicles) do
                if vehicle ~= ambulanceVehicle and DoesEntityExist(vehicle) then
                    local vehicleDriver = GetPedInVehicleSeat(vehicle, -1)
                    if DoesEntityExist(vehicleDriver) and not IsPedAPlayer(vehicleDriver) then
                        TaskVehicleTempAction(vehicleDriver, vehicle, 27, 3000)
                    end
                end
            end
            
            if distance < 10.0 then
                drivingToPlayer = false
                AmbulanceArrived()
                break
            end
            
            if GetGameTimer() - startTime > (Config.Ambulance.timeout * 1000) then
                timeoutReached = true
                drivingToPlayer = false
                ShowNotification('Ambulance timeout reached, teleporting to your location...')
                TeleportAmbulanceToPlayer()
                break
            end
            
            Wait(500)
        end
    end)
end

function GetNearbyVehicles(coords, radius)
    local vehicles = {}
    local handle, vehicle = FindFirstVehicle()
    local finished = false
    
    repeat
        if DoesEntityExist(vehicle) then
            local vehicleCoords = GetEntityCoords(vehicle)
            local distance = #(coords - vehicleCoords)
            if distance <= radius then
                table.insert(vehicles, vehicle)
            end
        end
        finished, vehicle = FindNextVehicle(handle)
    until not finished
    
    EndFindVehicle(handle)
    return vehicles
end

function TeleportAmbulanceToPlayer()
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local teleportCoords = vector3(playerCoords.x + 5.0, playerCoords.y + 5.0, playerCoords.z)
    
    local found, groundZ = GetGroundZFor_3dCoord(teleportCoords.x, teleportCoords.y, teleportCoords.z + 10.0, false)
    if found and groundZ then
        teleportCoords = vector3(teleportCoords.x, teleportCoords.y, groundZ)
    end
    
    SetEntityCoords(ambulanceVehicle, teleportCoords.x, teleportCoords.y, teleportCoords.z, false, false, false, true)
    SetEntityHeading(ambulanceVehicle, GetEntityHeading(playerPed) + 90.0)
    SetVehicleOnGroundProperly(ambulanceVehicle)
    
    Wait(1000)
    
    AmbulanceArrived()
end

function AmbulanceArrived()
    ShowNotification(Config.Messages.medicArrived)
    
    SetVehicleSiren(ambulanceVehicle, false)
    SetVehicleLights(ambulanceVehicle, 0)
    
    if DoesBlipExist(medicBlip) then
        RemoveBlip(medicBlip)
    end
    
    TaskLeaveVehicle(medicPed, ambulanceVehicle, 0)
    
    Wait(3000)
    
    medicBlip = AddBlipForEntity(medicPed)
    SetBlipSprite(medicBlip, 61)
    SetBlipColour(medicBlip, 1)
    SetBlipScale(medicBlip, 0.8)
    SetBlipAsShortRange(medicBlip, false)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Emergency Medic")
    EndTextCommandSetBlipName(medicBlip)
    
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    
    TaskGoToEntity(medicPed, playerPed, -1, 2.0, 2.0, 1073741824, 0)
    
    CreateThread(function()
        while DoesEntityExist(medicPed) do
            local medicCoords = GetEntityCoords(medicPed)
            local distance = #(medicCoords - playerCoords)
            
            if distance < 3.0 then
                TaskTurnPedToFaceEntity(medicPed, playerPed, 2000)
                Wait(2000)
                StartHealing()
                break
            end
            
            Wait(500)
        end
    end)
end

function SpawnMedic()
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local spawnCoords = vector3(playerCoords.x + 2.0, playerCoords.y + 2.0, playerCoords.z)
    
    local pedHash = GetHashKey(Config.MedicModel)
    RequestModel(pedHash)
    while not HasModelLoaded(pedHash) do
        Wait(1)
    end
    
    medicPed = CreatePed(4, pedHash, spawnCoords.x, spawnCoords.y, spawnCoords.z, 0.0, true, false)
    SetEntityAsMissionEntity(medicPed, true, true)
    SetBlockingOfNonTemporaryEvents(medicPed, true)
    SetPedCanRagdoll(medicPed, false)
    
    ShowNotification(Config.Messages.arriving)
    
    Wait(1000)
    
    TaskTurnPedToFaceEntity(medicPed, playerPed, 2000)
    Wait(2000)
    
    StartHealing()
end

function StartHealing()
    ShowNotification(Config.Messages.healing)
    
    RequestAnimDict('mini@cpr@char_a@cpr_str')
    while not HasAnimDictLoaded('mini@cpr@char_a@cpr_str') do
        Wait(1)
    end
    
    TaskPlayAnim(medicPed, 'mini@cpr@char_a@cpr_str', 'cpr_pumpchest', 8.0, -8.0, -1, 1, 0, false, false, false)
    
    if lib.progressBar({
        duration = Config.HealTime * 1000,
        label = Config.ProgressBarText,
        useWhileDead = true,
        canCancel = true,
        disable = {
            car = true,
            move = true,
            combat = true
        }
    }) then
        HealPlayer()
        ShowNotification(Config.Messages.healed)
        TriggerServerEvent('fearx-npcmedic:processPayment')
        CleanupMedic()
    else
        ShowNotification(Config.Messages.cancelled)
        CleanupMedic()
    end
end

function HealPlayer()
    local playerPed = PlayerPedId()
    
    if Config.Framework == 'esx' then
        if IsPlayerDead() then
            TriggerEvent('esx_ambulancejob:revive')
            if GetResourceState('wasabi_ambulance') == 'started' then
                TriggerEvent('wasabi_ambulance:revivePlayer')
            end
        end
        
        SetEntityHealth(playerPed, GetEntityMaxHealth(playerPed))
        SetPedArmour(playerPed, Config.HealAmount)
        
    elseif Config.Framework == 'qb' then
        if IsPlayerDead() then
            TriggerEvent('hospital:client:Revive')
            TriggerEvent('qb-ambulancejob:client:revive')
            if GetResourceState('wasabi_ambulance') == 'started' then
                TriggerEvent('wasabi_ambulance:revivePlayer')
            end
        end
        
        TriggerEvent('hospital:client:HealInjuries', playerPed, true)
        TriggerEvent('qb-ambulancejob:client:heal')
        SetPedArmour(playerPed, Config.HealAmount)
        
    elseif Config.Framework == 'qbox' then
        if IsPlayerDead() then
            TriggerEvent('qbx_medical:client:revive')
            if GetResourceState('wasabi_ambulance') == 'started' then
                TriggerEvent('wasabi_ambulance:revivePlayer')
            end
        end
        
        TriggerEvent('qbx_medical:client:heal')
        SetEntityHealth(playerPed, GetEntityMaxHealth(playerPed))
        SetPedArmour(playerPed, Config.HealAmount)
        
    else
        SetEntityHealth(playerPed, GetEntityMaxHealth(playerPed))
        SetPedArmour(playerPed, Config.HealAmount)
        
        for i = 0, 5 do
            SetPedBodyPartHealth(playerPed, i, 1000.0)
        end
    end
end

function CleanupMedic()
    if DoesEntityExist(medicPed) then
        DeleteEntity(medicPed)
    end
    
    if DoesBlipExist(medicBlip) then
        RemoveBlip(medicBlip)
        medicBlip = nil
    end
    
    CleanupAmbulance()
    
    medicCalled = false
    medicPed = nil
end

function CleanupAmbulance()
    if DoesEntityExist(ambulanceVehicle) then
        DeleteEntity(ambulanceVehicle)
    end
    
    ambulanceVehicle = nil
    drivingToPlayer = false
end

RegisterCommand(Config.Command, function()
    ShowMedicMenu()
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        if DoesEntityExist(medicPed) then
            DeleteEntity(medicPed)
        end
        if DoesEntityExist(ambulanceVehicle) then
            DeleteEntity(ambulanceVehicle)
        end
        if DoesBlipExist(medicBlip) then
            RemoveBlip(medicBlip)
        end
    end
end)

if Config.Framework == 'esx' then
    RegisterNetEvent('esx:playerLoaded')
    AddEventHandler('esx:playerLoaded', function(xPlayer)
        ESX.PlayerData = xPlayer
    end)

    RegisterNetEvent('esx:setJob')
    AddEventHandler('esx:setJob', function(job)
        ESX.PlayerData.job = job
    end)
elseif Config.Framework == 'qb' then
    RegisterNetEvent('QBCore:Client:OnPlayerLoaded')
    AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
        Wait(1000)
    end)
elseif Config.Framework == 'qbox' then
    RegisterNetEvent('QBCore:Client:OnPlayerLoaded')
    AddEventHandler('QBCore:Client:OnPlayerLoaded', function()
        Wait(1000)
    end)
end