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
helpers.server_command = fio.pathjoin(helpers.root, 'test', 'entrypoint', 'srv_kv_storage.lua')

t.before_suite(function()
    fio.rmtree(helpers.datadir)
    fio.mktree(helpers.datadir)
end)

return helpers
