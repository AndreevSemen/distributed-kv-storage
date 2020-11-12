local t = require('luatest')
local log = require('log')
local fio = require('fio')

local shared = require('test.helper')
local helper = {shared = shared }


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

helper.base_kv_endpoint = '/kv'

function helper.key_path(key)
    return join_url(helper.base_kv_endpoint, key)
end

return helper
