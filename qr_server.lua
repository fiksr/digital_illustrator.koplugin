--[[--
Local Wi-Fi QR Code Server for Gemini AI Book Illustrator plugin.
Allows instant pairing from any mobile phone on local Wi-Fi:
Scans QR code -> Opens web form -> Sends API keys & settings directly to Kindle.
--]]--

local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local QRMessage = require("ui/widget/qrmessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local QRServer = {}
QRServer.__index = QRServer

local function getLocalIP()
    local ok_sock, socket = pcall(require, "socket")
    if ok_sock and socket and socket.udp then
        local s = socket.udp()
        if s then
            s:settimeout(0.1)
            local ok = pcall(s.setpeername, s, "8.8.8.8", 80)
            if ok then
                local ip, _ = s:getsockname()
                s:close()
                if ip and ip ~= "127.0.0.1" and #ip > 0 then
                    return ip
                end
            end
        end
    end

    -- Linux / Kindle fallback
    local p = io.popen("ifconfig wlan0 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d: -f2")
    if p then
        local out = p:read("*l")
        p:close()
        if out and #out > 0 then return out:gsub("%s+", "") end
    end

    local p2 = io.popen("ip route get 1.1.1.1 2>/dev/null | awk '{print $7}'")
    if p2 then
        local out = p2:read("*l")
        p2:close()
        if out and #out > 0 then return out:gsub("%s+", "") end
    end

    return nil
end

local function urlDecode(str)
    if not str then return "" end
    str = str:gsub("+", " ")
    str = str:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end)
    return str
end

local function parseFormBody(body)
    local params = {}
    if not body then return params end
    for pair in string.gmatch(body, "([^&]+)") do
        local k, v = pair:match("([^=]+)=(.*)")
        if k and v then
            params[urlDecode(k)] = urlDecode(v):gsub("^%s+", ""):gsub("%s+$", "")
        end
    end
    return params
end

