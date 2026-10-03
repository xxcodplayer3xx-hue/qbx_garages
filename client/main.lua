local config = require 'config.client'
if not config.enableClient then return end
local VehicleCategory = {
	all = {
		[0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [5] = true,
		[6] = true, [7] = true, [8] = true, [9] = true, [10] = true, [11] = true,
		[12] = true, [13] = true, [14] = true, [15] = true, [16] = true, [17] = true,
		[18] = true, [19] = true, [20] = true, [21] = true, [22] = true,
	},
	car = {
		[0] = true,
		[1] = true,
		[2] = true,
		[3] = true,
		[4] = true,
		[5] = true,
		[6] = true,
		[7] = true,
		[8] = true,
		[9] = true,
		[10] = true,
		[11] = true,
		[12] = true,
		[13] = true,
		[17] = true,
		[18] = true,
		[19] = true,
		[20] = true,
		[22] = true,
	},
	air = { [15] = true, [16] = true },
	sea = { [14] = true },
}

---@param category VehicleType
---@param vehicle number
---@return boolean
local function isOfType(category, vehicle)
	local classes = VehicleCategory[category]
	return classes ~= nil and classes[GetVehicleClass(vehicle)] == true
end

---@param vehicle number
local function kickOutPeds(vehicle)
    for i = -1, 5, 1 do
        local seat = GetPedInVehicleSeat(vehicle, i)
        if seat ~= 0 then
            TaskLeaveVehicle(seat, vehicle, 0)
        end
    end
end

local nuiBusy = false
local activeGarage = nil

local function closeGarageUi()
    activeGarage = nil
    nuiBusy = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = "close", data = {} })
end

---@param garageName string
---@param garageInfo GarageConfig
---@param accessPoint integer
local function openGarageMenu(garageName, garageInfo, accessPoint)
    local vehicles = lib.callback.await("qbx_garages:server:getAllVehicles", false, garageName) or {}

    activeGarage = {
        name = garageName,
        label = garageInfo.label,
        accessPoint = accessPoint,
    }
    nuiBusy = false
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "open",
        data = {
            garageName = garageName,
            garageLabel = garageInfo.label,
            accessPoint = accessPoint,
            vehicles = vehicles,
        },
    })
end

RegisterNUICallback("close", function(_, callback)
    closeGarageUi()
    callback({ ok = true })
end)

RegisterNUICallback("retrieve", function(data, callback)
    if nuiBusy or not activeGarage or type(data) ~= "table" then
        callback({ ok = false, error = "The garage is busy. Try again in a moment." })
        return
    end

    local vehicleId = tonumber(data.vehicleId)
    if not vehicleId or vehicleId % 1 ~= 0 then
        callback({ ok = false, error = "That vehicle selection is invalid." })
        return
    end

    if cache.vehicle then
        callback({ ok = false, error = "Exit your current vehicle before retrieving another one." })
        return
    end

    nuiBusy = true
    local result = lib.callback.await("qbx_garages:server:retrieveVehicle", false, vehicleId, activeGarage.name, activeGarage.accessPoint)
    nuiBusy = false

    if result and result.ok and result.netId then
        local vehicle = lib.waitFor(function()
            if NetworkDoesEntityExistWithNetworkId(result.netId) then
                return NetToVeh(result.netId)
            end
        end)
        if vehicle and vehicle ~= 0 and config.engineOn then
            SetVehicleEngineOn(vehicle, true, true, false)
        end
    end

    callback(result or { ok = false, error = "The vehicle could not be retrieved." })
end)

AddEventHandler("onResourceStop", function(resource)
    if resource == cache.resource then
        closeGarageUi()
    end
end)

---@param vehicle number
---@param garageName string
local function parkVehicle(vehicle, garageName)
    if GetVehicleNumberOfPassengers(vehicle) == 0 then
        local isParkable = lib.callback.await('qbx_garages:server:isParkable', false, garageName, NetworkGetNetworkIdFromEntity(vehicle))

        if not isParkable then
            exports.qbx_core:Notify(locale('error.not_owned'), 'error', 5000)
            return
        end

        kickOutPeds(vehicle)
        SetVehicleDoorsLocked(vehicle, 2)
        Wait(1500)
        local parked = lib.callback.await('qbx_garages:server:parkVehicle', false, NetworkGetNetworkIdFromEntity(vehicle), lib.getVehicleProperties(vehicle), garageName)
        if parked then
            exports.qbx_core:Notify(locale('success.vehicle_parked'), 'primary', 4500)
        end
    else
        exports.qbx_core:Notify(locale('error.vehicle_occupied'), 'error', 3500)
    end
end

---@param garage GarageConfig
---@return boolean
local function checkCanAccess(garage)
    if garage.groups and not exports.qbx_core:HasPrimaryGroup(garage.groups, QBX.PlayerData) then
        exports.qbx_core:Notify(locale('error.no_access'), 'error')
        return false
    end
    if cache.vehicle and not isOfType(garage.vehicleType, cache.vehicle) then
        exports.qbx_core:Notify(locale('error.not_correct_type'), 'error')
        return false
    end
    return true
end

local activeRadialItems = {}

AddEventHandler('onResourceStop', function(resource)
    if resource ~= cache.resource then return end
    for id in pairs(activeRadialItems) do lib.removeRadialItem(id) end
end)

