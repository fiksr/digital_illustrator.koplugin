--[[--
Google Gemini & Imagen REST API Client for KOReader.
Supports 2026 Gemini text models (3.1 Flash Preview, 3.8 Flash) and Image models.
Handles structured JSON chapter analysis and base64 image generation for E-Ink.
--]]--

local logger = require("logger")

local API = {}
API.__index = API

-- Fast JSON module loader
local json = nil
local ok, mod = pcall(require, "rapidjson")
if ok and mod and mod.decode then
    json = mod
else
    ok, mod = pcall(require, "json")
    if ok and mod and mod.decode then
        json = mod
    end
end

local function encodeJSON(tbl)
    if json and json.encode then
        local ok_enc, res = pcall(json.encode, tbl)
        if ok_enc and res then return res end
    end
    return "{}"
end

local function decodeJSON(str)
    if not str or #str == 0 then return nil end
    if json and json.decode then
        local ok_dec, res = pcall(json.decode, str)
        if ok_dec then return res end
    end
    return nil
end

-- Fast pure Lua Base64 decoder fallback
local b64_chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function decodeBase64(data)
    data = string.gsub(data, '[^'..b64_chars..'=]', '')
    return (data:gsub('..?', function(cc)
        if #cc < 2 then return '' end
        local c = 0
        for i = 1, #cc do
            local ch = cc:sub(i, i)
            local idx = b64_chars:find(ch, 1, true)
            if idx then
                c = c * 64 + (idx - 1)
            elseif ch == '=' then
                c = c * 64
            end
        end
        return string.char(bit.band(bit.rshift(c, 16), 255), bit.band(bit.rshift(c, 8), 255), bit.band(c, 255))
    end))
end

function API:new(settings)
    local self = setmetatable({}, API)
    self.settings = settings
    return self
end

function API:getKey()
    local key = self.settings:get("api_key") or ""
    return key:gsub("^%s+", ""):gsub("%s+$", ""):gsub("[\r\n]", "")
end

function API:getTextModel()
    return self.settings:get("text_model") or "gemini-3.1-flash-preview"
end

function API:getImageModel()
    return self.settings:get("image_model") or "gemini-3.1-flash-image"
end

function API:getTimeout()
    return tonumber(self.settings:get("timeout")) or 25
end

-- Ping / Validate API Key
function API:ping()
    local key = self:getKey()
    if #key == 0 then
        return false, "Gemini API key is not set. Please enter your key in Settings or import from /mnt/us/gemini_token.txt."
    end

    local model = self:getTextModel()
    local url = string.format(
        "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s",
        model, key
    )

    local payload = {
        contents = {
            {
                role = "user",
                parts = { { text = "Ping. Answer with 'OK'." } }
            }
        }
    }

    local body_json = encodeJSON(payload)
    local tmp_payload = "/tmp/gemini_ping.json"
    local f = io.open(tmp_payload, "w")
    if not f then
        tmp_payload = "gemini_ping.json"
        f = io.open(tmp_payload, "w")
    end
    if f then
        f:write(body_json)
        f:close()
    end

    local curl_cmd = string.format(
        'curl -s -k -m 12 -X POST -H "Content-Type: application/json" -d @%s "%s" -w "\\nHTTP_CODE:%%{http_code}" 2>/dev/null',
        tmp_payload, url
    )

    local handle = io.popen(curl_cmd)
    if handle then
        local raw = handle:read("*a")
        handle:close()
        pcall(function() os.remove(tmp_payload) end)

        if raw and #raw > 0 then
            local resp_body, http_code = raw:match("^(.-)\nHTTP_CODE:(%d%d%d)%s*$")
            if http_code == "200" then
                return true, string.format("Connected successfully to Google Gemini! (Model: %s)", model)
            elseif http_code == "400" or http_code == "403" then
                return false, "API Key Error: Invalid key or permissions. Check Google AI Studio."
            elseif http_code == "404" then
                return false, string.format("Model '%s' not found. Try Gemini 3.1 Flash Preview in settings.", model)
            else
                return false, string.format("Connection error (HTTP %s). Check Wi-Fi.", tostring(http_code))
            end
        end
    end

    pcall(function() os.remove(tmp_payload) end)
    return false, "Connection timed out. Check Kindle Wi-Fi connection."
