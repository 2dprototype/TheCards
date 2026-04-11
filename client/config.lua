local json = require("json")

local Config = {}

-- Default configuration
Config.data = {
    server_uri = "ws://localhost:8080",
    username = ""
}

local CONFIG_FILE = "network_config.json"

function Config.load()
    if love.filesystem.getInfo(CONFIG_FILE) then
        local contents = love.filesystem.read(CONFIG_FILE)
        local ok, parsed = pcall(json.decode, contents)
        if ok and type(parsed) == "table" then
            for k, v in pairs(parsed) do
                Config.data[k] = v
            end
        end
    end
end

function Config.save()
    local contents = json.encode(Config.data)
    love.filesystem.write(CONFIG_FILE, contents)
end

function Config.get(key)
    return Config.data[key]
end

function Config.set(key, value)
    Config.data[key] = value
    Config.save()
end

return Config
