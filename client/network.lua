local websocket = require("websocket")
local json = require("json")

local Network = {}
Network.ws = nil
Network.roomCode = nil
Network.isHost = false
Network.clientId = nil
Network.players = {} -- List of clientIds in room

function Network.load()
    -- Nothing for now
end

function Network.connect(host, port, secure)
    local scheme = secure and "wss" or "ws"
    local url = scheme .. "://" .. host .. ":" .. port
    local client = websocket.client.sync()
    local ok, err = client:connect(url)
    if not ok then
        print("Connected failed: " .. tostring(err))
        return
    end
    client.sock:settimeout(0)
    Network.ws = client
end

function Network.disconnect()
    if Network.ws then
        Network.ws:close()
        Network.ws = nil
    end
    Network.roomCode = nil
    Network.isHost = false
    Network.players = {}
end

function Network.connectAsHost(name)
    Network.connect("127.0.0.1", 8080, false)
    Network.isHost = true
    Network.send({ type = "CREATE_ROOM", name = name or "Host" })
end

function Network.connectAsGuest(code, name)
    Network.connect("127.0.0.1", 8080, false)
    Network.isHost = false
    Network.send({ type = "JOIN_ROOM", code = code, name = name })
end

function Network.send(data)
    if Network.ws then
        local str = json.encode(data)
        Network.ws:send(str)
    end
end

function Network.sendGameMessage(target, data)
    -- target can be "all" or clientId if host; if guest, target doesn't matter (goes to host)
    if Network.isHost then
        Network.send({ type = "HOST_MSG", targetId = target, data = data })
    else
        Network.send({ type = "CLIENT_MSG", data = data })
    end
end

function Network.update(dt)
    if not Network.ws then return end
    
    while true do
        local data, opcode, clean, close_code, err = Network.ws:receive()
        if data then
            local ok, msg = pcall(json.decode, data)
            if ok and msg then
                Network.handleSystemMessage(msg)
            end
        elseif err == "timeout" then
            break
        elseif err then
            if _G.handleNetworkEvent then _G.handleNetworkEvent({ type = "DISCONNECT", reason = "Server connection closed." }) end
            Network.disconnect()
            break
        end
    end
end

function Network.handleSystemMessage(msg)
    if msg.type == "HELLO" then
        Network.clientId = msg.clientId
    elseif msg.type == "CLIENT_JOINED" then
        table.insert(Network.players, { id = msg.clientId, name = msg.name })
        -- inform main
        if _G.handleNetworkEvent then _G.handleNetworkEvent(msg) end
    else
        -- general message handling in main
        if _G.handleNetworkEvent then _G.handleNetworkEvent(msg) end
    end
end

function Network.getPlayerCount()
    if Network.isHost then
        return 1 + #Network.players
    else
        return "?" -- handled by lobby state tracking otherwise
    end
end

return Network
