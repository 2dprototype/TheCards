local socket = require("socket")
local json = require("json")

local Network = {}
Network.tcp = nil
Network.roomCode = nil
Network.isHost = false
Network.clientId = nil
Network.players = {} -- List of clientIds in room

local buffer = ""

function Network.load()
    -- Nothing for now
end

function Network.connect(host, port)
    local tcp = socket.tcp()
    tcp:settimeout(0)
    local _, err = tcp:connect(host, port)
    Network.tcp = tcp
end

function Network.disconnect()
    if Network.tcp then
        Network.tcp:close()
        Network.tcp = nil
    end
    Network.roomCode = nil
    Network.isHost = false
    Network.players = {}
end

function Network.connectAsHost(name)
    Network.connect("127.0.0.1", 8080)
    Network.isHost = true
    Network.send({ type = "CREATE_ROOM", name = name or "Host" })
end

function Network.connectAsGuest(code, name)
    Network.connect("127.0.0.1", 8080)
    Network.isHost = false
    Network.send({ type = "JOIN_ROOM", code = code, name = name })
end

function Network.send(data)
    if Network.tcp then
        local str = json.encode(data)
        Network.tcp:send(str .. "\n")
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
    if not Network.tcp then return end
    
    local chunk, err, part = Network.tcp:receive("*a")
    local data_str = nil
    
    if chunk then
        data_str = chunk
    elseif err == "timeout" and part and #part > 0 then
        -- no complete data, wait for next tick? actually *a reads until closed. 
        -- Oh wait, receive("*a") blocks until connection closed or error. We should use *l or read chunks.
        -- We will use "*l" to read a line since we send lines.
    end
    
    -- In non-blocking socket, *a returns partially read data in `part` on "timeout".
    if err == "timeout" and part then
        buffer = buffer .. part
    elseif chunk then
        buffer = buffer .. chunk
    elseif err == "closed" then
        if _G.handleNetworkEvent then _G.handleNetworkEvent({ type = "DISCONNECT", reason = "Server connection closed." }) end
        Network.disconnect()
        return
    end
    
    -- Split by newline
    while true do
        local startIdx, endIdx = string.find(buffer, "\n")
        if startIdx then
            local line = string.sub(buffer, 1, startIdx - 1)
            buffer = string.sub(buffer, endIdx + 1)
            
            local ok, msg = pcall(json.decode, line)
            if ok and msg then
                Network.handleSystemMessage(msg)
            end
        else
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
