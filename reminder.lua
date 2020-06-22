local timer = require "util.timer";
local stanza = require "util.stanza";
local serpent = require("serpent")

local data = {}
local file_path = "reminders.lua"
local instructions = [[Examples:
·Trucar a la Mariona 20/11/2016 17:30 o 20/11 17:30
·Sopar amb els amics 08/03/2016 o 08/03
·Revisar la bústia de correu en 47 minuts/hores/dies/mesos
·Renovar DNI el 30 o el dia 30
·Treure la cassola del forn a les 14:15
·Visita al metge el 20/11/2016 12:00 contacte@adreça.com
]]

local function load_data()
    local toReturn = false
    local file = io.open(file_path, "r")
        if file then
            local ok, new_data = serpent.load(file:read("*a"), {safe = false})
            file:close()
            
            if ok and new_data then 
                data = new_data
                toReturn = true
            end
        end
    return toReturn
end


local function persist_data()
    local file = io.open(file_path, "w")
    file:write(serpent.block(data))
    file:close()
end

local function add_message(jid, message)
    data[#data +1] = {jid, message}
    persist_data()
end

local function send_message(bot, jid, message)
    bot:send(stanza.message({ to = jid, type = "headline" }):body(message))
end

local function delete_message(jid, message)
    local i = nil
    for k,v in ipairs(data) do
        if v.jid == jid then
            if v.message == message then
                i = k
                break
            end
        end
    end
    
    table.remove(data,i)
    persist_data()
end

local function send_and_delete_message(bot, jid, message)
    send_message(bot, jid, message)
    delete_message(jid, message)
end

local function create_timer(bot, jid, message, seconds)
    -- Timers can't store variables.
    timer.add_task(seconds, function() send_and_delete_message(bot, jid, message) end);
end


local function create_and_add_timer(bot, jid, message, seconds)
    create_timer(bot, jid, message, seconds)
    add_message(jid, message)
end

local function wrong_input(message)
    message:reply("Sorry, I couldn't understand that. Write «instructions» or «help» for more information.")
end

function riddim.plugins.reminder(bot)
    load_data()
    local function process_message(msg)
        local body = msg.body
        if body then
            --by default remember the task in 30 minutes
            --If date, remember at 6:00 of that day
            --if format nn/nn/nnnn nn:nn then at that timer
            local message = msg.body:match("^%s*(.-)%s*$")
            local input = msg.body:match("^%s*(.-)%s*$"):lower()
            local jid = msg.sender.jid:match("^(.-)/")
            local send_to = msg.body:match("^.* (.-)$")
            if send_to then
                if send_to:match("^.+@.+%..+$") then
                    message = "Missatge de " .. jid .. ":\n" .. message:match("^(.*)" .. send_to .. "$")
                    jid = send_to
                end
            end
            
            -- "Trucar a Yuri 20/11/2016 17:30" or "Trucar a Yuri 20/11 17:30"
            if input:match("%d%d?/%d%d?/?%d?%d?%d?%d? %d%d?:%d%d$") then
                input = input:match("%d%d?/%d%d?/?%d?%d?%d?%d? %d%d?:%d%d$")
                local day = input:match("^%d%d?")
                local month = input:match("^%d%d?/(%d%d?)")
                local year = input:match("^%d%d?/(%d%d%d?%d?)") -- Get length of year to translate it to dddd
                local hour = input:match("(%d%d?):%d%d$") -- TODO: could be 17 instead of 17:00 too
                local minutes = input:match("%d%d$")
                
                if not year then
                    year = tostring(os.date("*t", os.time()).year)
                end
                
                if year:len() < 4 then
                    year = year + 2000 --[["20" .. year]]
                end
                
                local seconds_left = os.time({year = year, month = month, day = day, hour = hour, min = minutes})
                seconds_left = seconds_left - os.time()
                create_and_add_timer(bot, jid, message, seconds_left)
                
            -- Go to grocery store 08/03/2016 or 08/03"
            elseif input:match("%d%d?/%d%d?/?%d?%d?%d?%d?$") then
                input = input:match("%d%d?/%d%d?/?%d?%d?%d?%d?$")
                local day = input:match("^%d%d?")
                local month = input:match("^%d%d?/(%d%d?)")
                local year = input:match("^%d%d?/(%d%d%d?%d?)") --get length of year to translate it to dddd
                local hour = "6"
                local minutes = "0"
                
                if not year then
                    year = os.date("*t", os.time()).year
                end
                
                if year:len() < 4 then
                    year = year + 2000 --[["20" .. year]]
                end

                local seconds_left = os.time({year = year, month = month, day = day, hour = hour, min = minutes})
                seconds_left = seconds_left - os.time() 
                create_and_add_timer(bot, jid, message, seconds_left)

            -- "Parar el foc en 47 minuts/hores/dies/mesos"
            elseif input:match("^.*en %d+.-$") then
                local number = input:match("^.*en (%d+).-$")
                local time = input:match("^%s*(.-)%s*$"):match("^.*%d(.-)$")
                local date_table = os.date("*t", os.time())
                time = time:lower()
                local seconds_left = nil
                
                --This is wrong. It must take current date and sum the new date instead
                if time:match("minuts") or time:match("min") then
                    seconds_left = number * 60
                elseif time:match("hores") or time:match("h")then
                    seconds_left = number * 60 * 60
                elseif time:match("dies") or time:match("d") then
                    seconds_left = number * 24 * 60 * 60
                elseif time:match("mesos") or time:match("mes") then
                    seconds_left = number * 30 * 24 * 60 * 60
                end
                
                if seconds_left then
                    create_and_add_timer(bot, jid, message, seconds_left)
                end
                    
            -- "Anar a la ITV el 30"
            elseif input:match("el ?d?i?a? ?(%d%d?)$") then
                local day = input:match("el ?d?i?a? ?(%d%d?)$")
                local date_table = os.date("*t", os.time())
                if day then
                    if day < 28 and day > 0 and day > date_table.day then
                        date_table.day = day
                        local seconds_left = os.time(date_table) - os.time()
                        create_and_add_timer(bot, jid, message, seconds_left)
                    else
                        msg:reply("That date cannot be handled.")
                    end
                end
                
            -- "Rentar l'habitació a les 12 / 12:30"
            elseif input:match("a les %d%d?:?%d?%d?$") then
                local hour = input:match("(%d%d?):?%d?%d?$")
                local minutes = input:match("%d?%d?$")
                
                if not minutes then
                    minutes = 0
                end
                
                local date_table = os.date("*t", os.time())
                date_table.hour = hour
                date_table.min = minutes
                local seconds_left = os.time(date_table) - os.time()
                create_and_add_timer(bot, jid, message, seconds_left)
            
            --"Rentar l'habitació a la 1 / 1:30"
            elseif input:match("a la %d:?%d?%d?$") then
                local hour = input:match("(%d):?%d?%d?$")
                local minutes = input:match("%d?%d?$")
                
                if not minutes then
                    minutes = 0
                end
                
                if hour == 1 then
                    local date_table = os.date("*t", os.time())
                    date_table.hour = hour
                    date_table.min = minutes
                    local seconds_left = os.time(date_table) - os.time()
                    create_and_add_timer(bot, jid, message, seconds_left)
                else
                    wrong_input(msg)
                end
                
            elseif input:lower() == "instructions" or input:lower() == "help" then
                msg:reply(instructions)
            else 
                wrong_input(msg)
            end
        end
    end
    bot:hook("message", process_message);
end 

