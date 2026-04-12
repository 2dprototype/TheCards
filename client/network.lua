local websocket = require("websocket")
local json = require("json")
local socket = require("socket")
local Config = require("config")

local Network = {}
Network.ws = nil
Network.protocol = "ws"
Network.roomCode = nil
Network.isHost = false
Network.clientId = nil
Network.players = {} -- List of clientIds in room

function Network.load()
    -- Nothing for now
end

function Network.connect(uri)
    if not uri or uri == "" then return end
    local scheme, host, port = uri:match("^(%w+)://([^:]+):(%d+)$")
    if not scheme then 
        print("Invalid URI format")
        return 
    end
    
    Network.protocol = scheme
    print("Connecting via " .. scheme .. " to " .. host .. ":" .. port)
    
    if scheme == "ws" or scheme == "wss" then
        local client = websocket.client.sync()
        local ok, err = client:connect(uri)
        if not ok then
            print("Connected failed: " .. tostring(err))
            return
        end
        client.sock:settimeout(0)
        Network.ws = client
    elseif scheme == "tcp" then
        local client = socket.tcp()
        client:settimeout(0)
        client:connect(host, port)
        Network.ws = client
    elseif scheme == "udp" then
        local client = socket.udp()
        client:settimeout(0)
        client:setpeername(host, port)
        Network.ws = client
    else
        print("Unsupported protocol: " .. scheme)
    end
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
    Network.connect(Config.get("server_uri"))
    Network.isHost = true
    Network.send({ type = "CREATE_ROOM", name = name or "Host" })
end

function Network.connectAsGuest(code, name)
    Network.connect(Config.get("server_uri"))
    Network.isHost = false
    Network.send({ type = "JOIN_ROOM", code = code, name = name })
end

function Network.send(data)
    if Network.ws then
        local str = json.encode(data)
        if Network.protocol == "tcp" then
            Network.ws:send(str .. "\n")
        else
            Network.ws:send(str)
        end
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
    
    if Network.protocol == "ws" or Network.protocol == "wss" then
        while true do
            local data, opcode, clean, close_code, err = Network.ws:receive()
            if data then
                local ok, msg = pcall(json.decode, data)
                if ok and msg then Network.handleSystemMessage(msg) end
                if not Network.ws then break end
            elseif err == "timeout" then
                break
            elseif err then
                if _G.handleNetworkEvent then _G.handleNetworkEvent({ type = "DISCONNECT", reason = "Server connection closed." }) end
                Network.disconnect()
                break
            end
        end
    elseif Network.protocol == "tcp" then
        while true do
            local data, err, partial = Network.ws:receive("*l")
            if data then
                local ok, msg = pcall(json.decode, data)
                if ok and msg then Network.handleSystemMessage(msg) end
                if not Network.ws then break end
            elseif err == "timeout" then
                break
            elseif err then
                if _G.handleNetworkEvent then _G.handleNetworkEvent({ type = "DISCONNECT", reason = "Server connection closed." }) end
                Network.disconnect()
                break
            end
        end
    elseif Network.protocol == "udp" then
        while true do
            local data, err = Network.ws:receive()
            if data then
                local ok, msg = pcall(json.decode, data)
                if ok and msg then Network.handleSystemMessage(msg) end
                if not Network.ws then break end
            elseif err == "timeout" then
                break
            elseif err then
                -- UDP doesn't normally 'close' in the same way, but network errors can happen
                break
            end
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
