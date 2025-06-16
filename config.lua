Config = {}

Config.Framework = 'auto'

Config.Command = 'medic'

Config.WaitTime = 5

Config.HealTime = 10

Config.HealAmount = 100

Config.Cost = 500

Config.MedicModel = 's_m_m_doctor_01'

Config.ProgressBarText = 'Being healed by medic...'

Config.AllowedJobs = {}

Config.PaymentMethods = {
    cash = true,
    bank = true
}

Config.CurrencyName = 'money'

Config.OxInventoryCashItem = 'cash'

Config.Messages = {
    calling = 'Calling medic...',
    arriving = 'Medic is arriving...',
    healing = 'Medic is healing you...',
    healed = 'You have been healed!',
    noMoney = 'You don\'t have enough money in cash or bank!',
    alreadyCalled = 'You already called a medic!',
    cancelled = 'Healing cancelled!',
    notDead = 'You must be dead to call a medic!',
    paidCash = 'Paid $%s from cash',
    paidBank = 'Paid $%s from bank account',
    notAllowed = 'You are not authorized to use this command!'
}