local ESX = nil
local QBCore = nil
local medicCalled = false
local medicPed = nil

if Config.Framework == 'auto' then
    if GetResourceState('es_extended') == 'started' then
        ESX = exports['es_extended']:getSharedObject()
        Config.Framework = 'esx'
    elseif GetResourceState('qb-core') == 'started' then
        QBCore = exports['qb-core']:GetCoreObject()
        Config.Framework = 'qb'
    end
elseif Config.Framework == 'esx' then
    ESX = exports['es_extended']:getSharedObject()
elseif Config.Framework == 'qb' then
    QBCore = exports['qb-core']:GetCoreObject()
end

function IsPlayerAllowed()
    if #Config.AllowedJobs == 0 then
        return true
    end
    
    local playerJob = nil
    
    if Config.Framework == 'esx' then
        playerJob = ESX.PlayerData.job.name
    elseif Config.Framework == 'qb' then
        local PlayerData = QBCore.Functions.GetPlayerData()
        playerJob = PlayerData.job.name
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
        if ESX.PlayerData.dead then
            return true
        end
        
        if exports.wasabi_ambulance and exports.wasabi_ambulance:isPlayerDead() then
            return true
        end
        
        if health <= 0 or health <= 100 then
            return true
        end
        
        local playerData = ESX.GetPlayerData()
        if playerData.dead or playerData.isDead then
            return true
        end
        
        return false
    elseif Config.Framework == 'qb' then
        local PlayerData = QBCore.Functions.GetPlayerData()
        
        if PlayerData.metadata['isdead'] or PlayerData.metadata['inlaststand'] then
            return true
        end
        
        if exports.wasabi_ambulance and exports.wasabi_ambulance:isPlayerDead() then
            return true
        end
        
        return false
    else
        if exports.wasabi_ambulance and exports.wasabi_ambulance:isPlayerDead() then
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
        SpawnMedic()
    end)
end

function ResetMedicScript()
    if DoesEntityExist(medicPed) then
        DeleteEntity(medicPed)
    end
    
    if lib.progressActive() then
        lib.cancelProgress()
    end
    
    medicCalled = false
    medicPed = nil
    
    ShowNotification('Medic script has been reset successfully!')
end

function SpawnMedic()
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local spawnCoords = vector3(playerCoords.x, playerCoords.y, playerCoords.z + 2.0)
    
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
            TriggerEvent('wasabi_ambulance:revivePlayer')
        end
        
        SetEntityHealth(playerPed, GetEntityMaxHealth(playerPed))
        SetPedArmour(playerPed, Config.HealAmount)
        
    elseif Config.Framework == 'qb' then
        if IsPlayerDead() then
            TriggerEvent('hospital:client:Revive')
            TriggerEvent('qb-ambulancejob:client:revive')
            TriggerEvent('wasabi_ambulance:revivePlayer')
        end
        
        TriggerEvent('hospital:client:HealInjuries', playerPed, true)
        TriggerEvent('qb-ambulancejob:client:heal')
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
    
    medicCalled = false
    medicPed = nil
end

RegisterCommand(Config.Command, function()
    ShowMedicMenu()
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        if DoesEntityExist(medicPed) then
            DeleteEntity(medicPed)
        end
    end
end)