end

-- Analyze Chapter Text and Return Structured Scene Suggestions
function API:analyzeChapter(chapter_text, system_instruction)
    local key = self:getKey()
    if #key == 0 then
        return nil, "Gemini API key is not configured."
    end

    local model = self:getTextModel()
    local url = string.format(
        "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s",
        model, key
    )

    -- Cap text to ~60,000 characters for quick network transfer while preserving chapter essence
    local truncated_text = chapter_text:sub(1, 60000)

    local payload = {
        system_instruction = {
            parts = { { text = system_instruction } }
        },
        contents = {
            {
                role = "user",
                parts = { { text = truncated_text } }
            }
        },
        generationConfig = {
            response_mime_type = "application/json",
            temperature = 0.5,
        }
    }

    local body_json = encodeJSON(payload)
    local tmp_payload = "/tmp/gemini_analyze.json"
    local f = io.open(tmp_payload, "w")
    if not f then
        tmp_payload = "gemini_analyze.json"
        f = io.open(tmp_payload, "w")
    end
    if f then
        f:write(body_json)
        f:close()
    end

    local timeout = self:getTimeout()
    local curl_cmd = string.format(
        'curl -s -k -m %d -X POST -H "Content-Type: application/json" -d @%s "%s" -w "\\nHTTP_CODE:%%{http_code}" 2>/dev/null',
        timeout, tmp_payload, url
    )

    local handle = io.popen(curl_cmd)
    if not handle then
        pcall(function() os.remove(tmp_payload) end)
        return nil, "Failed to launch curl process."
    end

    local raw = handle:read("*a")
    handle:close()
    pcall(function() os.remove(tmp_payload) end)

    if not raw or #raw == 0 then
        return nil, "Empty response or timeout during chapter analysis."
    end

    local resp_body, http_code = raw:match("^(.-)\nHTTP_CODE:(%d%d%d)%s*$")
    if http_code ~= "200" then
        return nil, string.format("Gemini API Error (HTTP %s): %s", tostring(http_code), tostring(resp_body):sub(1, 150))
    end

    local decoded = decodeJSON(resp_body)
    if not decoded or not decoded.candidates or not decoded.candidates[1] then
        return nil, "Invalid JSON structure received from Gemini."
    end

    local candidate = decoded.candidates[1]
    local text_content = candidate.content and candidate.content.parts and candidate.content.parts[1] and candidate.content.parts[1].text

    if not text_content then
        return nil, "No text parts returned in candidate."
    end

    -- Clean any markdown formatting if present
    text_content = text_content:gsub("^```json%s*", ""):gsub("^```%s*", ""):gsub("%s*```$", "")

    local scenes = decodeJSON(text_content)
    if type(scenes) == "table" and #scenes > 0 then
        return scenes
    elseif type(scenes) == "table" and scenes.scenes and #scenes.scenes > 0 then
        return scenes.scenes
    end

    return nil, "Could not parse scenes array from Gemini response."
end

