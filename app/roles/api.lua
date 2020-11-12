local log = require('log')
local cartridge = require('cartridge')
-- local crud = require('crud')
local errors = require('errors')
local vshard = require('vshard')

local err_httpd = errors.new_class("httpd error")

local function init_log()
    log.usecolor = true
end

local function new_log_wrapper(title)
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


local function form_response(request, code, json)
    local response = request:render{json = json}
    response.status = code
    return response
end

local function not_found(request)
    return form_response(request, 404, {error = 'key not found'})
end

local function bad_json(request)
    return form_response(request, 400, {error = 'invalid json'})
end

local function internal_error(request, error)
    return form_response(request, 500, {error = 'internal error', info = error})
end


local function http_create(request)
    local logger = new_log_wrapper('Create')

    local ok, json = pcall(request.json, request)
    if (not ok or json['key'] == nil or json['value'] == nil) then
        logger('info', 'request with invalid json: '..request.path)
        return bad_json(request)
    end

    local key = json['key']
    local value = json['value']

    local bucket_id = vshard.router.bucket_id(key)
    local result, error = crud.get('kv', key, {bucket_id = bucket_id})

    if error ~= nil then
        logger('info', 'internal error')
        return internal_error(request, error.err)
    end

    if table.getn(result['rows']) ~= 0 then
        logger('info', 'creating record with existing key `'..key..'`')
        return form_response(request, 409, {error = 'key already exists'})
    end

    local result, error = crud.insert_object('kv', {
        bucket_id = box.NULL,
        key = key,
        value = value,
    })

    if error ~= nil then
        logger('info', 'internal error')
        return internal_error(request, error.err)
    end

    logger('trace', 'record with key `'..key..'` created')
    return form_response(request, 200, {result = 'record created'})
end

local function http_read(request)
    local logger = new_log_wrapper('Read')

    local key = request:stash('id')

    local bucket_id = vshard.router.bucket_id(key)
    local result, error = crud.get('kv', key, {bucket_id = bucket_id})

    if error ~= nil then
        logger('info', 'internal error')
        return internal_error(request, error.err)
    end

    local got = result['rows']
    if table.getn(got) == 0 then
        logger('info', 'key `'..key..'` not found')
        return not_found(request)
    end

    logger('trace', 'record with key `'..key..'` red')
    return form_response(request, 200, {
        -- first row (1/1)
        -- third field (value)
        value = got[1][3],
    })
end

local function http_update(request)
    local logger = new_log_wrapper('Update')

    local key = request:stash('id')
    local ok, json = pcall(request.json, request)
    if (not ok or json['value'] == nil) then
        logger('info', 'request with invalid json: '..request.path)
        return bad_json(request)
    end

    local value = json['value']

    local bucket_id = vshard.router.bucket_id(key)
    local result, error = crud.update('kv',
        key,
        {{'=', 3, value}},
        {bucket_id = bucket_id}
    )

    if error ~= nil then
        logger('info', 'internal error')
        return internal_error(request, error.err)
    end

    local updated = result['rows']
    if table.getn(updated) == 0 then
        logger('info', 'key `'..key..'` not found')
        return not_found(request)
    end

    logger('trace', 'record with key `'..key..'` updated')
    return form_response(request, 200, {result = 'record updated'})
end

local function http_delete(request)
    local logger = new_log_wrapper('Delete')

    local key = request:stash('id')

    local bucket_id = vshard.router.bucket_id(key)
    local result, error = crud.delete('kv', key, {bucket_id = bucket_id})

    if error ~= nil then
        logger('info', 'internal error')
        return internal_error(request, error.err)
    end

    local deleted = result['rows']
    if table.getn(deleted) == 0 then
        logger('info', 'key `'..key..'` not found')
        return not_found(request)
    end

    logger('trace', 'record with key `'..key..'` deleted')
    return form_response(request, 200, {result = 'record deleted'})
end


local function init(opts)
    init_log()
    crud.init_router()

    if opts.is_master then
        box.schema.user.grant('guest',
            'read,write,execute',
            'universe',
            nil,
            { if_not_exists = true }
        )
    end

    local httpd = cartridge.service_get('httpd')

    if not httpd then
        return nil, err_httpd:new("not found")
    end

    httpd:route({public = true, method = 'POST'  , path = '/kv'}, http_create)
    httpd:route({public = true, method = 'PUT'   ,  path = '/kv/:id'}, http_update)
    httpd:route({public = true, method = 'GET'   ,  path = '/kv/:id'}, http_read)
    httpd:route({public = true, method = 'DELETE',  path = '/kv/:id'}, http_delete)

    return true
end


return {
    role_name = 'api',
    init = init,
    dependencies = {
        'cartridge.roles.crud-router',
    },
}