---@param garageName string
---@param garage GarageConfig
---@param accessPoint AccessPoint
---@param accessPointIndex integer
local function createZones(garageName, garage, accessPoint, accessPointIndex)
    CreateThread(function()
        accessPoint.dropPoint = accessPoint.dropPoint or accessPoint.spawn
        local drawRadius = accessPoint.drawRadius or 60
        local dropDrawRadius = accessPoint.dropDrawRadius or 60
        local useRadius = accessPoint.useRadius or 1
        local dropUseRadius = accessPoint.dropUseRadius or 1.5
        local dropZone, coordsZone
        local useRadial = config.interact == 'radialmenu'

        local function createInteractionZone(coords, radius, isDrop)
            local id = ('qbx_garages:%s:%s:%s'):format(garageName, accessPointIndex, isDrop and 'drop' or 'menu')
            local shownAction

            local function getAction()
                if useRadial and not LocalPlayer.state.isLoggedIn then return end
                if isDrop then return cache.vehicle and 'park' or nil end
                if accessPoint.dropPoint and cache.vehicle then return end
                return garage.type == GarageType.DEPOT and 'impound' or cache.vehicle and 'park' or 'car'
            end

            local function selectAction()
                if #(GetEntityCoords(cache.ped) - vec3(coords.x, coords.y, coords.z)) > radius then return end
                local action = getAction()
                if not action or not checkCanAccess(garage) then return end
                if action == 'park' then
                    parkVehicle(cache.vehicle, garageName)
                else
                    openGarageMenu(garageName, garage, accessPointIndex)
                end
            end

            local function clearInteraction()
                if useRadial then
                    lib.removeRadialItem(id)
                    activeRadialItems[id] = nil
                elseif shownAction then
                    lib.hideTextUI()
                end
                shownAction = nil
            end

            local function updateInteraction()
                local action = getAction()
                if action == shownAction then return end
                clearInteraction()
                shownAction = action
                if not action then return end
                if useRadial then
                    activeRadialItems[id] = true
                    lib.addRadialItem({
                        id = id,
                        label = locale('info.' .. action .. '_radial'),
                        icon = action == 'park' and 'square-parking' or 'warehouse',
                        onSelect = selectAction,
                    })
                else
                    lib.showTextUI(locale('info.' .. action .. '_e'))
                end
            end

            return lib.zones.sphere({
                coords = coords,
                radius = radius,
                onEnter = updateInteraction,
                onExit = clearInteraction,
                inside = function()
                    updateInteraction()
                    if not useRadial and IsControlJustReleased(0, 38) then selectAction() end
                end,
                debug = config.debugPoly,
            })
        end

        local function createDropZone()
            if dropZone then return end
            dropZone = createInteractionZone(accessPoint.dropPoint, dropUseRadius, true)
        end

        local function createCoordsZone()
            if coordsZone then return end
            coordsZone = createInteractionZone(accessPoint.coords, useRadius, false)
        end
        lib.zones.sphere({
            coords = accessPoint.coords,
            radius = drawRadius,
            onEnter = function()
                createCoordsZone()
            end,
            onExit = function()
                if coordsZone then
                    coordsZone.onExit()
                    coordsZone:remove()
                    coordsZone = nil
                end
            end,
            inside = function()
                config.drawGarageMarker(accessPoint.coords.xyz, useRadius)
            end,
            debug = config.debugPoly,
        })

        if accessPoint.dropPoint and garage.type ~= GarageType.DEPOT then
            lib.zones.sphere({
                coords = accessPoint.dropPoint,
                radius = dropDrawRadius,
                onEnter = function()
                    createDropZone()
                end,
                onExit = function()
                    if dropZone then
                        dropZone.onExit()
                        dropZone:remove()
                        dropZone = nil
                    end
                end,
                inside = function()
                    config.drawDropOffMarker(accessPoint.dropPoint, dropUseRadius)
                end,
                debug = config.debugPoly,
            })
        end
    end)
end

---@param garageInfo GarageConfig
---@param accessPoint AccessPoint
local function createBlips(garageInfo, accessPoint)
    local blip = AddBlipForCoord(accessPoint.coords.x, accessPoint.coords.y, accessPoint.coords.z)
    SetBlipSprite(blip, accessPoint.blip.sprite or 357)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, 0.60)
    SetBlipAsShortRange(blip, true)
    SetBlipColour(blip, accessPoint.blip.color or 3)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(accessPoint.blip.name or garageInfo.label)
    EndTextCommandSetBlipName(blip)
end

local function createGarage(name, garage)
    local accessPoints = garage.accessPoints
    for i = 1, #accessPoints do
        local accessPoint = accessPoints[i]

        if accessPoint.blip then
            createBlips(garage, accessPoint)
        end

        createZones(name, garage, accessPoint, i)
    end
end

local function createGarages()
    local garages = lib.callback.await('qbx_garages:server:getGarages')
    for name, garage in pairs(garages) do
        createGarage(name, garage)
    end
end

RegisterNetEvent('qbx_garages:client:garageRegistered', function(name, garage)
    createGarage(name, garage)
end)

CreateThread(function()
    createGarages()
end)