local function buildHTMLPage(settings)
    local gemini_key = (settings and settings:get("api_key")) or ""
    local fal_key = (settings and settings:get("fal_key")) or ""
    local openai_key = (settings and settings:get("openai_key")) or ""
    local cur_img_model = (settings and settings:get("image_model")) or "pollinations-flux"
    local cur_art_style = (settings and settings:get("art_style")) or "auto_genre"

    return string.format([[<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>✨ Gemini Illustrator - Kindle Setup</title>
<style>
  * { box-sizing: border-box; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; }
  body { background: #0f172a; color: #e2e8f0; margin: 0; padding: 20px; display: flex; justify-content: center; min-height: 100vh; align-items: center; }
  .card { background: #1e293b; width: 100%%; max-width: 500px; padding: 28px; border-radius: 20px; box-shadow: 0 10px 30px rgba(0,0,0,0.5); border: 1px solid #334155; }
  h1 { margin: 0 0 6px 0; font-size: 1.4rem; color: #38bdf8; display: flex; align-items: center; gap: 8px; }
  p.subtitle { margin: 0 0 20px 0; font-size: 0.85rem; color: #94a3b8; line-height: 1.4; }
  .field { margin-bottom: 18px; }
  label { display: block; font-weight: 600; font-size: 0.88rem; margin-bottom: 6px; color: #f1f5f9; }
  .hint { font-size: 0.76rem; color: #64748b; margin-bottom: 6px; }
  input[type="text"], select { width: 100%%; padding: 12px 14px; background: #0f172a; border: 1.5px solid #334155; border-radius: 10px; color: #f8fafc; font-size: 0.95rem; font-family: monospace; outline: none; transition: border-color 0.2s; }
  input[type="text"]:focus, select:focus { border-color: #38bdf8; }
  button { width: 100%%; margin-top: 10px; padding: 15px; background: #0284c7; color: #fff; border: none; border-radius: 12px; font-size: 1.05rem; font-weight: 700; cursor: pointer; transition: all 0.2s; box-shadow: 0 4px 14px rgba(2,132,199,0.4); }
  button:hover { background: #0369a1; }
  .badge-free { background: #065f46; color: #34d399; font-size: 0.72rem; padding: 2px 7px; border-radius: 6px; margin-left: 6px; font-weight: 700; }
  .footer { margin-top: 18px; text-align: center; font-size: 0.78rem; color: #64748b; }
</style>
</head>
<body>
<div class="card">
  <h1>✨ Gemini AI Illustrator</h1>
  <p class="subtitle">Enter or paste your API keys below. They will be saved instantly onto your Kindle over local Wi-Fi.</p>
  
  <form method="POST" action="/save">
    <div class="field">
      <label>Google Gemini API Key <span class="badge-free">100%% FREE</span></label>
      <div class="hint">Required for Chapter Brain & Text Analysis (aistudio.google.com)</div>
      <input type="text" name="api_key" value="%s" placeholder="AIzaSy...">
    </div>

    <div class="field">
      <label>Fal.ai API Key</label>
      <div class="hint">For FLUX.1 Schnell ($0.003 / image - ~333 images for $1 from fal.ai)</div>
      <input type="text" name="fal_key" value="%s" placeholder="fal_...">
    </div>

    <div class="field">
      <label>OpenAI API Key</label>
      <div class="hint">For DALL-E 3 (platform.openai.com)</div>
      <input type="text" name="openai_key" value="%s" placeholder="sk-proj-...">
    </div>

    <div class="field">
      <label>Default Image Provider / Model</label>
      <select name="image_model">
        <option value="pollinations-flux" %s>🌸 Pollinations Flux.1 ($0.00 - 100%% Free)</option>
        <option value="fal-flux-schnell" %s>⚡ Fal.ai FLUX.1 Schnell ($0.003 / img)</option>
        <option value="fal-flux-dev" %s>🎨 Fal.ai FLUX.1 Dev ($0.025 / img)</option>
        <option value="gemini-3.1-flash-lite-image" %s>🍌 Google Nano Banana 2 Lite ($0.07 / img)</option>
        <option value="gemini-3.1-flash-image" %s>🍌 Google Nano Banana 2 ($0.10 / img)</option>
        <option value="dall-e-3" %s>🤖 OpenAI DALL-E 3 ($0.04 - $0.08 / img)</option>
      </select>
    </div>

    <div class="field">
      <label>Default Art Style</label>
      <select name="art_style">
        <option value="auto_genre" %s>🧠 Auto (Smart Genre Detection)</option>
        <option value="engraving" %s>🖋️ Victorian Engraving & Ink (Doré / Dürer)</option>
        <option value="comic_noir" %s>📖 Graphic Novel & Comic Noir (Chiaroscuro)</option>
        <option value="woodcut" %s>🪵 Vintage Woodblock & Woodcut</option>
        <option value="charcoal_sketch" %s>✏️ Charcoal & Pencil Drawing</option>
        <option value="cinematic_bw" %s>🎬 Cinematic B&W Still</option>
      </select>
    </div>

    <div class="field" style="display: flex; align-items: center; gap: 10px; margin-top: 14px;">
      <input type="checkbox" name="enable_web_search" value="true" id="web_search" %s style="width: 20px; height: 20px; accent-color: #0284c7;">
      <label for="web_search" style="margin: 0; cursor: pointer; font-size: 0.88rem;">🌐 Enable Google Search Grounding for Characters</label>
    </div>

    <button type="submit">💾 Send & Save to Kindle</button>
  </form>
  <div class="footer">🔒 100%% Private & Local — Direct transfer over home Wi-Fi</div>
</div>
</body>
</html>]],
    gemini_key, fal_key, openai_key,
    cur_img_model == "pollinations-flux" and "selected" or "",
    cur_img_model == "fal-flux-schnell" and "selected" or "",
    cur_img_model == "fal-flux-dev" and "selected" or "",
    cur_img_model == "gemini-3.1-flash-lite-image" and "selected" or "",
    cur_img_model == "gemini-3.1-flash-image" and "selected" or "",
    cur_img_model == "dall-e-3" and "selected" or "",
    cur_art_style == "auto_genre" and "selected" or "",
    cur_art_style == "engraving" and "selected" or "",
    cur_art_style == "comic_noir" and "selected" or "",
    cur_art_style == "woodcut" and "selected" or "",
    cur_art_style == "charcoal_sketch" and "selected" or "",
    cur_art_style == "cinematic_bw" and "selected" or "",
    (settings and settings:get("enable_web_search") == true) and "checked" or ""
)
end

local function buildSuccessHTML()
    return [[<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Saved!</title>
<style>
  * { box-sizing: border-box; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
  body { background: #0f172a; color: #f8fafc; margin: 0; padding: 24px; display: flex; justify-content: center; min-height: 100vh; align-items: center; text-align: center; }
  .card { background: #1e293b; max-width: 440px; padding: 36px 24px; border-radius: 20px; box-shadow: 0 10px 30px rgba(0,0,0,0.5); border: 1px solid #334155; }
  .icon { font-size: 3.5rem; margin-bottom: 12px; }
  h1 { margin: 0 0 10px 0; color: #34d399; font-size: 1.5rem; }
  p { color: #94a3b8; font-size: 0.95rem; line-height: 1.5; margin-bottom: 0; }
</style>
</head>
<body>
<div class="card">
  <div class="icon">✨</div>
  <h1>Settings Saved!</h1>
  <p>Your API keys and configuration have been transferred and saved to your Kindle.<br><br>You can now close this tab and return to reading!</p>
</div>
</body>
</html>]]
end

function QRServer:new(settings)
    local self = setmetatable({}, QRServer)
    self.settings = settings
    self.server_socket = nil
    self.poll_timer = nil
    self.is_running = false
    return self
end

function QRServer:start(on_success_callback, on_close_callback)
    local ip = getLocalIP()
    if not ip then
        UIManager:show(InfoMessage:new{
            text = _("Could not detect Kindle Wi-Fi IP address.\nPlease ensure Kindle is connected to Wi-Fi."),
            timeout = 3.5,
        })
        return
    end

    local ok_sock, socket = pcall(require, "socket")
    if not ok_sock or not socket or not socket.bind then
        UIManager:show(InfoMessage:new{
            text = _("LuaSocket module is unavailable."),
            timeout = 3,
        })
        return
    end

    -- Try ports 8080, 8081, 8082, 8888
    local ports = { 8080, 8081, 8082, 8888 }
    local server = nil
    local bound_port = 8080

    for _, p in ipairs(ports) do
        local s, err = socket.bind("*", p)
        if s then
            server = s
            bound_port = p
            break
        end
    end

    if not server then
        UIManager:show(InfoMessage:new{
            text = _("Failed to start local web server (ports occupied)."),
            timeout = 3,
        })
        return
    end

    server:settimeout(0.01)
    self.server_socket = server
    self.is_running = true

    local pair_url = string.format("http://%s:%d", ip, bound_port)
    local self_ref = self
    local qr_widget = nil

    -- Polling function for incoming HTTP requests
    local function pollLoop()
        if not self_ref.is_running or not self_ref.server_socket then return end

        local client = self_ref.server_socket:accept()
        if client then
            client:settimeout(0.5)
            local req_line = client:receive("*l")
            if req_line then
                local method, path = req_line:match("^(%a+)%s+(%S+)")
                local content_length = 0

                -- Read headers
                while true do
                    local header_line = client:receive("*l")
                    if not header_line or header_line == "" then break end
                    local cl = header_line:match("[Cc]ontent%-[Ll]ength:%s*(%d+)")
                    if cl then content_length = tonumber(cl) or 0 end
                end

                if method == "POST" then
                    local body = ""
                    if content_length > 0 then
                        body = client:receive(content_length) or ""
                    end
                    local params = parseFormBody(body)

                    -- Save settings
                    if self_ref.settings then
                        if params.api_key then self_ref.settings:set("api_key", params.api_key) end
                        if params.fal_key then self_ref.settings:set("fal_key", params.fal_key) end
                        if params.openai_key then self_ref.settings:set("openai_key", params.openai_key) end
                        if params.image_model then self_ref.settings:set("image_model", params.image_model) end
                        if params.art_style then self_ref.settings:set("art_style", params.art_style) end
                        self_ref.settings:set("enable_web_search", params.enable_web_search == "true")
                    end

                    -- Send HTTP 200 Success Response
                    local resp_html = buildSuccessHTML()
                    local resp = string.format(
                        "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=UTF-8\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s",
                        #resp_html, resp_html
                    )
                    client:send(resp)
                    client:close()

                    -- Close QR modal & server
                    self_ref:stop()
                    if qr_widget then
                        UIManager:close(qr_widget)
                    end

                    UIManager:show(InfoMessage:new{
                        text = _("🎉 API Keys & Settings received successfully from Phone!"),
                        timeout = 3.5,
                    })

                    if on_success_callback then
                        on_success_callback()
                    end
                    return
                else
                    -- GET Request: Serve configuration web page
                    local html = buildHTMLPage(self_ref.settings)
                    local resp = string.format(
                        "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=UTF-8\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s",
                        #html, html
                    )
                    client:send(resp)
                    client:close()
                end
            else
                client:close()
            end
        end

        -- Reschedule next poll
        if self_ref.is_running then
            self_ref.poll_timer = UIManager:scheduleIn(0.1, pollLoop)
        end
    end

    -- Start polling loop
    self.poll_timer = UIManager:scheduleIn(0.1, pollLoop)

    -- Display QR Code Modal on Kindle E-Ink screen
    local prompt_text = string.format(_("Scan with phone on same Wi-Fi:\n%s"), pair_url)
    qr_widget = QRMessage:new{
        text = pair_url,
        width = math.min(Device.screen:getWidth(), Device.screen:getHeight()) - 80,
        height = math.min(Device.screen:getWidth(), Device.screen:getHeight()) - 80,
        dismiss_callback = function()
            self_ref:stop()
            if on_close_callback then
                on_close_callback()
            end
        end,
    }
    UIManager:show(qr_widget)
end

function QRServer:stop()
    self.is_running = false
    if self.poll_timer then
        UIManager:unschedule(self.poll_timer)
        self.poll_timer = nil
    end
    if self.server_socket then
        pcall(function() self.server_socket:close() end)
        self.server_socket = nil
    end
end

return QRServer
