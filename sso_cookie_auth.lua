local cjson  = require 'cjson'

local cookie_auth_data = ngx.unescape_uri(ngx.var.cookie_FIXME_YOUR_AUTH_DATA_COOKIE)
local cookie_auth_sign = ngx.unescape_uri(ngx.var.cookie_FIXME_YOUR_AUTH_SIGN_COOKIE)
local hmac = ""
local timestamp = ""

local keys = {}

local key = ""
local sso_url = ""

local sso_domain_match = ngx.re.match(ngx.var.host, "FIXME_ALLOWED_DOMAINS_REGEX")
if sso_domain_match then
  sso_url = "https://sso." .. sso_domain_match[0]
  key = keys[sso_domain_match[0]]
  if key == nil then
    ngx.log(ngx.ERR, "Unable to fetch key for: " .. sso_domain_match[0])
    ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
    return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
  end
else
  ngx.log(ngx.ERR, "Unknown SSO domain: " .. ngx.var.host)
  ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
  return ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
end

local function validate_allowed_audience(allowed_audiences, present_audiences)
  if allowed_audiences == '' then return true end
  for allowed_audience in string.gmatch(allowed_audiences, '([^, ]+)') do
    for _, audience in ipairs(present_audiences) do
      if allowed_audience == audience then return true end
    end
  end
  return false
end

-- Verify signature
if cookie_auth_data ~= nil and cookie_auth_sign ~= nil then
    local sign = (cookie_auth_sign:gsub("..", function (cc)
                    return string.char(tonumber(cc, 16))
                  end))

    if ngx.hmac_sha1(key, cookie_auth_data) == sign then
      local auth_data = cjson.decode(ngx.decode_base64(cookie_auth_data))
      -- Verify validity of signature
      if tonumber(auth_data['exp']) >= ngx.time() then
        if auth_data['uid'] ~= cjson.null then
          ngx.req.set_header("X-Forwarded-User", auth_data['uid'])
        end

        -- Sanitize required audience
        sso_allowed_audience = 'nobody'
        if ngx.var.sso_allowed_audience ~= nil and ngx.var.sso_allowed_audience ~= '' then
          if ngx.var.sso_allowed_audience == 'any' then
            sso_allowed_audience = ''
          else
            sso_allowed_audience = ngx.var.sso_allowed_audience
          end
        end

        -- Verify if the user has appropriate audience
        if not validate_allowed_audience(sso_allowed_audience, auth_data['aud']) then
          ngx.log(ngx.ERR, "User " .. auth_data['uid'] .. "doesn't have any of allowed audiences.")
          ngx.status = ngx.HTTP_FORBIDDEN
          return ngx.exit(ngx.HTTP_FORBIDDEN)
        end

        -- We have validated auth cookie and passing the request
        return
      end
    end
end

-- Being here means, that your signature was invalid/expired/missing
-- and you should be redirected to SSO

-- Convert a table of arguments to an URI string
local function uri_args_string (args)
    if not args then
        args = ngx.req.get_uri_args()
    end
    String = "?"
    for k,v in pairs(args) do
        String = String..tostring(k).."="..tostring(v).."&"
    end
    return string.sub(String, 1, string.len(String) - 1)
end

local back_url = ngx.var.scheme .. "://" .. ngx.var.host
if ngx.var.sso_return_url ~= nil and ngx.var.sso_return_url ~= '' then
 back_url = ngx.var.sso_return_url
end
back_url = back_url .. ngx.var.uri .. uri_args_string()

return ngx.redirect(sso_url .. "/?r=".. ngx.escape_uri(ngx.encode_base64(back_url)))

