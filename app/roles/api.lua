local log = require('log')
local vshard = require('vshard')
local cartridge = require('cartridge')
local errors = require('errors')

local err_vshard_router = errors.new_class("Vshard routing error")
local err_httpd = errors.new_class("httpd error")

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
        logger('error', 'request with invalid json: '..request.path)
        return bad_json(request)
    end

    local key = json['key']
    local value = json['value']

    local bucket_id = vshard.router.bucket_id(key)
    local has_created, error = err_vshard_router:pcall(
        vshard.router.call,
        bucket_id,
        'write',
        'create',
        {key, value}
    )

    if error then
        logger('error', 'internal error')
        return internal_error(request, error.err)
    end

    if has_created then
        logger('error', 'creating record with existing key `'..key..'`')
        return form_response(request, 409, {error = 'key already exists'})
    end

    logger('info', 'record with key `'..key..'` created')
    return form_response(request, 200, {result = 'record created'})
end

local function http_read(request)
    local logger = new_log_wrapper('Read')

    local key = request:stash('id')
    local bucket_id = vshard.router.bucket_id(key)

    local value, error = err_vshard_router:pcall(
        vshard.router.call,
        bucket_id,
        'read',
        'read',
        {key}
    )

    if error then
        logger('error', 'internal error')
        return internal_error(request, error.err)
    end

    if value == nil then
        logger('error', 'key `'..key..'` not found')
        return not_found(request)
    end

    logger('info', 'record with key `'..key..'` red')
    return form_response(request, 200, {value = value})
end

local function http_update(request)
    local logger = new_log_wrapper('Update')

    local key = request:stash('id')
    local ok, json = pcall(request.json, request)
    if (not ok or json['value'] == nil) then
        logger('error', 'request with invalid json: '..request.path)
        return bad_json(request)
    end

    local value = json['value']

    local bucket_id = vshard.router.bucket_id(key)
    local has_updated, error = err_vshard_router:pcall(
        vshard.router.call,
        bucket_id,
        'write',
        'update',
        {key, value}
    )

    if error then
        logger('error', 'internal error')
        return internal_error(request, error.err)
    end

    if has_updated == nil then
        logger('error', 'key `'..key..'` not found')
        return not_found(request)
    end

    logger('info', 'record with key `'..key..'` updated')
    return form_response(request, 200, {result = 'record updated'})
end

local function http_delete(request)
    local logger = new_log_wrapper('Delete')

    local key = request:stash('id')
    local bucket_id = vshard.router.bucket_id(key)

    local has_deleted, error = err_vshard_router:pcall(
        vshard.router.call,
        bucket_id,
        'write',
        'delete',
        {key}
    )

    if error then
        logger('error', 'internal error')
        return internal_error(request, error.err)
    end

    if has_deleted == nil then
        logger('error', 'key `'..key..'` not found')
        return not_found(request)
    end

    logger('info', 'record with key `'..key..'` deleted')
    return form_response(request, 200, {result = 'record deleted'})
end


local function init(opts)
    rawset(_G, 'vshard', vshard)

    if opts.is_master then
        box.schema.user.grant('guest',
            'read,write,execute',
            'universe',
            nil, { if_not_exists = true }
        )
    end

    local httpd = cartridge.service_get('httpd')

    if not httpd then
        return nil, err_httpd:new("not found")
    end

    httpd:route({public = true, method = 'POST', path = '/kv'},
                http_create)
    httpd:route({public = true, method = 'PUT',  path = '/kv/:id'},
                http_update)
    httpd:route({public = true, method = 'GET',  path = '/kv/:id'},
                http_read)
    httpd:route({public = true, method = 'DELETE',  path = '/kv/:id'},
                http_delete)

    return true
end


return {
    role_name = 'api',
    init = init,
    dependencies = {'cartridge.roles.vshard-router'},
}
