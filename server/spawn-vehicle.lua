local logger = require '@qbx_core.modules.logger'
local spawningVehicles = {}

local function getVehicleType(playerVehicle)
    local vehicle = playerVehicle and VEHICLES[playerVehicle.modelName]
    if not vehicle then return end

    if vehicle.category == "helicopters" or vehicle.category == "planes" then
        return VehicleType.AIR
    elseif vehicle.category == "boats" then
        return VehicleType.SEA
    end

    return VehicleType.CAR
end

---@param player table
---@param garage GarageConfig
---@return boolean
local function canAccessGarage(player, garage)
    if garage.groups and not exports.qbx_core:HasPrimaryGroup(player.PlayerData.source, garage.groups) then
        return false
    end
    if garage.canAccess ~= nil and not garage.canAccess(player.PlayerData.source) then
        return false
    end
    return true
end

---@param vehicleId integer
---@param modelName string
local function setVehicleStateToOut(vehicleId, vehicle, modelName)
    local depotPrice = Config.calculateImpoundFee(vehicleId, modelName) or 0
    return exports.qbx_vehicles:SaveVehicle(vehicle, {
        state = VehicleState.OUT,
        depotPrice = depotPrice
    })
end

---@param source number
---@param depotPrice integer
---@return string?
local function payDepotPrice(source, depotPrice)
    local cashBalance = exports.qbx_core:GetMoney(source, "cash") or 0
    local bankBalance = exports.qbx_core:GetMoney(source, "bank") or 0

    if cashBalance >= depotPrice and exports.qbx_core:RemoveMoney(source, "cash", depotPrice, "paid-depot") then
        return "cash"
    elseif bankBalance >= depotPrice and exports.qbx_core:RemoveMoney(source, "bank", depotPrice, "paid-depot") then
        return "bank"
    end
end

---@param source number
---@param vehicleId integer
---@param garageName string
---@param accessPointIndex integer
---@return number? netId
local function spawnVehicle(source, vehicleId, garageName, accessPointIndex, retrieveAnywhere)
    if type(vehicleId) ~= 'number' or vehicleId % 1 ~= 0 then return end
    if type(garageName) ~= 'string' then return end
    if type(accessPointIndex) ~= 'number' or accessPointIndex % 1 ~= 0 then return end

    local player = exports.qbx_core:GetPlayer(source)
    local garage = TryGetGarage(source, garageName)
    if not player or not garage or not canAccessGarage(player, garage) then return end

    local accessPoint = garage.accessPoints[accessPointIndex]
    if not accessPoint then
        logger.log({
            source = source,
            message = string.format(
                'Attempted to spawn a vehicle from a non-existent access point index: %d for garage: %s',
                accessPointIndex,
                garageName
            ),
            webhook = Config.logging.webhook.error,
            event = 'error',
            color = 'red'
        })

        return
    end

    local distanceBetweenPlayerAndAccessPoint = #(GetEntityCoords(GetPlayerPed(source)) - accessPoint.coords.xyz)
    if distanceBetweenPlayerAndAccessPoint > 3 then
        logger.log({
            source = source,
            message = string.format(
                'Player attempted to spawn a vehicle but was too far from the access point. Distance: %.2f, Access Point Index: %d, Garage: %s',
                distanceBetweenPlayerAndAccessPoint,
                accessPointIndex,
                garageName
            ),
            webhook = Config.logging.webhook.anticheat,
            event = 'suspicious',
            color = 'white'
        })

        return
    end
    local garageType = GetGarageType(garageName)

    local spawnCoords = accessPoint.spawn or accessPoint.coords
    local filter = retrieveAnywhere and {
        citizenid = not garage.shared and player.PlayerData.citizenid or nil,
    } or GetPlayerVehicleFilter(source, garageName)
    local playerVehicle = exports.qbx_vehicles:GetPlayerVehicle(vehicleId, filter)
    if not playerVehicle then
        exports.qbx_core:Notify(source, locale('error.not_owned'), 'error')
        return
    end
    if type(playerVehicle.props) ~= "table" or type(playerVehicle.props.plate) ~= "string"
        or type(playerVehicle.props.model) ~= "number" then return end

    local existingVehicle = FindVehicleOnServer(playerVehicle.props.plate)
    if garageType == GarageType.DEPOT and existingVehicle and not retrieveAnywhere then
        return exports.qbx_core:Notify(source, locale("error.not_impound"), "error")
    end
    if Config.distanceCheck then
        local nearbyVehicle = lib.getClosestVehicle(spawnCoords.xyz, Config.distanceCheck, false)
        if nearbyVehicle and nearbyVehicle ~= existingVehicle then
            exports.qbx_core:Notify(source, locale("error.no_space"), "error")
            return
        end
    end

    if retrieveAnywhere and playerVehicle.state == VehicleState.IMPOUNDED and garageType ~= GarageType.DEPOT then
        return exports.qbx_core:Notify(source, locale("error.not_impound"), "error")
    end

    if not GaragesHooks("spawnVehicle", { source = source, vehicleId = vehicleId, garageName = garageName }) then return end

    if retrieveAnywhere and existingVehicle then
        if GetVehicleNumberOfPassengers(existingVehicle) > 0 or GetPedInVehicleSeat(existingVehicle, -1) ~= 0 then
            return exports.qbx_core:Notify(source, locale("error.vehicle_occupied"), "error")
        end
    end

    local paidFrom
    local depotPrice
    if garageType == GarageType.DEPOT then
        OverrideFreeDepotPriceForOutVehicle(playerVehicle)
        depotPrice = tonumber(playerVehicle.depotPrice) or 0
        if depotPrice ~= depotPrice or depotPrice < 0 or depotPrice > 100000000 then
            return
        end

        if depotPrice > 0 then
            paidFrom = payDepotPrice(source, depotPrice)
            if not paidFrom then
                exports.qbx_core:Notify(source, locale('error.not_enough'), 'error')
                return
            end
        end
    end

    playerVehicle.props.lockState = 1 -- Modify the veh props lock state here to avoid conflicts with the vehicleConfig.noLock system.

    local warpPed = Config.warpInVehicle and GetPlayerPed(source)
    local success, netId, veh = pcall(qbx.spawnVehicle, {
        spawnSource = spawnCoords,
        model = playerVehicle.props.model,
        props = playerVehicle.props,
        warp = warpPed,
    })

    if not success or not netId or not veh or veh == 0 or not DoesEntityExist(veh) then
        if paidFrom then
            exports.qbx_core:AddMoney(source, paidFrom, depotPrice, "depot-spawn-refund")
        end
        return
    end

    if not GaragesHooks('spawnedVehicle', {source = source, vehicleId = vehicleId, vehicle = veh, garageName = garageName}) then
        exports.qbx_core:DeleteVehicle(veh)
        if paidFrom then exports.qbx_core:AddMoney(source, paidFrom, depotPrice, "depot-spawn-refund") end
        return
    end

    Entity(veh).state:set('vehicleid', vehicleId, false)
    local saved, result = pcall(setVehicleStateToOut, vehicleId, veh, playerVehicle.modelName)
    if not saved or not result then
        exports.qbx_core:DeleteVehicle(veh)
        if paidFrom then exports.qbx_core:AddMoney(source, paidFrom, depotPrice, "depot-spawn-refund") end
        return
    end

    if retrieveAnywhere and existingVehicle then
        exports.qbx_core:DeleteVehicle(existingVehicle)
    end

    if Config.doorsLocked then
        if GetResourceState('qbx_vehiclekeys') == 'started' then
            TriggerEvent('qb-vehiclekeys:server:setVehLockState', netId, 2)
        else
            SetVehicleDoorsLocked(veh, 2)
        end
    end

    TriggerClientEvent('vehiclekeys:client:SetOwner', source, playerVehicle.props.plate)

    TriggerEvent('qbx_garages:server:vehicleSpawned', veh)
    return netId
