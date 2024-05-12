require("mysqloo")

local DATABASE_HOST = "IP"
local DATABASE_PORT = 3306
local DATABASE_NAME = "NAME"
local DATABASE_USERNAME = "USERNAME"
local DATABASE_PASSWORD = "PASSWORD"

local db = mysqloo.connect(DATABASE_HOST, DATABASE_USERNAME, DATABASE_PASSWORD, DATABASE_NAME, DATABASE_PORT)

function db:onConnected()
    print("Database has connected successfully.")
end

function db:onConnectionFailed(err)
    print("Connection to database failed: " .. err)
end

db:connect()

local function connectDiscord(ply, text, teamChat)
    local command = "/connectdiscord"
    if string.sub(text, 1, string.len(command)) == command then
        local token = string.sub(text, string.len(command) + 2)
        if token == "" then
            ply:ChatPrint("Вы должны указать токен после команды.")
            return ""
        end

        local steam_id = ply:SteamID()


        local checkQuery = db:query(string.format("SELECT steam_id FROM tokens WHERE steam_id = '%s'", db:escape(steam_id)))

        function checkQuery:onSuccess(data)
            if data and #data > 0 then
                ply:ChatPrint("Вы уже ранее привязали свой Discord")
            else
                local tokenQuery = db:query(string.format("SELECT discord_id, end_time FROM tokens WHERE token = '%s' AND end_time > NOW()", db:escape(token)))

                function tokenQuery:onSuccess(tokenData)
                    if tokenData and #tokenData > 0 then
                        local result = tokenData[1]
                        local nickname = ply:Nick()
                        local usergroup = ply:GetUserGroup()
                        local current_date = os.date("%Y-%m-%d %H:%M:%S")

                        local updateQuery = db:query(string.format([[
                            UPDATE tokens SET
                            steam_id = '%s',
                            nickname = '%s',
                            usergroup = '%s',
                            date = '%s'
                            WHERE token = '%s'
                        ]], db:escape(steam_id), db:escape(nickname), db:escape(usergroup), current_date, db:escape(token)))

                        function updateQuery:onSuccess()
                            ply:ChatPrint("Ваш аккаунт успешно превязан.")
                        end

                        function updateQuery:onError(err)
                            print("Error updating user data: " .. err)
                            ply:ChatPrint("Ошибка при обновлении данных: " .. err)
                        end

                        updateQuery:start()
                    else
                        ply:ChatPrint("Токен не найден или уже истек. Попробуйте получить новый")
                    end
                end

                function tokenQuery:onError(err)
                    print("Error querying token data: " .. err)
                    ply:ChatPrint("Ошибка при получении данных токена: " .. err)
                end

                tokenQuery:start()
            end
        end

        function checkQuery:onError(err)
            print("Error checking existing steam_id: " .. err)
            ply:ChatPrint("Ошибка при проверке существующего Steam ID: " .. err)
        end

        checkQuery:start()
        return ""
    end
end

hook.Add("PlayerSay", "ConnectDiscordCommand", connectDiscord)

local function updatePlayerData(steam_id, nickname, usergroup)
    local query = db:query(string.format([[
        UPDATE tokens SET
        nickname = '%s',
        usergroup = '%s'
        WHERE steam_id = '%s'
    ]], db:escape(nickname), db:escape(usergroup), db:escape(steam_id)))

    function query:onSuccess()
        print("Player data updated for: " .. steam_id)
    end

    function query:onError(err)
        print("Error updating player data: " .. err)
    end

    query:start()
end

hook.Add("PlayerInitialSpawn", "PlayerData_UpdateOnSpawn", function(ply)
    updatePlayerData(ply:SteamID(), ply:Nick(), ply:GetUserGroup())
end)

hook.Add("PlayerDisconnected", "PlayerData_UpdateOnDisconnect", function(ply)
    updatePlayerData(ply:SteamID(), ply:Nick(), ply:GetUserGroup())
end)

hook.Add("onPlayerChangedName", "PlayerData_UpdateOnNameChange", function(ply, oldName, newName)
    updatePlayerData(ply:SteamID(), newName, ply:GetUserGroup())
end)

if ULib then
    hook.Add("ULibUserGroupChange", "PlayerData_UpdateOnGroupChange", function(account_id, allows, denies, oldGroup, newGroup)
        local ply = player.GetBySteamID(account_id)
        if ply and ply:IsValid() then
            updatePlayerData(ply:SteamID(), ply:Nick(), newGroup)
        end
    end)
end

local function searchDiscord(ply, text, teamChat)
    local command = "/searchdiscord"
    if string.sub(text, 1, string.len(command)) == command then
        local searchTerm = string.sub(text, string.len(command) + 2)
        if searchTerm == "" then
            ply:ChatPrint("Вы должны указать Steam ID или никнейм после команды.")
            return ""
        end

        local query
        if string.sub(searchTerm, 1, 6) == "STEAM_" then
            query = db:query(string.format("SELECT discord_id FROM tokens WHERE steam_id = '%s'", db:escape(searchTerm)))
        else
            query = db:query(string.format("SELECT discord_id FROM tokens WHERE steam_id LIKE '%%%s%%'", db:escape(searchTerm)))
        end

        function query:onSuccess(data)
            if data and #data > 0 then
                local message = "Найденные Discord ID: "
                for _, row in ipairs(data) do
                    message = message .. row.discord_id .. ", "
                end
                message = message:sub(1, -3)
                ply:ChatPrint(message)
            else
                ply:ChatPrint("Пользователь с такими данными не найден.")
            end
        end

        function query:onError(err)
            print("Error with search query: " .. err)
            ply:ChatPrint("Ошибка при поиске: " .. err)
        end

        query:start()
        return ""
    end
end

hook.Add("PlayerSay", "SearchDiscordCommand", searchDiscord)