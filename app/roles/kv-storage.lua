local cartridge = require('cartridge')

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

local function init(opts)
	if opts.is_master then
        init_tarantool()
    end
    return true
end

return {
	role_name = 'kv-storage',
	init = init,
	dependencies = {
		'cartridge.roles.crud-storage',
    },
}
