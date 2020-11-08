local t = require('luatest')
local log = require('log')

local shared = require('test.helper')
local helper = {shared = shared }

t.before_suite(function()
    t.cluster = helper.shared.Cluster:new({
        server_command = helper.shared.server_command,
        datadir = helper.shared.datadir,
        use_vshard = true,
        replicasets = {
            {
                alias = 'router',
                uuid = helper.shared.uuid('a'),
                roles = {
                    'app.roles.api',
                },
                servers = {
                    { instance_uuid = helper.shared.uuid('a', 1), alias = 'router' },
                },
            },
            {
                alias = 'kv-storage',
                uuid = helper.shared.uuid('b'),
                roles = {
                    'app.roles.kv-storage',
                },
                servers = {
                    { instance_uuid = helper.shared.uuid('b', 1), alias = 'kv-storage-1-master' },
                    { instance_uuid = helper.shared.uuid('b', 2), alias = 'kv-storage-1-replica-1' },
                    { instance_uuid = helper.shared.uuid('b', 3), alias = 'kv-storage-1-replica-2' },
                },
            },
        },
        env = {
            ['ENGINE'] = 'memtx'
        },
    })
    t.cluster:start()
    t.space_format = t.cluster.servers[2].net_box.space.customers:format()

    helper.router = t.cluster.servers[1]
end)

t.after_suite(function() t.cluster:stop() end)

return helper
