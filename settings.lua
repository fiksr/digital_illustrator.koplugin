--[[--
Settings and persistence manager for Gemini AI Book Illustrator plugin.
Supports multiple image providers: Google Gemini/Imagen, Pollinations (Free Flux), Fal.ai (Flux Schnell/Dev), and OpenAI (DALL-E 3).
--]]--

local Settings = {}
Settings.__index = Settings

local DEFAULT_SETTINGS = {
    api_key = "",                        -- Google Gemini API Key (for Text Brain & Google Imagen)
    fal_key = "",                        -- Fal.ai API Key (for ultra-cheap Flux.1)
    openai_key = "",                     -- OpenAI API Key (for DALL-E 3)
    text_model = "gemini-3.1-flash-lite", -- 500 RPD high quota (Free Text Brain)
    image_model = "pollinations-flux",    -- Default to Free Pollinations Flux or Nano Banana
    resolution = "768x1024",              -- Fast, responsive for Kindle Wi-Fi & 3:4 E-Ink
    art_style = "auto_genre",             -- Automatically adapt to book genre
    save_dir = "/mnt/us/koreader/bookart",
    timeout = 30,
    auto_contrast_prompt = true,
    enable_web_search = false,           -- Optional Google Search Grounding for canonical character lookup
}

Settings.TEXT_MODELS = {
    { id = "gemini-3.1-flash-lite", name = "Gemini 3.1 Flash Lite (500 RPD - 100% Free)", desc = "High rate limits, ultra-fast chapter analysis" },
    { id = "gemini-3.8-flash",      name = "Gemini 3.8 Flash (2026 Flagship)",           desc = "Deep contextual understanding" },
    { id = "gemini-2.5-flash",      name = "Gemini 2.5 Flash",                           desc = "Stable high-speed model" },
    { id = "gemini-2.0-flash",      name = "Gemini 2.0 Flash",                           desc = "Fast legacy flash model" },
    { id = "gemini-2.5-pro",        name = "Gemini 2.5 Pro",                             desc = "Maximum literary reasoning" },
}

Settings.IMAGE_MODELS = {
    -- 1. 100% Free Open API
    {
        id = "pollinations-flux",
        provider = "pollinations",
        name = "🌸 Pollinations Flux.1 ($0.00 - 100% Free)",
        desc = "No API key needed, unlimited, powered by Flux.1 engine"
    },

    -- 2. Fal.ai Ultra-Cheap & Fast
    {
        id = "fal-flux-schnell",
        provider = "fal",
        name = "⚡ Fal.ai FLUX.1 Schnell",
        desc = "Ultra-fast ~1s, low cost per image (requires Fal key)"
    },
    {
        id = "fal-flux-dev",
        provider = "fal",
        name = "🎨 Fal.ai FLUX.1 Dev",
        desc = "Maximum photorealism & detail (requires Fal key)"
    },

    -- 3. Google Nano Banana Image Models
    {
        id = "gemini-3.1-flash-lite-image",
        provider = "google",
        name = "🍌 Nano Banana 2 Lite",
        desc = "Google Gemini multimodal fast E-Ink portrait engine"
    },
    {
        id = "gemini-3.1-flash-image",
        provider = "google",
        name = "🍌 Nano Banana 2",
        desc = "Google Gemini multimodal standard portrait generation"
    },
    {
        id = "gemini-3-pro-image",
        provider = "google",
        name = "🍌 Nano Banana Pro",
        desc = "Google Gemini multimodal maximum artistic detail"
    },

    -- 4. OpenAI
    {
        id = "dall-e-3",
        provider = "openai",
        name = "🤖 OpenAI DALL-E 3",
        desc = "Standard vertical DALL-E 3 quality (requires OpenAI key)"
    },
}

Settings.RESOLUTIONS = {
    { id = "768x1024",  name = "Fast (768 x 1024)",          desc = "Quick download, responsive on Kindle e-ink" },
    { id = "896x1152",  name = "Balanced (896 x 1152)",      desc = "Great balance of speed & crispness" },
    { id = "1024x1365", name = "Sharp HD (1024 x 1365)",     desc = "High detail, 3:4 aspect ratio" },
    { id = "1272x1696", name = "Native 300 PPI (1272x1696)", desc = "Pixel-perfect for Paperwhite 12th gen" },
}

Settings.ART_STYLES = {
    { id = "auto_genre",      name = "🧠 Auto (Smart Genre Detection)",  desc = "Adapts to Sci-Fi, Fantasy, Noir, Romance, etc." },
    { id = "engraving",       name = "🖋️ Victorian Engraving & Ink",     desc = "Gustave Doré / Dürer style, crisp black lines" },
    { id = "comic_noir",      name = "📖 Graphic Novel & Comic Noir",    desc = "High contrast chiaroscuro, heavy ink shadows" },
    { id = "woodcut",         name = "🪵 Vintage Woodblock & Woodcut",   desc = "Folkloric, bold medieval woodcut print" },
    { id = "charcoal_sketch", name = "✏️ Charcoal & Pencil Drawing",     desc = "Soft tonal shading, realistic portraiture" },
    { id = "cinematic_bw",    name = "🎬 Cinematic B&W Still",           desc = "Film photography with atmospheric lighting" },
}

function Settings:new()
    local self = setmetatable({}, Settings)
    self.data = {}
    self:load()
    return self