-- Generate Image from Visual Prompt
function API:generateImage(visual_prompt, output_filepath)
    local key = self:getKey()
    if #key == 0 then
        return nil, "Gemini API key is not configured."
    end

    local model = self:getImageModel()
    local timeout = math.max(self:getTimeout(), 30)

    -- Ensure output directory exists
    local out_dir = output_filepath:match("^(.*)[/\\]")
    if out_dir and #out_dir > 0 then
        pcall(function() os.execute(string.format('mkdir -p "%s"', out_dir)) end)
    end

    local tmp_payload = "/tmp/gemini_gen_img.json"
    local tmp_b64 = "/tmp/gemini_img.b64"
    local url = ""
    local payload = {}

    if model:match("^imagen") then
        -- Google Imagen 3.0 / 4.0 predict endpoint
        url = string.format("https://generativelanguage.googleapis.com/v1beta/models/%s:predict?key=%s", model, key)
        payload = {
            instances = {
                { prompt = visual_prompt }
            },
            parameters = {
                sampleCount = 1,
                aspectRatio = "3:4",
                outputMimeType = "image/png"
            }
        }
    else
        -- Gemini Native / Nano Banana / Interactions endpoint
        url = string.format("https://generativelanguage.googleapis.com/v1beta/interactions?key=%s", key)
        payload = {
            model = model,
            input = {
                {
                    type = "text",
                    text = visual_prompt
                }
            }
        }
    end

    local body_json = encodeJSON(payload)
    local f = io.open(tmp_payload, "w")
    if not f then
        tmp_payload = "gemini_gen_img.json"
        f = io.open(tmp_payload, "w")
    end
    if f then
        f:write(body_json)
        f:close()
    end

    local curl_cmd = string.format(
        'curl -s -k -m %d -X POST -H "Content-Type: application/json" -d @%s "%s" -w "\\nHTTP_CODE:%%{http_code}" 2>/dev/null',
        timeout, tmp_payload, url
    )

    local handle = io.popen(curl_cmd)
    if not handle then
        pcall(function() os.remove(tmp_payload) end)
        return nil, "Failed to launch curl process."
    end

    local raw = handle:read("*a")
    handle:close()
    pcall(function() os.remove(tmp_payload) end)

    if not raw or #raw == 0 then
        return nil, "Empty response or timeout during image generation."
    end

    local resp_body, http_code = raw:match("^(.-)\nHTTP_CODE:(%d%d%d)%s*$")
    if http_code ~= "200" then
        return nil, string.format("Image API Error (HTTP %s): %s", tostring(http_code), tostring(resp_body):sub(1, 150))
    end

    local decoded = decodeJSON(resp_body)
    if not decoded then
        return nil, "Invalid JSON from Image API."
    end

    -- Extract base64 image payload from various Google response schemas
    local b64_data = nil
    if decoded.predictions and decoded.predictions[1] and decoded.predictions[1].bytesBase64Encoded then
        b64_data = decoded.predictions[1].bytesBase64Encoded
    elseif decoded.output_image then
        b64_data = decoded.output_image
    elseif decoded.interaction and decoded.interaction.output_image then
        b64_data = decoded.interaction.output_image
    elseif decoded.generatedImages and decoded.generatedImages[1] and decoded.generatedImages[1].image and decoded.generatedImages[1].image.imageBytes then
        b64_data = decoded.generatedImages[1].image.imageBytes
    elseif decoded.candidates and decoded.candidates[1] and decoded.candidates[1].content and decoded.candidates[1].content.parts then
        for _, p in ipairs(decoded.candidates[1].content.parts) do
            if p.inlineData and p.inlineData.data then
                b64_data = p.inlineData.data
                break
            end
        end
    end

    if not b64_data or #b64_data == 0 then
        return nil, "No image bytes found in API response. Prompt might have violated safety filters."
    end

    -- Write base64 to temp file and decode via fast Linux base64 command
    local fb = io.open(tmp_b64, "w")
    if not fb then
        tmp_b64 = "gemini_img.b64"
        fb = io.open(tmp_b64, "w")
    end
    if fb then
        fb:write(b64_data)
        fb:close()
    end

    -- 1. Try native Linux base64 command on Kindle
    local decode_cmd = string.format('base64 -d "%s" > "%s" 2>/dev/null', tmp_b64, output_filepath)
    local ret = os.execute(decode_cmd)
    pcall(function() os.remove(tmp_b64) end)

    -- 2. Verify file written and size > 1KB
    local check_f = io.open(output_filepath, "rb")
    if check_f then
        local sz = check_f:seek("end")
        check_f:close()
        if sz and sz > 1000 then
            return output_filepath
        end
    end

    -- 3. Fallback to pure Lua Base64 decoder if OS command failed
    local binary_bytes = decodeBase64(b64_data)
    if binary_bytes and #binary_bytes > 1000 then
        local out_f = io.open(output_filepath, "wb")
        if out_f then
            out_f:write(binary_bytes)
            out_f:close()
            return output_filepath
        end
    end

    return nil, "Failed to write decoded image to disk."
end

return API
