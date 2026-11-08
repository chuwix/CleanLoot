local _, CL = ...

local HELP = {
    "/cll               open the options panel",
    "/cll sim [n]       simulate n loot rolls (1-8) with a fake group",
    "/cll sim colors    one simulated drop of every colour",
    "/cll sim group <n> other players in the simulated group (1-39, default 4)",
    "/cll sim clear     remove the simulated rolls",
    "/cll restore       bring back rolls still running (automatic at login and /reload)",
    "/cll next|previous select a visible loot roll",
    "/cll inspect       toggle the selected item's inspection",
    "/cll need|greed|pass  roll on the selected item",
    "/cll debug [on|off]  trace every roll in chat (why one did or did not show)",
}

SLASH_CLEANLOOT1 = "/cleanloot"
SLASH_CLEANLOOT2 = "/cll"
SlashCmdList["CLEANLOOT"] = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd, rest = cmd:lower(), rest:lower()

    if cmd == "" or cmd == "options" or cmd == "config" then
        CL.Options.Open()
    elseif cmd == "sim" then
        local sub, arg = rest:match("^(%S*)%s*(.-)$")
        if sub == "clear" then
            CL.Sim.Clear()
            CL.Print("simulated rolls cleared.")
        elseif sub == "colors" or sub == "colours" then
            CL.Sim.Colors()
        elseif sub == "group" then
            local n = CL.Sim.SetGroupSize(tonumber(arg) or 4)
            CL.Print(("sim group: %d other players (applies to the next drops)."):format(n))
        else
            CL.Sim.Start(tonumber(sub) or 1)
        end
    elseif cmd == "debug" then
        if rest == "on" then CL.db.debug = true
        elseif rest == "off" then CL.db.debug = false
        else CL.db.debug = not CL.db.debug end
        CL.Print("debug " .. (CL.db.debug and "on: every roll is traced in chat (and kept in the saved variables)." or "off."))
    elseif cmd == "restore" then
        local n = CL.RestoreRolls()
        CL.Print(n > 0 and ("%d running roll(s) brought back."):format(n) or "no running roll to bring back.")
    elseif cmd == "next" or cmd == "previous" or cmd == "inspect"
        or cmd == "need" or cmd == "greed" or cmd == "pass" then
        CL.Keyboard.Action(cmd)
    else
        CL.Print("v" .. CL.Version() .. " -- commands:")
        for _, line in ipairs(HELP) do print("  " .. line) end
    end
end
