local http = require "http"
local shortport = require "shortport"
local stdnse = require "stdnse"

description = "Detect Keycloak Identity Server"
categories = {"default", "discovery", "safe"}

portrule = shortport.port_or_service({8080, 8443, 9090}, {"http", "https"})

action = function(host, port)
    local paths = {
        "/.well-known/openid-configuration",
        "/realms/master/protocol/oidc/certs",
        "/admin/",
        "/auth/",
        "/realms/",
        "/realms/master/",
        "/realms/master/.well-known/openid-configuration"
    }
    
    local detected = false
    local detectedPaths = {}
    
    -- Проверка всех путей
    for _, path in ipairs(paths) do
        local response = http.get(host, port, path)
        
        if response and response.status == 200 then
            if response.body then
                if string.find(response.body, "keycloak", 1, true) or
                   string.find(response.body, "issuer", 1, true) or
                   string.find(response.body, "authorization_endpoint", 1, true) or
                   string.find(response.body, "openid%-configuration", 1, true) then
                    table.insert(detectedPaths, "✓ " .. path .. " (200 OK)")
                    detected = true
                end
            end
        elseif response and response.status == 302 then
            table.insert(detectedPaths, "↻ " .. path .. " (302 Redirect)")
        end
    end
    
    -- Проверка Server header
    local serverHeader = "Unknown"
    local response = http.get(host, port, "/")
    if response and response.header then
        serverHeader = response.header["server"] or "Unknown"
        
        if string.find(serverHeader, "Undertow", 1, true) then
            table.insert(detectedPaths, "✓ Server: " .. serverHeader)
            detected = true
        end
    end
    
    if detected then
        local output = stdnse.output_table()
        output["Status"] = "✅ KEYCLOAK DETECTED"
        output["Server"] = serverHeader
        output["Found Endpoints"] = detectedPaths
        return output
    end
    
    return "Keycloak not detected"
end
