--[[--
Settings and persistence manager for Gemini AI Book Illustrator plugin.
Stores settings in G_reader_settings and supports /mnt/us/gemini_token.txt import.
--]]--

local Settings = {}
Settings.__index = Settings

local DEFAULT_SETTINGS = {
    api_key = "",
    text_model = "gemini-3.1-flash-lite",       -- 500 RPD high quota
    image_model = "gemini-3.1-flash-lite-image", -- Nano Banana 2 Lite (Fastest for Kindle)
    resolution = "768x1024",                     -- Fast, responsive for Kindle Wi-Fi & 3:4 E-Ink
    art_style = "auto_genre",                    -- Automatically adapt to book genre
    save_dir = "/mnt/us/koreader/bookart",
    timeout = 25,
    auto_contrast_prompt = true,
}

Settings.TEXT_MODELS = {
    { id = "gemini-3.1-flash-lite", name = "Gemini 3.1 Flash Lite (500 RPD - Recommended)", desc = "High rate limits, ultra-fast chapter analysis" },
    { id = "gemini-3.8-flash",      name = "Gemini 3.8 Flash (2026 Flagship)",              desc = "Deep contextual understanding" },
    { id = "gemini-2.5-flash",      name = "Gemini 2.5 Flash",                              desc = "Stable high-speed model" },
    { id = "gemini-2.0-flash",      name = "Gemini 2.0 Flash",                              desc = "Fast legacy flash model" },
    { id = "gemini-2.5-pro",        name = "Gemini 2.5 Pro",                                desc = "Maximum literary reasoning" },
}

Settings.IMAGE_MODELS = {
    { id = "gemini-3.1-flash-lite-image", name = "Nano Banana 2 Lite (Gemini 3.1 Flash Lite Image)", desc = "Fastest image generation (2.7x speed, ideal for Kindle)" },
    { id = "gemini-3.1-flash-image",      name = "Nano Banana 2 (Gemini 3.1 Flash Image)",          desc = "High-quality multimodal image generation" },
    { id = "gemini-3-pro-image",          name = "Nano Banana Pro (Gemini 3 Pro Image)",            desc = "Maximum artistic detail & composition" },
    { id = "imagen-4.0-generate-001",     name = "Google Imagen 4.0 Standard",                      desc = "Photorealistic and stylistic rendering" },
    { id = "imagen-3.0-generate-002",     name = "Google Imagen 3.0",                               desc = "Proven high-detail illustration model" },
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

    -- Sanitize API Key and strings
    if type(self.data.api_key) == "string" then
        self.data.api_key = self.data.api_key:gsub("^%s+", ""):gsub("%s+$", ""):gsub("[\r\n]", "")
    end
    self.data.timeout = tonumber(self.data.timeout) or 25
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
    if key == "api_key" and type(value) == "string" then
        value = value:gsub("^%s+", ""):gsub("%s+$", ""):gsub("[\r\n]", "")
    elseif key == "timeout" then
        value = tonumber(value) or 25
    end
    self.data[key] = value
    self:save()
end

-- Import token from /mnt/us/gemini_token.txt or candidate paths (does NOT delete file)
function Settings:importTokenFromFile(specified_filepath)
    local candidate_paths = {}
    if specified_filepath and #specified_filepath > 0 then
        table.insert(candidate_paths, specified_filepath)
    end

    table.insert(candidate_paths, "/mnt/us/gemini_token.txt")
    table.insert(candidate_paths, "/mnt/us/gemini_token.txt.txt") -- Windows double-extension protection
    table.insert(candidate_paths, "/mnt/us/gemini_token")
    table.insert(candidate_paths, "/mnt/us/koreader/gemini_token.txt")
    table.insert(candidate_paths, "/mnt/base-us/gemini_token.txt")
    table.insert(candidate_paths, "gemini_token.txt")
    table.insert(candidate_paths, "gemini_token.txt.txt")

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
        return false, "File not found: /mnt/us/gemini_token.txt\n(Make sure file is placed on Kindle root drive)"
    end

    local token = found_file:read("*a")
    found_file:close()

    if not token then
        return false, "Could not read token file."
    end

    token = token:gsub("^%s+", ""):gsub("%s+$", ""):gsub("[\r\n]", "")

    if #token < 10 then
        return false, "API Key is too short or empty (length: " .. #token .. ")."
    end

    self:set("api_key", token)

    return true, string.format("Gemini API key imported successfully! (%d chars from %s)", #token, found_path)
end

return Settings
