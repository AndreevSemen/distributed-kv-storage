local log = require('log')
local vshard = require('vshard')
local cartridge = require('cartridge')
local errors = require('errors')

local err_vshard_router = errors.new_class("Vshard routing error")
local err_httpd = errors.new_class("httpd error")

local function InitLog()
    log.usecolor = true
end

local function NewLogWrapper(title)
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


local function FormResponse(request, code, json)
    local response = request:render{json = json}
    response.status = code
    return response
end

local function NotFound(request)
    return FormResponse(request, 404, {error = 'key not found'})
end

local function BadJSON(request)
    return FormResponse(request, 400, {error = 'invalid json'})
end

local function InternalError(request, error)
    return FormResponse(request, 500, {error = 'internal error', info = error})
end


local function HTTPCreate(request)
    local logger = NewLogWrapper('Create')

    local ok, json = pcall(request.json, request)
    if (not ok or json['key'] == nil or json['value'] == nil) then
        logger('info', 'request with invalid json: '..request.path)
        return BadJSON(request)
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
        logger('info', 'internal error')
        return InternalError(request, error.err)
    end

    if has_created then
        logger('info', 'creating record with existing key `'..key..'`')
        return FormResponse(request, 409, {error = 'key already exists'})
    end

    logger('trace', 'record with key `'..key..'` created')
    return FormResponse(request, 200, {result = 'record created'})
end

local function HTTPRead(request)
    local logger = NewLogWrapper('Read')

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
        logger('info', 'internal error')
        return InternalError(request, error.err)
    end

    if value == nil then
        logger('info', 'key `'..key..'` not found')
        return NotFound(request)
    end

    logger('trace', 'record with key `'..key..'` red')
    return FormResponse(request, 200, {value = value})
end

local function HTTPUpdate(request)
    local logger = NewLogWrapper('Update')

    local key = request:stash('id')
    local ok, json = pcall(request.json, request)
    if (not ok or json['value'] == nil) then
        logger('info', 'request with invalid json: '..request.path)
        return BadJSON(request)
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
        logger('info', 'internal error')
        return InternalError(request, error.err)
    end

    if has_updated == nil then
        logger('info', 'key `'..key..'` not found')
        return NotFound(request)
    end

    logger('trace', 'record with key `'..key..'` updated')
    return FormResponse(request, 200, {result = 'record updated'})
end

local function HTTPDelete(request)
    local logger = NewLogWrapper('Delete')

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
        logger('info', 'internal error')
        return InternalError(request, error.err)
    end

    if has_deleted == nil then
        logger('info', 'key `'..key..'` not found')
        return NotFound(request)
    end

    logger('trace', 'record with key `'..key..'` deleted')
    return FormResponse(request, 200, {result = 'record deleted'})
end


local function init(opts)
    rawset(_G, 'vshard', vshard)

    InitLog()

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
                HTTPCreate)
    httpd:route({public = true, method = 'PUT',  path = '/kv/:id'},
                HTTPUpdate)
    httpd:route({public = true, method = 'GET',  path = '/kv/:id'},
                HTTPRead)
    httpd:route({public = true, method = 'DELETE',  path = '/kv/:id'},
                HTTPDelete)

    return true
end


return {
    role_name = 'api',
    init = init,
    dependencies = {'cartridge.roles.vshard-router'},
}
