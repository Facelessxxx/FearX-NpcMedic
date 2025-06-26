local ESX = nil
local QBCore = nil
local QBox = nil

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

function CheckPlayerMoney(source)
    if Config.Framework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            local cashMoney = xPlayer.getMoney() or 0
            local bankAccount = xPlayer.getAccount('bank')
            local bankMoney = bankAccount and bankAccount.money or 0
            
            if Config.PaymentMethods.cash and cashMoney >= Config.Cost then
                return true
            end
            if Config.PaymentMethods.bank and bankMoney >= Config.Cost then
                return true
            end
        end
    elseif Config.Framework == 'qb' then
        local Player = QBCore.Functions.GetPlayer(source)
        if Player then
            local cashMoney = Player.PlayerData.money['cash'] or 0
            local bankMoney = Player.PlayerData.money['bank'] or 0
            
            if Config.PaymentMethods.cash and cashMoney >= Config.Cost then
                return true
            end
            if Config.PaymentMethods.bank and bankMoney >= Config.Cost then
                return true
            end
        end
    elseif Config.Framework == 'qbox' then
        local Player = QBox:GetPlayer(source)
        if Player then
            local cashMoney = Player.PlayerData.money['cash'] or 0
            local bankMoney = Player.PlayerData.money['bank'] or 0
            
            if Config.PaymentMethods.cash and cashMoney >= Config.Cost then
                return true
            end
            if Config.PaymentMethods.bank and bankMoney >= Config.Cost then
                return true
            end
        end
    else
        local cashCount = exports.ox_inventory:Search(source, Config.OxInventoryCashItem) or {}
        local totalCash = 0
        for _, item in pairs(cashCount) do
            totalCash = totalCash + item.count
        end
        if totalCash >= Config.Cost then
            return true
        end
    end
    
    return false
end

function ProcessPayment(source)
    local paid = false
    local paymentMethod = ''
    
    if Config.Framework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            if Config.PaymentMethods.cash and xPlayer.getMoney() >= Config.Cost then
                xPlayer.removeMoney(Config.Cost)
                paymentMethod = 'cash'
                paid = true
            elseif Config.PaymentMethods.bank and xPlayer.getAccount('bank').money >= Config.Cost then
                xPlayer.removeAccountMoney('bank', Config.Cost)
                paymentMethod = 'bank'
                paid = true
            end
        end
    elseif Config.Framework == 'qb' then
        local Player = QBCore.Functions.GetPlayer(source)
        if Player then
            if Config.PaymentMethods.cash and Player.PlayerData.money['cash'] >= Config.Cost then
                Player.Functions.RemoveMoney('cash', Config.Cost)
                paymentMethod = 'cash'
                paid = true
            elseif Config.PaymentMethods.bank and Player.PlayerData.money['bank'] >= Config.Cost then
                Player.Functions.RemoveMoney('bank', Config.Cost)
                paymentMethod = 'bank'
                paid = true
            end
        end
    elseif Config.Framework == 'qbox' then
        local Player = QBox:GetPlayer(source)
        if Player then
            if Config.PaymentMethods.cash and Player.PlayerData.money['cash'] >= Config.Cost then
                Player.Functions.RemoveMoney('cash', Config.Cost)
                paymentMethod = 'cash'
                paid = true
            elseif Config.PaymentMethods.bank and Player.PlayerData.money['bank'] >= Config.Cost then
                Player.Functions.RemoveMoney('bank', Config.Cost)
                paymentMethod = 'bank'
                paid = true
            end
        end
    else
        if exports.ox_inventory:RemoveItem(source, Config.OxInventoryCashItem, Config.Cost) then
            paymentMethod = 'cash'
            paid = true
        end
    end
    
    if paid then
        local message = paymentMethod == 'cash' and Config.Messages.paidCash or Config.Messages.paidBank
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Payment',
            description = string.format(message, Config.Cost),
            type = 'success'
        })
    end
end

if Config.Framework == 'esx' then
    ESX.RegisterServerCallback('fearx-npcmedic:checkMoney', function(source, cb)
        cb(CheckPlayerMoney(source))
    end)
elseif Config.Framework == 'qb' then
    QBCore.Functions.CreateCallback('fearx-npcmedic:checkMoney', function(source, cb)
        cb(CheckPlayerMoney(source))
    end)
elseif Config.Framework == 'qbox' then
    QBox:CreateCallback('fearx-npcmedic:checkMoney', function(source, cb)
        cb(CheckPlayerMoney(source))
    end)
else
    RegisterServerEvent('fearx-npcmedic:checkMoney')
    AddEventHandler('fearx-npcmedic:checkMoney', function()
        TriggerClientEvent('fearx-npcmedic:checkMoney:callback', source, CheckPlayerMoney(source))
    end)
end

RegisterServerEvent('fearx-npcmedic:processPayment')
AddEventHandler('fearx-npcmedic:processPayment', function()
    ProcessPayment(source)
end)

RegisterServerEvent('fearx-npcmedic:logUsage')
AddEventHandler('fearx-npcmedic:logUsage', function()
    local playerName = GetPlayerName(source)
    local identifier = nil
    
    if Config.Framework == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            identifier = xPlayer.identifier
        end
    elseif Config.Framework == 'qb' then
        local Player = QBCore.Functions.GetPlayer(source)
        if Player then
            identifier = Player.PlayerData.citizenid
        end
    elseif Config.Framework == 'qbox' then
        local Player = QBox:GetPlayer(source)
        if Player then
            identifier = Player.PlayerData.citizenid
        end
    else
        identifier = 'standalone_' .. source
    end
    
    print(('[Fearx-NpcMedic] Player %s (%s) used medic command'):format(playerName, identifier))
end)