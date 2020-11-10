local t = require('luatest')
local log = require('log')
local fio = require('fio')

local shared = require('test.helper')
local helper = {shared = shared }


local root_url = '/'
local function join_url(...)
    local url = ''
    for i, piece in ipairs({...}) do
        if i == 1 then
            url = piece
        else
            url = string.format('%s/%s', url, piece)
        end
    end
    return url
end

function helper.path_to_storage(storage)
    return string.format('/%s', storage)
end

function helper.key_path_formatter(storage_path)
    return function(key)
        return join_url(storage_path, key)
    end
end

return helper
