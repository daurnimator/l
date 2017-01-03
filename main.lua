#!/usr/bin/env lua

local cqueues = require "cqueues"
local ca = require "cqueues.auxlib"
local cs = require "cqueues.socket"
local cq = cqueues.new()

-- localise incase user changes global environment
local _G = _G
local getmetatable = getmetatable
local load = load
if _VERSION == "Lua 5.1" then
	-- In 5.1 load() didn't take a string
	load = loadstring
	-- note: loadstring in 5.1 did not take a 'mode' argument
end
local pcall = pcall
local select = select
local type = type
local xpcall = xpcall
local traceback = debug.traceback
local stdout = io.stdout
local stderr = io.stderr
local tostring = tostring

local banner = string.format("lua-repl %s\n", _VERSION)

local function get_prompt(firstline)
	local prompt
	if firstline then
		prompt = _G._PROMPT
	else
		prompt = _G._PROMPT2
	end
	if type(prompt) ~= "string" then
		if firstline then
			prompt = "> "
		else
			prompt = ">> "
		end
	end
	return prompt
end

local function saveline(line)
	-- TODO: history saving
end

local function msg_handler(e)
	if type(e) ~= "string" then
		if getmetatable(e).__tostring then
			e = getmetatable(e).__tostring(e)
			if type(e) == "string" then
				return e
			end
		end
		e = "(error object is a " .. type(e) .. " value)"
	end
	return traceback(e, 2)
end

cq:wrap(function()
	local stdin = ca.assert(cs.fdopen(0))
	stdout:write(banner)
	while true do
		stdout:write(get_prompt(true))
		stdout:flush()

		local f, err

		local line = stdin:read("*l")
		if line == nil then
			break
		end
		if line:sub(1,1) == "=" then
			line = "return " .. line
		else -- addreturn
			local l = "return " .. line
			f = load(l, "=stdin", "t")
		end
		if f then
			saveline(line)
		else
			while true do
				f, err = load(line, "=stdin", "t")
				if f then
					saveline(line)
					break
				end
				if err:sub(-5) ~= "<eof>" then
					saveline(line)
					break
				end
				stdout:write(get_prompt(false))
				stdout:flush()
				local newline = stdin:read("*l")
				if newline == nil then
					saveline(line)
					return
				end
				line = line .. "\n" .. newline
			end
		end
		if f then -- docall
			local function handle_results(ok, ...)
				if ok then
					if select("#", ...) > 0 then
						local print_ok, print_err = pcall(_G.print, ...)
						if not print_ok then
							if type(print_err) ~= "string" then
								print_err = "(null)"
							end
							err = "error calling 'print' (" .. print_err .. ")"
						end
					end
				else
					err = ...
				end
			end
			handle_results(xpcall(f, msg_handler))
		end
		if err then
			stderr:write(err, "\n")
			stderr:flush()
		end
	end
end)
_G.cq = cq
while true do
	local ok, err, _, thd = cq:step()
	if not ok then
		stderr:write(traceback(thd, tostring(err)))
		stderr:flush()
	end
end
