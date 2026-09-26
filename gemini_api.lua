--[[--
Universal Multi-Provider AI REST Client for KOReader.
Uses Google Gemini 3.1 Flash Lite for Text Analysis & Scene Extraction.
Supports Multiple Image Backends:
  - Pollinations.ai (FLUX.1 / SDXL - 100% Free, $0.00)
  - Fal.ai (FLUX.1 Schnell $0.003 / Dev $0.025)
  - Google AI Studio (Nano Banana 2 Lite $0.07 / Standard $0.10 / Imagen 4.0)
  - OpenAI (DALL-E 3 / GPT Image $0.04 - $0.08)
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

local function urlEncode(str)
    if not str then return "" end
    str = string.gsub(str, "\n", " ")
    str = string.gsub(str, "([^%w _%%%-%.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    str = string.gsub(str, " ", "%%20")
    return str
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

function API:getGeminiKey()
    local key = self.settings:get("api_key") or ""
    return key:gsub("^%s+", ""):gsub("%s+$", ""):gsub("[\r\n]", "")
end

function API:getFalKey()
    local key = self.settings:get("fal_key") or ""
    return key:gsub("^%s+", ""):gsub("%s+$", ""):gsub("[\r\n]", "")
end

function API:getOpenAIKey()
    local key = self.settings:get("openai_key") or ""
    return key:gsub("^%s+", ""):gsub("%s+$", ""):gsub("[\r\n]", "")
end

function API:getTextModel()
    return self.settings:get("text_model") or "gemini-3.1-flash-lite"
end

function API:getImageModel()
    return self.settings:get("image_model") or "pollinations-flux"
end

function API:getImageDimensions()
    local res_str = self.settings:get("resolution") or "768x1024"
    local w, h = res_str:match("(%d+)x(%d+)")
    return tonumber(w) or 768, tonumber(h) or 1024
end

function API:getTimeout()
    return tonumber(self.settings:get("timeout")) or 30
end

-- Ping / Validate Active Providers
function API:ping()
    local gemini_key = self:getGeminiKey()
    local image_model = self:getImageModel()
    local provider = self.settings:getImageProvider()

    -- 1. Test Gemini Text Brain
    if #gemini_key == 0 then
        return false, "Google Gemini API key is not set. Required for text/chapter analysis."
    end

    local text_model = self:getTextModel()
    local url = string.format(
        "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s",
        text_model, gemini_key
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
    local text_ok = false
    local text_msg = ""
    if handle then
        local raw = handle:read("*a")
        handle:close()
        pcall(function() os.remove(tmp_payload) end)

        if raw and #raw > 0 then
            local resp_body, http_code = raw:match("^(.-)\nHTTP_CODE:(%d%d%d)%s*$")
            if http_code == "200" then
                text_ok = true
                text_msg = string.format("🧠 Text Brain (%s): Connected OK!\n", text_model)
            else
                return false, string.format("Gemini Text API Error (HTTP %s). Check Gemini API key.", tostring(http_code))
            end
        end
    end

    if not text_ok then
        return false, "Gemini Text Brain connection timed out. Check Kindle Wi-Fi."
    end

    -- 2. Verify Image Provider Key status
    local img_msg = ""
    if provider == "pollinations" then
        img_msg = "🌸 Image Engine: Pollinations Flux.1 ($0.00 Free - Ready!)"
    elseif provider == "fal" then
        local fal_key = self:getFalKey()
        if #fal_key > 0 then
            img_msg = string.format("⚡ Image Engine: Fal.ai FLUX (%d chars key - Ready!)", #fal_key)
        else
            img_msg = "⚠️ Image Engine: Fal.ai selected, but Fal API key is not set."
        end
    elseif provider == "openai" then
        local openai_key = self:getOpenAIKey()
        if #openai_key > 0 then
            img_msg = string.format("🤖 Image Engine: OpenAI DALL-E 3 (%d chars key - Ready!)", #openai_key)
        else
            img_msg = "⚠️ Image Engine: OpenAI selected, but OpenAI API key is not set."
        end
    else
        img_msg = string.format("🍌 Image Engine: Google %s (Linked Billing Required)", image_model)
    end

    return true, text_msg .. img_msg
end

-- Analyze Chapter Text via Google Gemini 3.1 Flash Lite (Free Text Brain)
function API:analyzeChapter(chapter_text, system_instruction)
    local key = self:getGeminiKey()
    if #key == 0 then
        return nil, "Gemini API key is not configured. (Required for reading chapters)"
    end

    local model = self:getTextModel()
    local url = string.format(
        "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s",
        model, key
    )

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
        return nil, "No text content returned in Gemini candidate."
    end

    text_content = text_content:gsub("^```json%s*", ""):gsub("^```%s*", ""):gsub("%s*```$", "")

    local scenes = decodeJSON(text_content)
    if type(scenes) == "table" and #scenes > 0 then
        return scenes
    elseif type(scenes) == "table" and scenes.scenes and #scenes.scenes > 0 then
        return scenes.scenes
    end

    return nil, "Could not parse scenes array from Gemini response."
end

-- Extract Cast of Characters from Text (using Google Gemini 3.1 Flash with optional Web Search Grounding)
function API:extractCharacters(text_to_analyze, system_instruction, enable_web_search)
    local key = self:getGeminiKey()
    if #key == 0 then
        return nil, "Gemini API key is not configured."
    end

    local model = self:getTextModel()
    local url = string.format(
        "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s",
        model, key
    )

    local truncated_text = text_to_analyze:sub(1, 2000000)

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
            temperature = 0.3,
        }
    }

    -- Add Google Search Grounding if enabled by user
    if enable_web_search then
        payload.tools = {
            {
                google_search = {}
            }
        }
        -- Note: When tools/google_search is present, response_mime_type is omitted to prevent API 400 error
    else
        payload.generationConfig.response_mime_type = "application/json"
    end

    local body_json = encodeJSON(payload)
    local tmp_payload = "/tmp/gemini_characters.json"
    local f = io.open(tmp_payload, "w")
    if not f then
        tmp_payload = "gemini_characters.json"
        f = io.open(tmp_payload, "w")
    end
    if f then
        f:write(body_json)
        f:close()
    end

    local timeout = math.max(self:getTimeout(), 60)
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
        return nil, "Empty response or timeout during character extraction."
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
        return nil, "No character content returned in Gemini candidate."
    end

    text_content = text_content:gsub("^%s*```json%s*", ""):gsub("^%s*```%s*", ""):gsub("%s*```%s*$", "")
    local json_arr = text_content:match("(%b[])") or text_content:match("(%b{})") or text_content

    local characters = decodeJSON(json_arr)
    if type(characters) == "table" and #characters > 0 then
        return characters
    elseif type(characters) == "table" and characters.characters and #characters.characters > 0 then
        return characters.characters
    end

    return nil, "Could not parse characters array from Gemini response."
end

-- Extract Cast of Characters by Searching the Internet directly via Google Search Grounding
function API:extractCharactersFromInternet(book_info, system_instruction)
    local key = self:getGeminiKey()
    if #key == 0 then
        return nil, "Gemini API key is not configured."
    end

    local model = self:getTextModel()
    local url = string.format(
        "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s",
        model, key
    )

    local title = (book_info and book_info.title) or "Book"
    local author = (book_info and book_info.author) or "Author"
    local user_prompt = string.format("Search the web for the complete cast of characters in the book '%s' by %s. Provide canonical character profiles and visual descriptions for portrait art generation.", title, author)

    local payload = {
        system_instruction = {
            parts = { { text = system_instruction } }
        },
        contents = {
            {
                role = "user",
                parts = { { text = user_prompt } }
            }
        },
        tools = {
            {
                google_search = {}
            }
        },
        generationConfig = {
            temperature = 0.3,
        }
    }

    local body_json = encodeJSON(payload)
    local tmp_payload = "/tmp/gemini_char_search.json"
    local f = io.open(tmp_payload, "w")
    if not f then
        tmp_payload = "gemini_char_search.json"
        f = io.open(tmp_payload, "w")
    end
    if f then
        f:write(body_json)
        f:close()
    end

    local timeout = math.max(self:getTimeout(), 60)
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
        return nil, "Empty response or timeout during internet character search."
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
        return nil, "No character content returned in Gemini search candidate."
    end

    text_content = text_content:gsub("^%s*```json%s*", ""):gsub("^%s*```%s*", ""):gsub("%s*```%s*$", "")
    local json_arr = text_content:match("(%b[])") or text_content:match("(%b{})") or text_content

    local characters = decodeJSON(json_arr)
    if type(characters) == "table" and #characters > 0 then
        return characters
    elseif type(characters) == "table" and characters.characters and #characters.characters > 0 then
        return characters.characters
    end

    return nil, "Could not parse characters array from Gemini web search response."
end

-- Generate Image: Dispatches to chosen provider (Pollinations, Fal.ai, Google, OpenAI)
function API:generateImage(visual_prompt, output_filepath)
    local provider = self.settings:getImageProvider()
    local model = self:getImageModel()
    local timeout = math.max(self:getTimeout(), 35)
    local width, height = self:getImageDimensions()

    -- Ensure output directory exists
    local out_dir = output_filepath:match("^(.*)[/\\]")
    if out_dir and #out_dir > 0 then
        pcall(function() os.execute(string.format('mkdir -p "%s"', out_dir)) end)
    end

    -- ==========================================================
    -- 1. Pollinations.ai (100% Free Flux.1 / SDXL, No Key Needed)
    -- ==========================================================
    if provider == "pollinations" or model == "pollinations-flux" then
        local seed = (os.time() % 100000) + math.random(1, 999)
        local enc_prompt = urlEncode(visual_prompt)
        local poll_url = string.format(
            "https://image.pollinations.ai/prompt/%s?width=%d&height=%d&model=flux&nologo=true&seed=%d",
            enc_prompt, width, height, seed
        )

        local curl_cmd = string.format(
            'curl -s -k -m %d -L "%s" -o "%s" -w "\\nHTTP_CODE:%%{http_code}" 2>/dev/null',
            timeout, poll_url, output_filepath
        )

        local handle = io.popen(curl_cmd)
        if handle then
            local raw = handle:read("*a")
            handle:close()

            local http_code = raw:match("HTTP_CODE:(%d%d%d)%s*$")
            if http_code == "200" then
                local check_f = io.open(output_filepath, "rb")
                if check_f then
                    local sz = check_f:seek("end")
                    check_f:close()
                    if sz and sz > 2000 then
                        return output_filepath
                    end
                end
            end
        end
        return nil, "Pollinations Free API failed to deliver image. Check Wi-Fi."
    end

    -- ==========================================================
    -- 2. Fal.ai (FLUX.1 [schnell] $0.003 / [dev] $0.025)
    -- ==========================================================
    if provider == "fal" or model:match("^fal%-flux") then
        local fal_key = self:getFalKey()
        if #fal_key == 0 then
            return nil, "Fal.ai API key is not set. Please add key in Settings."
        end

        local fal_endpoint = (model == "fal-flux-dev") and "https://fal.run/fal-ai/flux/dev" or "https://fal.run/fal-ai/flux/schnell"
        local payload = {
            prompt = visual_prompt,
            image_size = {
                width = width,
                height = height,
            },
            num_images = 1,
            enable_safety_checker = false,
        }

        local tmp_payload = "/tmp/fal_payload.json"
        local f = io.open(tmp_payload, "w")
        if not f then tmp_payload = "fal_payload.json"; f = io.open(tmp_payload, "w") end
        if f then f:write(encodeJSON(payload)); f:close() end

        local curl_cmd = string.format(
            'curl -s -k -m %d -X POST -H "Authorization: Key %s" -H "Content-Type: application/json" -d @%s "%s" -w "\\nHTTP_CODE:%%{http_code}" 2>/dev/null',
            timeout, fal_key, tmp_payload, fal_endpoint
        )

        local handle = io.popen(curl_cmd)
        if not handle then
            pcall(function() os.remove(tmp_payload) end)
            return nil, "Failed to launch Fal.ai curl."
        end

        local raw = handle:read("*a")
        handle:close()
        pcall(function() os.remove(tmp_payload) end)

        local resp_body, http_code = raw:match("^(.-)\nHTTP_CODE:(%d%d%d)%s*$")
        if http_code ~= "200" then
            return nil, string.format("Fal.ai Error (HTTP %s): %s", tostring(http_code), tostring(resp_body):sub(1, 120))
        end

        local decoded = decodeJSON(resp_body)
        local img_url = decoded and decoded.images and decoded.images[1] and decoded.images[1].url
        if not img_url then
            return nil, "No image URL returned by Fal.ai."
        end

        -- Download image from Fal media URL
        local dl_cmd = string.format('curl -s -k -m 20 -L "%s" -o "%s" 2>/dev/null', img_url, output_filepath)
        os.execute(dl_cmd)

        local check_f = io.open(output_filepath, "rb")
        if check_f then
            local sz = check_f:seek("end")
            check_f:close()
            if sz and sz > 2000 then
                return output_filepath
            end
        end
        return nil, "Failed to download generated image from Fal.ai."
    end

    -- ==========================================================
    -- 3. OpenAI (DALL-E 3 / GPT Image)
    -- ==========================================================
    if provider == "openai" or model == "dall-e-3" then
        local openai_key = self:getOpenAIKey()
        if #openai_key == 0 then
            return nil, "OpenAI API key is not set. Please add key in Settings."
        end

        local payload = {
            model = "dall-e-3",
            prompt = visual_prompt,
            n = 1,
            size = "1024x1792", -- Vertical portrait mode for Kindle
            response_format = "b64_json",
        }

        local tmp_payload = "/tmp/openai_payload.json"
        local f = io.open(tmp_payload, "w")
        if not f then tmp_payload = "openai_payload.json"; f = io.open(tmp_payload, "w") end
        if f then f:write(encodeJSON(payload)); f:close() end

        local curl_cmd = string.format(
            'curl -s -k -m %d -X POST -H "Authorization: Bearer %s" -H "Content-Type: application/json" -d @%s "https://api.openai.com/v1/images/generations" -w "\\nHTTP_CODE:%%{http_code}" 2>/dev/null',
            timeout, openai_key, tmp_payload
        )

        local handle = io.popen(curl_cmd)
        if not handle then
            pcall(function() os.remove(tmp_payload) end)
            return nil, "Failed to launch OpenAI curl."
        end

        local raw = handle:read("*a")
        handle:close()
        pcall(function() os.remove(tmp_payload) end)

        local resp_body, http_code = raw:match("^(.-)\nHTTP_CODE:(%d%d%d)%s*$")
        if http_code ~= "200" then
            return nil, string.format("OpenAI Error (HTTP %s): %s", tostring(http_code), tostring(resp_body):sub(1, 120))
        end

        local decoded = decodeJSON(resp_body)
        local b64_data = decoded and decoded.data and decoded.data[1] and decoded.data[1].b64_json
        if not b64_data then
            return nil, "No base64 data returned by OpenAI."
        end

        local tmp_b64 = "/tmp/openai_img.b64"
        local fb = io.open(tmp_b64, "w")
        if fb then fb:write(b64_data); fb:close() end

        local decode_cmd = string.format('base64 -d "%s" > "%s" 2>/dev/null', tmp_b64, output_filepath)
        os.execute(decode_cmd)
        pcall(function() os.remove(tmp_b64) end)

        local check_f = io.open(output_filepath, "rb")
        if check_f then
            local sz = check_f:seek("end")
            check_f:close()
            if sz and sz > 2000 then return output_filepath end
        end

        local binary_bytes = decodeBase64(b64_data)
        if binary_bytes and #binary_bytes > 2000 then
            local out_f = io.open(output_filepath, "wb")
            if out_f then out_f:write(binary_bytes); out_f:close(); return output_filepath end
        end

        return nil, "Failed to decode OpenAI image."
    end

    -- ==========================================================
    -- 4. Google Gemini & Imagen API (Nano Banana 2 Lite / Standard / Pro)
    -- ==========================================================
    local gemini_key = self:getGeminiKey()
    if #gemini_key == 0 then
        return nil, "Google Gemini API key is not configured."
    end

    local tmp_payload = "/tmp/gemini_gen_img.json"
    local tmp_b64 = "/tmp/gemini_img.b64"
    local url = ""
    local payload = {}

    local portrait_prompt = "Vertical portrait orientation (3:4 aspect ratio, vertical composition, taller than wide). " .. visual_prompt

    if model:match("^imagen") then
        url = string.format("https://generativelanguage.googleapis.com/v1beta/models/%s:predict?key=%s", model, gemini_key)
        payload = {
            instances = {
                { prompt = portrait_prompt }
            },
            parameters = {
                sampleCount = 1,
                aspectRatio = "3:4",
                outputMimeType = "image/png"
            }
        }
    else
        -- Native Gemini Multimodal Image Generation
        local gemini_model_id = model
        if gemini_model_id == "gemini-3.1-flash-lite-image" then
            gemini_model_id = "gemini-2.5-flash-image"
        end

        url = string.format("https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent?key=%s", gemini_model_id, gemini_key)
        payload = {
            contents = {
                {
                    role = "user",
                    parts = {
                        { text = portrait_prompt }
                    }
                }
            },
            generationConfig = {
                responseModalities = { "TEXT", "IMAGE" }
            }
        }
    end

    local body_json = encodeJSON(payload)
    local f = io.open(tmp_payload, "w")
    if not f then tmp_payload = "gemini_gen_img.json"; f = io.open(tmp_payload, "w") end
    if f then f:write(body_json); f:close() end

    local curl_cmd = string.format(
        'curl -s -k -m %d -X POST -H "x-goog-api-key: %s" -H "Content-Type: application/json" -d @%s "%s" -w "\\nHTTP_CODE:%%{http_code}" 2>/dev/null',
        timeout, gemini_key, tmp_payload, url
    )

    local handle = io.popen(curl_cmd)
    if not handle then
        pcall(function() os.remove(tmp_payload) end)
        return nil, "Failed to launch Google curl."
    end

    local raw = handle:read("*a")
    handle:close()
    pcall(function() os.remove(tmp_payload) end)

    if not raw or #raw == 0 then
        return nil, "Empty response or timeout during Google image generation."
    end

    local resp_body, http_code = raw:match("^(.-)\nHTTP_CODE:(%d%d%d)%s*$")
    if http_code ~= "200" then
        return nil, string.format("Google Image API Error (HTTP %s):\n%s\n\n(Tip: Switch to '🌸 Pollinations Flux.1' in Settings for 100%% free unlimited images)", tostring(http_code), tostring(resp_body):sub(1, 140))
    end

    local decoded = decodeJSON(resp_body)
    if not decoded then
        return nil, "Invalid JSON from Google Image API."
    end

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
            elseif p.inline_data and p.inline_data.data then
                b64_data = p.inline_data.data
                break
            end
        end
    end

    if not b64_data or #b64_data == 0 then
        return nil, "No image bytes in Google response (Safety filter or quota)."
    end

    local fb = io.open(tmp_b64, "w")
    if fb then fb:write(b64_data); fb:close() end

    local decode_cmd = string.format('base64 -d "%s" > "%s" 2>/dev/null', tmp_b64, output_filepath)
    os.execute(decode_cmd)
    pcall(function() os.remove(tmp_b64) end)

    local check_f = io.open(output_filepath, "rb")
    if check_f then
        local sz = check_f:seek("end")
        check_f:close()
        if sz and sz > 1500 then
            return output_filepath
        end
    end

    local binary_bytes = decodeBase64(b64_data)
    if binary_bytes and #binary_bytes > 1500 then
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
