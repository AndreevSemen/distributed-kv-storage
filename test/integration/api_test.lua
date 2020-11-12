local fio = require('fio')
local t = require('luatest')


local g = t.group('integration_api')

local helper = require('test.helper.integration')

local server_command = 'srv_kv_storage'

g.before_all = function()
    g.cluster = helper.shared.Cluster:new({
        base_http_port = 8080,
        base_advertise_port = 3000,
        server_command = helper.shared.entrypoint(server_command),
        datadir = helper.shared.datadir,
        use_vshard = true,
        replicasets = {
            {
                alias = 'router',
                uuid = helper.shared.uuid('a'),
                roles = {
                    'api',
                },
                servers = {
                    { instance_uuid = helper.shared.uuid('a', 1), alias = 'router' },
                },
            },
            {
                alias = 'kv-storage',
                uuid = helper.shared.uuid('b'),
                roles = {
                    'kv-storage',
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

    g.cluster:start()
    g.router = g.cluster.main_server
end

g.after_all = function()
    g.cluster:stop()
    fio.rmtree(g.cluster.datadir)
end

g.before_each(function()
    for _, server in ipairs(g.cluster.servers) do
        server.net_box:eval([[
            local space = box.space.kv
            if space ~= nil and not box.cfg.read_only then
                space:truncate()
            end
        ]])
    end
end)

g.after_each(function() end)

-- CRUD helpers
local function create(key, value)
    return g.router:http_request('post', helper.base_kv_endpoint, {
        json = {
            key = key,
            value = value,
        },
        http = { timeout = 1 },
        raise = false,
    })
end

local function read(key)
    return g.router:http_request('get', helper.key_path(key), { http = { timeout = 1 } , raise = false })
end

local function update(key, value)
    return g.router:http_request('put', helper.key_path(key), {
        json = { value = value },
        http = {
            timeout = 1
        },
        raise = false,
    })
end

local function delete(key)
    return g.router:http_request('delete', helper.key_path(key), { http = { timeout = 1 }, raise = false })
end


-- Expected bodies for some operations
local successfully_created_body = { result = 'record created' }
local successfully_updated_body = { result = 'record updated' }
local successfully_deleted_body = { result = 'record deleted' }


-- Is request ok helper
local function assert_resp_ok(resp, expected_body)
    t.assert_equals(resp.status, 200)
    if expected_body ~= nil then
        t.assert_equals(resp.json, expected_body)
    end
end


-- Is key already exists helper
local function assert_err_already_exists(resp)
    t.assert_equals(resp.status, 409)
    t.assert_equals(resp.json, { error = 'key already exists' })
end


-- Is key not found helper
local function assert_err_not_found(resp)
    t.assert_equals(resp.status, 404)
    t.assert_equals(resp.json, { error = 'key not found' })
end



g.test_read_not_found = function()
    local resp = read('some_key')
    assert_err_not_found(resp)
end

g.test_update_not_found = function()
    local resp = update('some_key', { greeting = 'hello_world' })
    assert_err_not_found(resp)
end

g.test_delete_not_found = function()
    local resp = delete('some_key')
    assert_err_not_found(resp)
end

g.test_create_ok = function()
    local resp = create('awesome key', { some_json = { 'opt 1', 'opt 2', 'opt 3'} })
    assert_resp_ok(resp, successfully_created_body)
end

g.test_create_already_exists = function()
    local resp = create('some_key', { name = 'semen' })
    assert_resp_ok(resp, successfully_created_body)

    local resp  = create('some_key', { array = {0, 1, 2, 3} })
    assert_err_already_exists(resp)


    local resp = create('other_key', { array = {0, 1, 2, 3} })
    assert_resp_ok(resp, successfully_created_body)

    local resp  = create('other_key', { name = 'semen' })
    assert_err_already_exists(resp)
end

g.test_read_ok = function()
    local value = {
        some_json_key = 'some_json_value'
    }
    local resp = create('some', value)
    assert_resp_ok(resp, successfully_created_body)

    local resp = read('some')
    assert_resp_ok(resp, { value = value })
end

g.test_update_ok = function()
    local value = {
        some_json_key = 'some_json_value'
    }
    local resp = create('some', value)
    assert_resp_ok(resp, successfully_created_body)

    local resp = read('some')
    assert_resp_ok(resp, { value = value })


    local value = {
        another_json_key = 'another_json_value'
    }
    local resp = update('some', value)
    assert_resp_ok(resp, successfully_updated_body)

    local resp = read('some')
    assert_resp_ok(resp, { value = value })
end

g.test_delete_ok = function()
    local value = {
        some_json_key = 'some_json_value'
    }
    local resp = create('some', value)
    assert_resp_ok(resp, successfully_created_body)

    local resp = read('some')
    assert_resp_ok(resp, { value = value })


    local resp = delete('some')
    assert_resp_ok(resp, successfully_deleted_body)

    local resp = read('some')
    assert_err_not_found(resp)

    local resp = delete('some')
    assert_err_not_found(resp)
end

g.test_multi_operation = function()
    local value1 = { ['hello dear world'] = {1, 2, 3} }
    local value2 = { words = {'some', 'string', 'list'} }
    local value3 = { ['parting'] = {'bye', 'bye', 'dear', 'world' } }

    -- -- create keys
    -- key 1
    local resp = create('key1', value1)
    assert_resp_ok(resp, successfully_created_body)
    local resp  = create('key1', value2)
    assert_err_already_exists(resp)

    -- key 2
    local resp = create('key2', value2)
    assert_resp_ok(resp, successfully_created_body)
    local resp  = create('key2', value1)
    assert_err_already_exists(resp)

    -- key 3
    local resp = create('key3', value3)
    assert_resp_ok(resp, successfully_created_body)
    local resp  = create('key3', value3)
    assert_err_already_exists(resp)

    -- -- read keys
    local resp = read('key1')
    assert_resp_ok(resp, { value = value1 })
    local resp = read('key2')
    assert_resp_ok(resp, { value = value2 })
    local resp = read('key3')
    assert_resp_ok(resp, { value = value3 })

    -- -- update keys
    local resp = update('key1', value2)
    assert_resp_ok(resp, successfully_updated_body)
    local resp = update('key2', value3)
    assert_resp_ok(resp, successfully_updated_body)
    local resp = update('key3', value1)
    assert_resp_ok(resp, successfully_updated_body)

    -- -- read keys
    local resp = read('key1')
    assert_resp_ok(resp, { value = value2 })
    local resp = read('key2')
    assert_resp_ok(resp, { value = value3 })
    local resp = read('key3')
    assert_resp_ok(resp, { value = value1 })

    -- -- delete keys
    local resp = delete('key1')
    assert_resp_ok(resp, successfully_deleted_body)
    local resp = delete('key2')
    assert_resp_ok(resp, successfully_deleted_body)
    local resp = delete('key3')
    assert_resp_ok(resp, successfully_deleted_body)

    -- -- read keys (not found)
    local resp = read('key1')
    assert_err_not_found(resp)
    local resp = read('key2')
    assert_err_not_found(resp)
    local resp = read('key3')
    assert_err_not_found(resp)

    -- -- create keys
    -- key 1
    local resp = create('key1', value1)
    assert_resp_ok(resp, successfully_created_body)
    local resp  = create('key1', value2)
    assert_err_already_exists(resp)

    -- key 2
    local resp = create('key2', value2)
    assert_resp_ok(resp, successfully_created_body)
    local resp  = create('key2', value1)
    assert_err_already_exists(resp)

    -- key 3
    local resp = create('key3', value3)
    assert_resp_ok(resp, successfully_created_body)
    local resp  = create('key3', value3)
    assert_err_already_exists(resp)

    -- -- read keys
    local resp = read('key1')
    assert_resp_ok(resp, { value = value1 })
    local resp = read('key2')
    assert_resp_ok(resp, { value = value2 })
    local resp = read('key3')
    assert_resp_ok(resp, { value = value3 })
end
