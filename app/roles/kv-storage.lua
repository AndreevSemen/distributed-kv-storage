local httpserver = require('http.server')
local log        = require('log')

local function init_tarantool()
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

local function new_log_wrapper(title)
	return function(level, data)
		local args = { "(%s): %s",
			title,
			data
		}

		if level == 'error' then
			log.error(unpack(args))
		elseif level == 'info' then
			log.info(unpack(args))
		end
	end
end

local function create(key, value)
	local logger = new_log_wrapper('create')

	local error = box.space.kv:get(key)
	if (error ~= nil) then
		logger('error', 'creating record with existing key `'..key..'`')
		return false
	end

	box.space.kv:insert({key, value})
	logger('info', 'record with key `'..key..'` created')
	return true
end

local function read(key)
	local logger = new_log_wrapper('read')

	local got = box.space.kv:get(key)
	if (got == nil) then
		logger('error', 'key `'..key..'` not found')
		return nil
	end

	logger('info', 'record with key `'..key..'` red')
	return got
end

local function update(key, value)
	local logger = new_log_wrapper('update')

	local updated = box.space.kv:update(key, {{'=', 2, value}})
	if (updated == nil) then
		logger('error', 'key `'..key..'` not found')
		return false
	end

	logger('info', 'record with key `'..key..'` updated')
	return true
end

local function delete(key)
	local logger = new_log_wrapper('delete')

	local deleted = box.space.kv:delete(key)
	if (deleted == nil) then
		logger('error', 'key `'..key..'` not found')
		return nil
	end

	logger('info', 'record with key `'..key..'` deleted')
	return deleted[2]
end

local exported_functions = {
	create = create,
	read   = read,
	update = update,
	delete = delete,
}

local function init(opts)
    if opts.is_master then
        init_tarantool()

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