end

function Settings:load()
    local loaded = nil
    if G_reader_settings and G_reader_settings.readSetting then
        loaded = G_reader_settings:readSetting("gemini_illustrator")
    end

    self.data = {}
    for k, v in pairs(DEFAULT_SETTINGS) do
        self.data[k] = v
    end

    if type(loaded) == "table" then
        for k, v in pairs(loaded) do
            self.data[k] = v
        end
    end

    -- Sanitize API Keys
    if type(self.data.api_key) == "string" then
        self.data.api_key = self.data.api_key:gsub("^%s+", ""):gsub("%s+$", ""):gsub("[\r\n]", "")
    end
    if type(self.data.fal_key) == "string" then
        self.data.fal_key = self.data.fal_key:gsub("^%s+", ""):gsub("%s+$", ""):gsub("[\r\n]", "")
    end
    if type(self.data.openai_key) == "string" then
        self.data.openai_key = self.data.openai_key:gsub("^%s+", ""):gsub("%s+$", ""):gsub("[\r\n]", "")
    end
    self.data.timeout = tonumber(self.data.timeout) or 30
end

function Settings:save()
    if G_reader_settings and G_reader_settings.saveSetting then
        G_reader_settings:saveSetting("gemini_illustrator", self.data)
    end
end

function Settings:get(key)
    return self.data[key]
end

function Settings:set(key, value)
    if (key == "api_key" or key == "fal_key" or key == "openai_key") and type(value) == "string" then
        value = value:gsub("^%s+", ""):gsub("%s+$", ""):gsub("[\r\n]", "")
    elseif key == "timeout" then
        value = tonumber(value) or 30
    end
    self.data[key] = value
    self:save()
end

-- Resolve provider for current image model
function Settings:getImageProvider()
    local model_id = self:get("image_model") or "pollinations-flux"
    for _, item in ipairs(Settings.IMAGE_MODELS) do
        if item.id == model_id then
            return item.provider or "google"
        end
    end
    if model_id:match("^pollinations") then return "pollinations" end
    if model_id:match("^fal") then return "fal" end
    if model_id:match("^dall") then return "openai" end
    return "google"
end

-- Import token helper for any provider
function Settings:importTokenFromFile(token_type, filename)
    filename = filename or (token_type == "fal" and "fal_token.txt" or (token_type == "openai" and "openai_token.txt" or "gemini_token.txt"))
    local candidate_paths = {
        "/mnt/us/" .. filename,
        "/mnt/us/" .. filename .. ".txt",
        "/mnt/us/" .. filename:gsub("%.txt$", ""),
        "/mnt/us/koreader/" .. filename,
        "/mnt/base-us/" .. filename,
        filename,
        filename .. ".txt",
    }

    local found_file = nil
    local found_path = nil

    for _, path in ipairs(candidate_paths) do
        local f = io.open(path, "r")
        if f then
            found_file = f
            found_path = path
            break
        end
    end

    if not found_file then
        return false, string.format("File not found: /mnt/us/%s\n(Place file on Kindle root storage)", filename)
    end

    local token = found_file:read("*a")
    found_file:close()

    if not token then
        return false, "Could not read token file."
    end

    token = token:gsub("^%s+", ""):gsub("%s+$", ""):gsub("[\r\n]", "")

    if #token < 8 then
        return false, "Key is too short or empty (length: " .. #token .. ")."
    end

    local setting_key = (token_type == "fal") and "fal_key" or ((token_type == "openai") and "openai_key" or "api_key")
    self:set(setting_key, token)

    return true, string.format("Key imported successfully! (%d chars from %s)", #token, found_path)
end

-- Import key from any arbitrary path chosen by the user (with provider auto-detection)
function Settings:importKeyFromArbitraryFile(filepath, target_provider)
    if not filepath then return false, "No file path provided." end

    local f = io.open(filepath, "r")
    if not f then
        return false, "Could not open file: " .. tostring(filepath)
    end

    local token = f:read("*a")
    f:close()

    if not token or #token == 0 then
        return false, "The selected file is empty."
    end

    token = token:gsub("^%s+", ""):gsub("%s+$", ""):gsub("[\r\n]", "")

    if #token < 8 then
        return false, "Key inside file is too short (length: " .. #token .. ")."
    end

    local basename = filepath:match("([^/\\]+)$") or filepath
    local lower = basename:lower()

    -- Auto-detect provider if auto or unspecified
    if not target_provider or target_provider == "auto" then
        if token:match("^AIza") or lower:match("gemini") or lower:match("google") then
            target_provider = "gemini"
        elseif token:match("^sk%-") or lower:match("openai") or lower:match("dall") then
            target_provider = "openai"
        elseif lower:match("fal") or lower:match("flux") then
            target_provider = "fal"
        else
            -- Default to Gemini if starting with standard AI token
            target_provider = "gemini"
        end
    end

    local setting_key = "api_key"
    local provider_name = "Google Gemini"
    if target_provider == "fal" then
        setting_key = "fal_key"
        provider_name = "Fal.ai"
    elseif target_provider == "openai" then
        setting_key = "openai_key"
        provider_name = "OpenAI"
    end

    self:set(setting_key, token)
    return true, string.format("%s Key saved! (%d chars from %s)", provider_name, #token, basename)
end

return Settings
