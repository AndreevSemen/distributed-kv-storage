-- This file is required automatically by luatest.
-- Add common configuration here.

local fio = require('fio')
local t = require('luatest')

local ok, cartridge_helpers = pcall(require, 'cartridge.test-helpers')
if not ok then
    log.error('Please, install cartridge rock to run tests')
    os.exit(1)
end

local helpers = table.copy(cartridge_helpers)

helpers.root = fio.dirname(fio.abspath(package.search('init')))
helpers.datadir = fio.pathjoin(helpers.root, 'tmp', 'storage_test')

function helpers.entrypoint(command_name)
    local path_to_entry = fio.pathjoin(
        helpers.root,
        'test',
        'entrypoint',
        string.format('%s.lua', command_name)
    )

    if not fio.path.exists(path_to_entry) then
        error(string.format('no such entrypoint: %s', path_to_entry), 2)
    end

    return path_to_entry
end

t.before_suite(function()
    fio.rmtree(helpers.datadir)
    fio.mktree(helpers.datadir)
end)

return helpers
