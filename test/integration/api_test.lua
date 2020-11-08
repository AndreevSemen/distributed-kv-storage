local fio = require('fio')

local t = require('luatest')
local g = t.group('integration_api')

local log = require('log')

local helper = require('test.helper.integration')


local url = 'localhost:8081/kv'
local http_client = require('http.client')


g.before_all = function()
    g.cluster = helper.shared.Cluster:new({
        base_http_port = 8080,
        base_advertise_port = 3000,
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
            ['ENGINE'] = 'memtx',
        },
    })

    log.info(g.cluster)

    g.cluster:start()

    helper.router = g.cluster.servers[1]
end

g.after_all = function()
    g.cluster:stop()
    fio.rmtree(g.cluster.datadir)
end

-- CRUD helpers
local function create(key, value)
    return g.router:http_request('get', url, {
        json = {
            key = key,
            value = value,
        },
        http = { timeout = 1 },
    })
end

local function read(key)
    return g.router:http_request('get', url..'/'..key, { http = { timeout = 1 } })
end

local function update(key, value)
    return g.router:http_request('put', url..'/'..key, {
        json = { value = value },
        http = {
            timeout = 1
        },
    })
end

local function delete(key)
    return g.router:http_request('delete', url..'/'..key, { http = { timeout = 1 } })
end


-- Is request ok helpers
local function ok(resp, expected_body)
    t.assert_equals(resp.status, 200)
    if expected_body ~= nil then
        t.assert_equals(resp.body, expected_body)
    end
end

local function create_ok(key, value)
    ok(create(key, value), { result = 'record created' })
end

local function read_ok(key, expected_value)
    ok(read(key), { value = expected_value })
end

local function update_ok(key, value)
    ok(update(key, value), { result = 'record updated' })
end

local function delete_ok(key)
    ok(delete(key), { result = 'record deleted' })
end


-- Is key already exists helpers
local function already_exists(resp)
    t.assert_equals(resp.status, 409)
    t.assert_equals(resp.body, { error = 'key already exists' })
end

local function create_already_exists(key, value)
    already_exists(create(key, value))
end


-- Is key not found helpers
local function not_found(resp)
    t.assert_equals(resp.status, 404)
    t.assert_equals(resp.body, {error = 'key not found'})
end

local function read_not_found(key)
    not_found(read(key))
end

local function update_not_found(key, value)
    not_found(update(key, value))
end

local function delete_not_found(key)
    not_found(delete(key))
end


g.test_read_not_found = function()
    read_not_found('some_key')
end

g.test_update_not_found = function()
    update_not_found('some_key', {'hello_world'})
end

g.test_delete_not_found = function()
    not_found(delete('some_key'))
end

g.test_create_ok = function()
    create_ok('awesome key', { some_json = { 'opt 1', 'opt 2', 'opt 3'} })
end

g.test_create_already_exists = function()
    create_ok('some_key', {})
    create_already_exists('some_key', {})
end

g.test_read_ok = function()
    local value = {
        some_json_key = 'some_json_value'
    }
    create_ok('some', value)
    read_ok('some', value)
end

g.test_update_ok = function()
    local value = {
        some_json_key = 'some_json_value'
    }
    create_ok('some', value)
    read_ok('some', value)

    value = {
        another_json_key = 'another_json_value'
    }
    update_ok('some', value)
    read_ok('some', value)
end

g.test_delete_ok = function()
    local value = {
        some_json_key = 'some_json_value'
    }
    create_ok('some', value)
    read_ok('some', value)

    delete_ok('some')
    read_not_found('some')
    delete_not_found('some')
end

g.test_multi_operation = function()
    local value1 = { ['hello dear world'] = {1, 2, 3} }
    local value2 = { 'some', 'string', 'list' }
    local value3 = { ['parting'] = {'bye', 'bye', 'dear', 'world' } }

    create_ok('key1', value1)
    create_already_exists('key1', value2)
    create_ok('key2', value2)
    create_already_exists('key2', value1)
    create_ok('key3', value3)
    create_already_exists('key3', value3)

    read_ok('key1', value1)
    read_ok('key2', value2)
    read_ok('key3', value3)

    update_ok('key1', value2)
    update_ok('key2', value3)
    update_ok('key3', value1)

    read_ok('key1', value2)
    read_ok('key2', value3)
    read_ok('key3', value1)

    delete_ok('key1')
    delete_ok('key2')
    delete_ok('key3')

    read_not_found('key1')
    read_not_found('key2')
    read_not_found('key3')

    create_ok('key1', value1)
    create_ok('key2', value2)
    create_ok('key3', value3)

    read_ok('key1', value1)
    read_ok('key2', value2)
    read_ok('key3', value3)
end
