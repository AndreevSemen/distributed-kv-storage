local cartridge = require('cartridge')
local crud = require('crud')

local function init_tarantool()
	box.schema.space.create('kv', {
		format = {
			{'bucket_id', 'unsigned'},
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
	box.space.kv:create_index('bucket_id', {
		parts = {'bucket_id'},
		unique = false
	})
end

local function init(opts)
	crud.init_storage()
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
