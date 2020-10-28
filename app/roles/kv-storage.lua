local httpserver = require('http.server')
local log        = require('log')


local function InitLog()
	log.usecolor = true
end

local function InitTarantool()
	box.schema.space.create('kv', {
		format = {
		    {'key', 'string'},
	    	{'value', 'map'},
	    },
		if_not_exists = true,
	})
	box.space.kv:create_index('primary', {
		type = 'tree',
		parts = {'key'},
		if_not_exists = true,
	})
end

local function NewLogWrapper(title)
	return function(level, data)
		local color = ""
		if level == 'trace' then
			color = "\27[32m"
		end
		if level == 'info' then
			color = "\27[33m"
		end

		log.info("%s[%s] (%s): %s\27[0m", color, os.date("%H:%M:%S %d/%m/%y"), title, data)
	end
end

local function Create(key, value)
	local logger = NewLogWrapper('Create')

	local error = box.space.kv:get(key)
	if (error ~= nil) then
		logger('info', 'creating record with existing key `'..key..'`')
		return false
	end

	box.space.kv:insert({key, value})
	logger('trace', 'record with key `'..key..'` created')
	return true
end

local function Read(key)
	local logger = NewLogWrapper('Read')

	local got = box.space.kv:get(key)
	if (got == nil) then
		logger('info', 'key `'..key..'` not found')
		return nil
	end

	logger('trace', 'record with key `'..key..'` red')
	return got
end

local function Update(key, value)
	local logger = NewLogWrapper('Create')

	local updated = box.space.kv:update(key, {{'=', 2, value}})
	if (updated == nil) then
		logger('info', 'key `'..key..'` not found')
		return false
	end

	logger('trace', 'record with key `'..key..'` updated')
	return true
end

local function Delete(key)
	local logger = NewLogWrapper('Delete')

	local deleted = box.space.kv:delete(key)
	if (deleted == nil) then
		logger('info', 'key `'..key..'` not found')
		return nil
	end

	logger('trace', 'record with key `'..key..'` deleted')
	return deleted[2]
end

local exported_functions = {
	create = Create,
	read   = Read,
	update = Update,
	delete = Delete,
}

local function init(opts)
    if opts.is_master then
        InitTarantool()
        InitLog()

        for name in pairs(exported_functions) do
            box.schema.func.create(name, {if_not_exists = true})
            box.schema.role.grant('public',
            	                  'execute',
            	                  'function',
            	                  name,
            	                  {if_not_exists = true})
        end
    end

    for name, func in pairs(exported_functions) do
        rawset(_G, name, func)
    end

    return true
end

return {
	role_name = 'kv-storage',
	init = init,
	dependencies = {
        'cartridge.roles.vshard-storage',
    },
}