end

lib.callback.register('qbx_garages:server:spawnVehicle', function(source, vehicleId, garageName, accessPointIndex)
    if type(vehicleId) ~= 'number' or vehicleId % 1 ~= 0 or spawningVehicles[vehicleId] then return end
    spawningVehicles[vehicleId] = true
    local success, result = pcall(spawnVehicle, source, vehicleId, garageName, accessPointIndex)
    spawningVehicles[vehicleId] = nil
    if not success then
        lib.print.error(result)
        return
    end
    return result
end)

lib.callback.register("qbx_garages:server:retrieveVehicle", function(source, vehicleId, garageName, accessPointIndex)
    if type(vehicleId) ~= "number" or vehicleId % 1 ~= 0 or type(garageName) ~= "string" or type(accessPointIndex) ~= "number" then
        print(("[qbx_garages] Retrieval refused: invalid request from %s"):format(source))
        return { ok = false, error = "The retrieval request was invalid." }
    end
    if spawningVehicles[vehicleId] then
        return { ok = false, error = "That vehicle is already being retrieved." }
    end

    spawningVehicles[vehicleId] = true
    local success, netId = pcall(spawnVehicle, source, vehicleId, garageName, accessPointIndex, true)
    spawningVehicles[vehicleId] = nil
    if not success then
        lib.print.error(netId)
        print(("[qbx_garages] Retrieval refused: server error for vehicle %s from %s"):format(vehicleId, source))
        return { ok = false, error = "The vehicle could not be retrieved right now." }
    end
    if not netId then
        print(("[qbx_garages] Retrieval refused: vehicle %s was not spawned for %s"):format(vehicleId, source))
        return { ok = false, error = "The vehicle could not be retrieved. Check the spawn point and try again." }
    end

    return { ok = true, netId = netId }
end)

function OverrideFreeDepotPriceForOutVehicle(vehicle)
    if VehicleState.OUT ~= vehicle.state then return end
    if vehicle.depotPrice and vehicle.depotPrice > 0 then return end

    vehicle.depotPrice = Config.calculateImpoundFee(vehicle.id, vehicle.modelName)
end
