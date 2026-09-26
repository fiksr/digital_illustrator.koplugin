--[[--
Gemini AI Book Illustrator Plugin for KOReader.
Generates intelligent, genre-aware scene illustrations using Google Gemini 2026 models with chapter scanning and E-Ink styling.
Supports multiple image generation backends: Pollinations (Free Flux), Fal.ai, Google Gemini, and OpenAI.
--]]--

local _ = require("gettext")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")

local logger = require("logger")

-- Safely load internal modules
local plugin_dir = debug.getinfo(1, "S").source:match("@?(.*[/\\])") or ""

local Settings, API, Scanner, PromptEngine, SceneDialog, QRServer
local ok, mod

ok, mod = pcall(dofile, plugin_dir .. "settings.lua")
if ok then Settings = mod else logger.err("GeminiIllustrator: Failed to load settings.lua:", mod) end

ok, mod = pcall(dofile, plugin_dir .. "gemini_api.lua")
if ok then API = mod else logger.err("GeminiIllustrator: Failed to load gemini_api.lua:", mod) end

ok, mod = pcall(dofile, plugin_dir .. "chapter_scanner.lua")
if ok then Scanner = mod else logger.err("GeminiIllustrator: Failed to load chapter_scanner.lua:", mod) end

ok, mod = pcall(dofile, plugin_dir .. "prompt_engine.lua")
if ok then PromptEngine = mod else logger.err("GeminiIllustrator: Failed to load prompt_engine.lua:", mod) end

ok, mod = pcall(dofile, plugin_dir .. "scene_dialog.lua")
if ok then SceneDialog = mod else logger.err("GeminiIllustrator: Failed to load scene_dialog.lua:", mod) end

ok, mod = pcall(dofile, plugin_dir .. "qr_server.lua")
if ok then QRServer = mod else logger.err("GeminiIllustrator: Failed to load qr_server.lua:", mod) end

local GeminiIllustrator = WidgetContainer:extend{
    name = "gemini_illustrator",
    is_doc_only = false,
}

function GeminiIllustrator:onDispatcherRegisterActions()
    Dispatcher:registerAction("gemini_illustrator", {
        category = "none",
        event = "ShowGeminiIllustrator",
        title = _("Gemini AI Illustrator"),
        general = true,
    })
end

function GeminiIllustrator:onShowGeminiIllustrator()
    local Menu = require("ui/widget/menu")
    local menu = Menu:new{
        title = _("✨ Gemini AI Book Illustrator"),
        item_table = self:getSubMenuItems(),
        is_borderless = true,
    }
    UIManager:show(menu)
end

function GeminiIllustrator:ensureInitialized()
    if not self.settings then
        if not Settings then
            local ok_s, s_mod = pcall(dofile, plugin_dir .. "settings.lua")
            if ok_s then Settings = s_mod end
        end
        if Settings then self.settings = Settings:new() end
    end
    if not self.api and self.settings then
        if not API then
            local ok_a, a_mod = pcall(dofile, plugin_dir .. "gemini_api.lua")
            if ok_a then API = a_mod end
        end
        if API then self.api = API:new(self.settings) end
    end
    if not self.scanner then
        if not Scanner then
            local ok_sc, sc_mod = pcall(dofile, plugin_dir .. "chapter_scanner.lua")
            if ok_sc then Scanner = sc_mod end
        end
        if Scanner then self.scanner = Scanner:new() end
    end
    if not self.prompt_engine and self.settings then
        if not PromptEngine then
            local ok_pe, pe_mod = pcall(dofile, plugin_dir .. "prompt_engine.lua")
            if ok_pe then PromptEngine = pe_mod end
        end
        if PromptEngine then self.prompt_engine = PromptEngine:new(self.settings) end
    end
    if not self.scene_dialog and self.settings then
        if not SceneDialog then
            local ok_sd, sd_mod = pcall(dofile, plugin_dir .. "scene_dialog.lua")
            if ok_sd then SceneDialog = sd_mod end
        end
        if SceneDialog then self.scene_dialog = SceneDialog:new(self.settings) end
    end
    if not self.qr_server and self.settings then
        if not QRServer then
            local ok_qr, qr_mod = pcall(dofile, plugin_dir .. "qr_server.lua")
            if ok_qr then QRServer = qr_mod end
        end
        if QRServer then self.qr_server = QRServer:new(self.settings) end
    end
end

function GeminiIllustrator:init()
    self:ensureInitialized()

    if self.ui and self.ui.menu then
        self.ui.menu:registerToMainMenu(self)
    end

    self:onDispatcherRegisterActions()
end

-- Inject into KOReader's Top Main Menu
function GeminiIllustrator:addToMainMenu(menu_items)
    menu_items.gemini_illustrator = {
        text = _("✨ AI Book Illustrator"),
        sorting_hint = "more_tools",
        sub_item_table_func = function()
            return self:getSubMenuItems()
        end,
    }
end

-- Inject into Highlight Context Menu (when user highlights text in a book)
function GeminiIllustrator:onSelectionMenu(menu_items, selected_text)
    if not selected_text or #selected_text == 0 then return end
    local self_ref = self

    table.insert(menu_items, {
        text = _("✨ Gemini Illustrate"),
        callback = function()
            self_ref:illustrateSelectedText(selected_text)
        end,
    })
end

function GeminiIllustrator:onReaderHighlight(menu_items, selected_text)
    self:onSelectionMenu(menu_items, selected_text)
end

-- Cast of Characters Submenu
function GeminiIllustrator:buildCastSubmenu()
    self:ensureInitialized()
    local self_ref = self
    return {
        {
            text = _("📚 Read So Far (Spoiler-Free / Up to Current Page)"),
            help_text = _("Scans all pages read up to now and extracts characters met so far."),
            callback = function()
                self_ref:scanAndSuggestCharacters("book")
            end,
        },
        {
            text = _("🌐 Full Book (Internet Search / Wikipedia Cast)"),
            help_text = _("Searches Wikipedia and literary databases for canonical cast of the entire book."),
            callback = function()
                self_ref:scanAndSuggestCharacters("internet")
            end,
        },
        {
            text = _("📖 Current Chapter Cast"),
            help_text = _("Extracts characters appearing in this specific chapter."),
            callback = function()
                self_ref:scanAndSuggestCharacters("chapter")
            end,
        },
    }
end

-- Scenes & Illustrations Submenu
function GeminiIllustrator:buildScenesSubmenu()
    self:ensureInitialized()
    local self_ref = self
    return {
        {
            text = _("🎬 Suggest Chapter Scenes (3-4 AI Concepts)"),
            help_text = _("Gemini analyzes the full chapter and proposes 3-4 visual scenes."),
            callback = function()
                self_ref:scanAndSuggestScenes("chapter")
            end,
        },
        {
            text = _("📄 Illustrate Current Page"),
            help_text = _("Directly illustrate the scene on the currently visible page."),
            callback = function()
                self_ref:illustrateCurrentPage()
            end,
        },
        {
            text = _("📑 Scan Custom Page Range..."),
            help_text = _("Select a specific page range (e.g. pages 15-28)."),
            callback = function()
                local cur_p = (self_ref.ui and self_ref.ui.view and self_ref.ui.view.state and self_ref.ui.view.state.page) or 1
                self_ref.scene_dialog:showPageRangeDialog(cur_p, function(start_p, end_p)
                    self_ref:scanAndSuggestScenes("range", start_p, end_p)
                end)
            end,
        },
    }
end

-- Main TouchMenu structure (Categorized and clean, fits on a single screen)
function GeminiIllustrator:getSubMenuItems()
    self:ensureInitialized()
    local self_ref = self

    return {
        {
            text = _("🎭 Cast of Characters (Profiles & Portraits)"),
            help_text = _("Explore characters, read profile dossiers, and generate concept art portraits."),
            sub_item_table_func = function()
                return self_ref:buildCastSubmenu()
            end,
        },
        {
            text = _("✨ Scenes & Book Illustrations"),
            help_text = _("Generate high-contrast visual illustrations for scenes in the book."),
            sub_item_table_func = function()
                return self_ref:buildScenesSubmenu()
            end,
        },
        {
            text = _("📁 Saved Illustrations Gallery..."),
            help_text = _("Browse, view fullscreen, set as screensaver, or export illustrations."),
            callback = function()
                local book_info = self_ref.scanner:getBookInfo(self_ref.ui)
                self_ref.scene_dialog:showGallery(book_info)
            end,
        },
        {
            text = _("🖼️ Choose Image Model & Provider"),
            help_text = _("Pollinations (Free $0), Fal.ai ($0.003), Google Imagen / Nano Banana, or OpenAI"),
            sub_item_table_func = function()
                return self_ref:buildImageModelSubmenu()
            end,
        },
        {
            text = _("🎨 Choose Art Style"),
            help_text = _("Select E-Ink style: Engraving, Noir, Woodcut, etc."),
            sub_item_table_func = function()
                return self_ref:buildArtStyleSubmenu()
            end,
        },
        {
            text = _("🧠 Choose Text Analysis Model"),
            help_text = _("Gemini 3.1 Flash Lite (Free 500 RPD), 3.8 Flash, or Pro"),
            sub_item_table_func = function()
                return self_ref:buildTextModelSubmenu()
            end,
        },
        {
            text = _("🌐 Google Search Grounding"),
            help_text = _("Toggle web search for real-world visual descriptions."),
            checked_func = function()
                return self_ref.settings:get("enable_web_search") == true
            end,
            callback = function(touchmenu_instance)
                local cur = self_ref.settings:get("enable_web_search") == true
                self_ref.settings:set("enable_web_search", not cur)
                self_ref.settings:save()
                if touchmenu_instance and touchmenu_instance.updateItems then
                    touchmenu_instance:updateItems()
                end
                local state_txt = (not cur) and _("Enabled") or _("Disabled")
                UIManager:show(InfoMessage:new{
                    text = string.format(_("Google Search Grounding: %s"), state_txt),
                    timeout = 2,
                })
            end,
        },
        {
            text = _("📐 Image Resolution & Speed"),
            help_text = _("Fast 768x1024, Balanced, or Native 300 PPI."),
            sub_item_table_func = function()
                return self_ref:buildResolutionSubmenu()
            end,
        },
        {
            text = _("🔑 API Keys & Connection Setup"),
            help_text = _("Manage API keys and test connections."),
            sub_item_table_func = function()
                return self_ref:buildKeysMenu()
            end,
        },
    }
end

local json = nil
local ok_j, mod_j = pcall(require, "rapidjson")
if ok_j and mod_j and mod_j.decode then
    json = mod_j
else
    ok_j, mod_j = pcall(require, "json")
    if ok_j and mod_j and mod_j.decode then
        json = mod_j
    end
end

-- Persistent Chapter Cache Helpers
function GeminiIllustrator:getCacheFilePath(key)
    local save_dir = (self.settings and self.settings:get("save_dir")) or "/mnt/us/koreader/bookart"
    local cache_dir = save_dir .. "/cache"
    pcall(function() os.execute(string.format('mkdir -p "%s"', cache_dir)) end)
    local safe_key = key:gsub("[^%w_%-]", "_")
    return string.format("%s/%s.json", cache_dir, safe_key)
end

function GeminiIllustrator:getCachedScenes(key)
    if self.mem_cache and self.mem_cache[key] then
        return self.mem_cache[key]
    end
    local path = self:getCacheFilePath(key)
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    if not content or #content == 0 then return nil end

    local decoded = nil
    if json and json.decode then
        local ok, res = pcall(json.decode, content)
        if ok and res then decoded = res end
    end
    if decoded and type(decoded) == "table" and #decoded > 0 then
        if not self.mem_cache then self.mem_cache = {} end
        self.mem_cache[key] = decoded
        return decoded
    end
    return nil
end

function GeminiIllustrator:setCachedScenes(key, scenes)
    if not self.mem_cache then self.mem_cache = {} end
    self.mem_cache[key] = scenes

    local path = self:getCacheFilePath(key)
    if json and json.encode then
        local ok, enc = pcall(json.encode, scenes)
        if ok and enc then
            local f = io.open(path, "w")
            if f then
                f:write(enc)
                f:close()
            end
        end
    end
end

-- Workflow 1: Scan Chapter or Range, Present Scene Choices, and Generate (with Smart Persistent Caching)
function GeminiIllustrator:scanAndSuggestScenes(mode, custom_start, custom_end, force_refresh)
    self:ensureInitialized()
    local self_ref = self

    if not self.api:getGeminiKey() or #self.api:getGeminiKey() == 0 then
        UIManager:show(InfoMessage:new{
            text = _("Please enter your Google Gemini API key in Settings first.\n(Free text key from aistudio.google.com)"),
            timeout = 3.5,
        })
        return
    end

    local book_info = self.scanner:getBookInfo(self.ui)
    local text_to_analyze = ""
    local title_label = ""
    local cache_key_segment = ""

    if mode == "chapter" then
        local chapter_text, s_p, e_p, ch_title = self.scanner:getCurrentChapterText(self.ui)
        text_to_analyze = chapter_text
        title_label = string.format("%s (pp. %d-%d)", ch_title, s_p, e_p)
        cache_key_segment = string.format("ch_%s_%d_%d", ch_title, s_p, e_p)
    else
        local range_text, s_p, e_p = self.scanner:getPageRangeText(self.ui, custom_start, custom_end)
        text_to_analyze = range_text
        title_label = string.format(_("Pages %d - %d"), s_p, e_p)
        cache_key_segment = string.format("range_%d_%d", s_p, e_p)
    end

    local full_cache_key = string.format("%s_%s", book_info.title or "book", cache_key_segment)

    -- Explicitly purge cache if user requested re-scan
    if force_refresh then
        if self.mem_cache then self.mem_cache[full_cache_key] = nil end
        local cache_file = self:getCacheFilePath(full_cache_key)
        pcall(function() os.remove(cache_file) end)
    end

    -- 1. Check for Cached Chapter Scenes (Instant 0-second load without consuming API quota)
    if not force_refresh then
        local cached_scenes = self:getCachedScenes(full_cache_key)
        if cached_scenes and #cached_scenes > 0 then
            self.scene_dialog:showScenePicker(
                cached_scenes,
                title_label,
                function(chosen_scene)
                    self_ref:generateAndDisplayScene(chosen_scene, book_info)
                end,
                function()
                    -- Re-scan requested by user
                    self_ref:scanAndSuggestScenes(mode, custom_start, custom_end, true)
                end,
                true -- is_cached
            )
            return
        end
    end

    if #text_to_analyze < 30 then
        UIManager:show(InfoMessage:new{
            text = _("Could not extract text from document.\nPlease ensure a book is currently open."),
            timeout = 3,
        })
        return
    end

    local text_kb = math.max(1, math.floor(#text_to_analyze / 1024))
    local info = InfoMessage:new{
        text = string.format(_("🧠 Gemini (%s) is reading %s (%d KB text) and identifying dramatic scenes..."), self.api:getTextModel(), title_label, text_kb),
    }
    UIManager:show(info)

    UIManager:scheduleIn(0.1, function()
        local sys_prompt = self_ref.prompt_engine:buildAnalysisSystemInstruction(book_info)
        local scenes, err = self_ref.api:analyzeChapter(text_to_analyze, sys_prompt)
        UIManager:close(info)

        if not scenes or #scenes == 0 then
            UIManager:show(InfoMessage:new{
                text = string.format(_("Failed to analyze scenes:\n%s"), tostring(err)),
                timeout = 4,
            })
            return
        end

        -- Save to persistent cache
        self_ref:setCachedScenes(full_cache_key, scenes)

        -- Show the interactive scene picker with Re-scan option
        self_ref.scene_dialog:showScenePicker(
            scenes,
            title_label,
            function(chosen_scene)
                self_ref:generateAndDisplayScene(chosen_scene, book_info)
            end,
            function()
                self_ref:scanAndSuggestScenes(mode, custom_start, custom_end, true)
            end,
            false -- is_cached
        )
    end)
end

-- Workflow 2: Illustrate Current Page
function GeminiIllustrator:illustrateCurrentPage()
    self:ensureInitialized()
    local page_text = self.scanner:getCurrentPageText(self.ui)
    if #page_text < 20 then
        UIManager:show(InfoMessage:new{
            text = _("Could not extract text from the current page.\nPlease open a book first."),
            timeout = 2.5,
        })
        return
    end

    local book_info = self.scanner:getBookInfo(self.ui)
    local cur_p = (self.ui and self.ui.view and self.ui.view.state and self.ui.view.state.page) or 1
    local visual_prompt = self.prompt_engine:buildSingleScenePrompt(page_text, book_info)

    local scene_obj = {
        title = string.format(_("Page %d Scene"), cur_p),
        summary = page_text:sub(1, 140) .. "...",
        visual_prompt = visual_prompt,
    }

    self:generateAndDisplayScene(scene_obj, book_info)
end

-- Workflow 3: Illustrate Highlighted Text
function GeminiIllustrator:illustrateSelectedText(selected_text)
    self:ensureInitialized()
    local book_info = self.scanner:getBookInfo(self.ui)
    local visual_prompt = self.prompt_engine:buildSingleScenePrompt(selected_text, book_info)

    local scene_obj = {
        title = _("Highlighted Scene"),
        summary = selected_text:sub(1, 140) .. "...",
        visual_prompt = visual_prompt,
    }

    self:generateAndDisplayScene(scene_obj, book_info)
end

-- Core: Calls Image API and Opens Fullscreen Viewer
function GeminiIllustrator:generateAndDisplayScene(scene_obj, book_info)
    self:ensureInitialized()
    local self_ref = self
    local visual_prompt = scene_obj.visual_prompt or scene_obj.summary or "Book illustration"
    local save_dir = self.settings:get("save_dir") or "/mnt/us/koreader/bookart"
    local timestamp = os.time()
    local out_path = string.format("%s/scene_%d.png", save_dir, timestamp)

    local img_model = self.api:getImageModel()
    local info = InfoMessage:new{
        text = string.format(_("🎨 Generating illustration with %s...\n(%s)"), img_model, scene_obj.title or ""),
    }
    UIManager:show(info)

    UIManager:scheduleIn(0.1, function()
        local generated_file, err = self_ref.api:generateImage(visual_prompt, out_path)
        UIManager:close(info)

        if generated_file then
            self_ref.scene_dialog:showGeneratedArtwork(generated_file, scene_obj, book_info)
        else
            UIManager:show(InfoMessage:new{
                text = string.format(_("Failed to generate image:\n%s"), tostring(err)),
                timeout = 4,
            })
        end
    end)
end

-- Workflow 4: Extract Cast of Characters, Present Choices, and Generate Portrait
function GeminiIllustrator:scanAndSuggestCharacters(mode, force_refresh)
    self:ensureInitialized()
    local self_ref = self

    if not self.api:getGeminiKey() or #self.api:getGeminiKey() == 0 then
        UIManager:show(InfoMessage:new{
            text = _("Please enter your Google Gemini API key in Settings first.\n(Free text key from aistudio.google.com)"),
            timeout = 3.5,
        })
        return
    end

    local book_info = self.scanner:getBookInfo(self.ui)
    local text_to_analyze = ""
    local title_label = ""
    local cache_key_segment = ""

    if mode == "chapter" then
        local chapter_text, s_p, e_p, ch_title = self.scanner:getCurrentChapterText(self.ui)
        text_to_analyze = chapter_text
        title_label = string.format("%s Characters (pp. %d-%d)", ch_title, s_p, e_p)
        cache_key_segment = string.format("cast_ch_%s_%d_%d", ch_title, s_p, e_p)
    elseif mode == "internet" then
        title_label = string.format(_("Internet Cast (%s)"), book_info.title or "Book")
        cache_key_segment = "cast_internet"
    else
        local book_text, s_p, e_p = self.scanner:getTextUpToCurrentPage(self.ui)
        text_to_analyze = book_text
        title_label = string.format(_("Full Cast (pp. 1-%d)"), e_p)
        cache_key_segment = string.format("cast_full_%d", e_p)
    end

    local full_cache_key = string.format("%s_%s", book_info.title or "book", cache_key_segment)

    -- Explicitly purge cache if user requested re-scan
    if force_refresh then
        if self.mem_cache then self.mem_cache[full_cache_key] = nil end
        local cache_file = self:getCacheFilePath(full_cache_key)
        pcall(function() os.remove(cache_file) end)
    end

    -- 1. Check for Cached Characters (Instant 0-second load)
    if not force_refresh then
        local cached_cast = self:getCachedScenes(full_cache_key)
        if cached_cast and #cached_cast > 0 then
            for _, char in ipairs(cached_cast) do
                char.has_portrait = (self_ref:getExistingCharacterPortrait(char, book_info) ~= nil)
            end
            self.scene_dialog:showCharacterPicker(
                cached_cast,
                title_label,
                function(chosen_char)
                    self_ref.scene_dialog:showCharacterCard(
                        chosen_char,
                        book_info,
                        function(c_obj, force_regen)
                            self_ref:generateAndDisplayCharacterPortrait(c_obj, book_info, force_regen)
                        end,
                        function(c_obj)
                            self_ref:generateAndDisplayCharacterPortrait(c_obj, book_info, false)
                        end
                    )
                end,
                function()
                    self_ref:scanAndSuggestCharacters(mode, true)
                end,
                true -- is_cached
            )
            return
        end
    end

    if mode ~= "internet" and #text_to_analyze < 30 then
        UIManager:show(InfoMessage:new{
            text = _("Could not extract text from document.\nPlease ensure a book is currently open."),
            timeout = 3,
        })
        return
    end

    local text_kb = math.max(1, math.floor(#text_to_analyze / 1024))
    local enable_web_search = (mode == "internet") or (self.settings:get("enable_web_search") == true)
    local search_hint = enable_web_search and " [+Google Search]" or ""
    local msg_text = ""
    if mode == "internet" then
        msg_text = string.format(_("🌐 Gemini is searching the web for characters in '%s' by %s..."), book_info.title or "Book", book_info.author or "Author")
    else
        msg_text = string.format(_("🧠 Gemini is identifying characters from %s (%d KB text)%s..."), title_label, text_kb, search_hint)
    end

    local info = InfoMessage:new{
        text = msg_text,
    }
    UIManager:show(info)

    UIManager:scheduleIn(0.1, function()
        local characters, err = nil, nil
        if mode == "internet" then
            local sys_prompt = self_ref.prompt_engine:buildInternetCharacterAnalysisInstruction(book_info)
            characters, err = self_ref.api:extractCharactersFromInternet(book_info, sys_prompt)
        else
            local sys_prompt = self_ref.prompt_engine:buildCharacterAnalysisInstruction(book_info, enable_web_search)
            characters, err = self_ref.api:extractCharacters(text_to_analyze, sys_prompt, enable_web_search)
        end
        UIManager:close(info)

        if not characters or #characters == 0 then
            UIManager:show(InfoMessage:new{
                text = string.format(_("Failed to extract characters:\n%s"), tostring(err)),
                timeout = 4,
            })
            return
        end

        -- Save to persistent cache
        self_ref:setCachedScenes(full_cache_key, characters)

        for _, char in ipairs(characters) do
            char.has_portrait = (self_ref:getExistingCharacterPortrait(char, book_info) ~= nil)
        end

        -- Show character picker
        self_ref.scene_dialog:showCharacterPicker(
            characters,
            title_label,
            function(chosen_char)
                self_ref.scene_dialog:showCharacterCard(
                    chosen_char,
                    book_info,
                    function(c_obj, force_regen)
                        self_ref:generateAndDisplayCharacterPortrait(c_obj, book_info, force_regen)
                    end,
                    function(c_obj)
                        self_ref:generateAndDisplayCharacterPortrait(c_obj, book_info, false)
                    end
                )
            end,
            function()
                self_ref:scanAndSuggestCharacters(mode, true)
            end,
            false -- is_cached
        )
    end)
end

-- Helper to get the canonical portrait path for a character
function GeminiIllustrator:getCharacterPortraitPath(char_obj, book_info)
    local save_dir = (self.settings and self.settings:get("save_dir")) or "/mnt/us/koreader/bookart"
    local portraits_dir = save_dir .. "/portraits"
    pcall(function() os.execute(string.format('mkdir -p "%s"', portraits_dir)) end)
    local safe_book = ((book_info and book_info.title) or "book"):gsub("[^%w_%-]", "_"):sub(1, 40)
    local safe_name = ((char_obj and char_obj.name) or "char"):gsub("[^%w_%-]", "_"):sub(1, 40)
    return string.format("%s/%s_%s.png", portraits_dir, safe_book, safe_name)
end

-- Check if a portrait already exists on disk (valid image > 1000 bytes)
function GeminiIllustrator:getExistingCharacterPortrait(char_obj, book_info)
    local target_path = self:getCharacterPortraitPath(char_obj, book_info)
    local f = io.open(target_path, "rb")
    if f then
        local size = f:seek("end")
        f:close()
        if size and size > 1000 then
            return target_path
        end
    end

    -- Check legacy or direct fallback location: [save_dir]/char_[safe_name].png
    local save_dir = (self.settings and self.settings:get("save_dir")) or "/mnt/us/koreader/bookart"
    local safe_name = ((char_obj and char_obj.name) or "char"):gsub("[^%w_%-]", "_"):sub(1, 40)
    local f2 = io.open(string.format("%s/char_%s.png", save_dir, safe_name), "rb")
    if f2 then
        local size = f2:seek("end")
        f2:close()
        if size and size > 1000 then
            return string.format("%s/char_%s.png", save_dir, safe_name)
        end
    end

    return nil
end

-- Generate Character Portrait or load existing one instantly (0 seconds, 0 quota)
function GeminiIllustrator:generateAndDisplayCharacterPortrait(char_obj, book_info, force_regenerate)
    self:ensureInitialized()
    local self_ref = self
    local visual_prompt = char_obj.visual_prompt or string.format("Vertical portrait concept art of %s, %s", char_obj.name or "Character", char_obj.role or "")
    local scene_obj = {
        title = string.format("🎭 %s", char_obj.name or "Character"),
        summary = string.format("%s\n\n%s", char_obj.role and ("Role: " .. char_obj.role) or "", char_obj.summary or ""),
        visual_prompt = visual_prompt,
        character = char_obj,
    }

    local existing_file = (not force_regenerate) and self:getExistingCharacterPortrait(char_obj, book_info)
    if existing_file then
        -- INSTANT 0-SECOND LOAD: Reuse existing portrait without calling API
        self.scene_dialog:showGeneratedArtwork(
            existing_file,
            scene_obj,
            book_info,
            function()
                -- Callback if user requests regeneration
                self_ref:generateAndDisplayCharacterPortrait(char_obj, book_info, true)
            end
        )
        return
    end

    local out_path = self:getCharacterPortraitPath(char_obj, book_info)
    local img_model = self.api:getImageModel()
    local info = InfoMessage:new{
        text = string.format(_("🎨 Generating portrait of %s with %s..."), char_obj.name or "Character", img_model),
    }
    UIManager:show(info)

    UIManager:scheduleIn(0.1, function()
        local generated_file, err = self_ref.api:generateImage(visual_prompt, out_path)
        UIManager:close(info)

        if generated_file then
            self_ref.scene_dialog:showGeneratedArtwork(
                generated_file,
                scene_obj,
                book_info,
                function()
                    self_ref:generateAndDisplayCharacterPortrait(char_obj, book_info, true)
                end
            )
        else
            UIManager:show(InfoMessage:new{
                text = string.format(_("Failed to generate character portrait:\n%s"), tostring(err)),
                timeout = 4,
            })
        end
    end)
end

-- Image Model Submenu
function GeminiIllustrator:buildImageModelSubmenu()
    self:ensureInitialized()
    local self_ref = self
    local items = {}
    local img_models = (Settings and Settings.IMAGE_MODELS) or {}

    for _, m in ipairs(img_models) do
        table.insert(items, {
            text = m.name,
            help_text = m.desc,
            checked_func = function()
                return (self_ref.settings and self_ref.settings:get("image_model") == m.id)
            end,
            callback = function(touchmenu_instance)
                if self_ref.settings then
                    self_ref.settings:set("image_model", m.id)
                end
                if touchmenu_instance and touchmenu_instance.updateItems then
                    touchmenu_instance:updateItems()
                end
            end,
        })
    end

    return items
end

-- Text Model Submenu
function GeminiIllustrator:buildTextModelSubmenu()
    self:ensureInitialized()
    local self_ref = self
    local items = {}
    local text_models = (Settings and Settings.TEXT_MODELS) or {}

    for _, m in ipairs(text_models) do
        table.insert(items, {
            text = m.name,
            help_text = m.desc,
            checked_func = function()
                return (self_ref.settings and self_ref.settings:get("text_model") == m.id)
            end,
            callback = function(touchmenu_instance)
                if self_ref.settings then
                    self_ref.settings:set("text_model", m.id)
                end
                if touchmenu_instance and touchmenu_instance.updateItems then
                    touchmenu_instance:updateItems()
                end
            end,
        })
    end

    return items
end

-- Art Style Submenu
function GeminiIllustrator:buildArtStyleSubmenu()
    self:ensureInitialized()
    local self_ref = self
    local items = {}
    local art_styles = (Settings and Settings.ART_STYLES) or {}

    for _, st in ipairs(art_styles) do
        table.insert(items, {
            text = st.name,
            help_text = st.desc,
            checked_func = function()
                return (self_ref.settings and self_ref.settings:get("art_style") == st.id)
            end,
            callback = function(touchmenu_instance)
                if self_ref.settings then
                    self_ref.settings:set("art_style", st.id)
                end
                if touchmenu_instance and touchmenu_instance.updateItems then
                    touchmenu_instance:updateItems()
                end
            end,
        })
    end

    return items
end

-- Resolution Submenu
function GeminiIllustrator:buildResolutionSubmenu()
    self:ensureInitialized()
    local self_ref = self
    local items = {}
    local resolutions = (Settings and Settings.RESOLUTIONS) or {}

    for _, res in ipairs(resolutions) do
        table.insert(items, {
            text = res.name,
            help_text = res.desc,
            checked_func = function()
                return (self_ref.settings and self_ref.settings:get("resolution") == res.id)
            end,
            callback = function(touchmenu_instance)
                if self_ref.settings then
                    self_ref.settings:set("resolution", res.id)
                end
                if touchmenu_instance and touchmenu_instance.updateItems then
                    touchmenu_instance:updateItems()
                end
            end,
        })
    end

    return items
end

-- API Keys Submenu
function GeminiIllustrator:buildKeysMenu()
    self:ensureInitialized()
    local self_ref = self

    return {
        {
            text = _("📱 Pair with Phone (Scan QR Code)"),
            help_text = _("Scan QR with your phone to paste and send all keys instantly over Wi-Fi."),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                if self_ref.qr_server then
                    self_ref.qr_server:start(function()
                        if touchmenu_instance and touchmenu_instance.updateItems then
                            touchmenu_instance:updateItems()
                        end
                    end)
                end
            end,
        },
        {
            text = _("Test Connection & Validate Keys"),
            keep_menu_open = true,
            callback = function()
                local info = InfoMessage:new{ text = _("Connecting to AI Services...") }
                UIManager:show(info)
                local ok_conn, msg = self_ref.api:ping()
                UIManager:close(info)
                UIManager:show(InfoMessage:new{ text = msg, timeout = 4 })
            end,
        },
        {
            text_func = function()
                local key = (self_ref.settings and self_ref.settings:get("api_key")) or ""
                local status = (#key > 0) and string.format(_("Configured (%d chars)"), #key) or _("Not Set")
                return string.format(_("Google Gemini Key: %s"), status)
            end,
            help_text = _("Required for Text Analysis & Chapter Brain (Free key from aistudio.google.com)"),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                local dialog
                dialog = InputDialog:new{
                    title = _("Google AI Studio API Key"),
                    description = _("Paste your Gemini API key:"),
                    input = (self_ref.settings and self_ref.settings:get("api_key")) or "",
                    buttons = {
                        {
                            {
                                text = _("Cancel"),
                                id = "close",
                                callback = function() UIManager:close(dialog) end,
                            },
                            {
                                text = _("Save"),
                                is_enter_default = true,
                                callback = function()
                                    local new_key = dialog:getInputText()
                                    UIManager:close(dialog)
                                    if self_ref.settings then
                                        self_ref.settings:set("api_key", new_key)
                                    end
                                    UIManager:show(InfoMessage:new{ text = _("Gemini Key saved."), timeout = 2 })
                                    if touchmenu_instance and touchmenu_instance.updateItems then
                                        touchmenu_instance:updateItems()
                                    end
                                end,
                            },
                        },
                    },
                }
                UIManager:show(dialog)
                dialog:onShowKeyboard()
            end,
        },
        {
            text_func = function()
                local key = (self_ref.settings and self_ref.settings:get("fal_key")) or ""
                local status = (#key > 0) and string.format(_("Configured (%d chars)"), #key) or _("Not Set")
                return string.format(_("Fal.ai API Key: %s"), status)
            end,
            help_text = _("Optional key for Fal.ai FLUX ($0.003 / image from fal.ai)"),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                local dialog
                dialog = InputDialog:new{
                    title = _("Fal.ai API Key"),
                    description = _("Paste your Fal.ai Key (for Flux.1 Schnell $0.003):"),
                    input = (self_ref.settings and self_ref.settings:get("fal_key")) or "",
                    buttons = {
                        {
                            {
                                text = _("Cancel"),
                                id = "close",
                                callback = function() UIManager:close(dialog) end,
                            },
                            {
                                text = _("Save"),
                                is_enter_default = true,
                                callback = function()
                                    local new_key = dialog:getInputText()
                                    UIManager:close(dialog)
                                    if self_ref.settings then
                                        self_ref.settings:set("fal_key", new_key)
                                    end
                                    UIManager:show(InfoMessage:new{ text = _("Fal.ai Key saved."), timeout = 2 })
                                    if touchmenu_instance and touchmenu_instance.updateItems then
                                        touchmenu_instance:updateItems()
                                    end
                                end,
                            },
                        },
                    },
                }
                UIManager:show(dialog)
                dialog:onShowKeyboard()
            end,
        },
        {
            text_func = function()
                local key = (self_ref.settings and self_ref.settings:get("openai_key")) or ""
                local status = (#key > 0) and string.format(_("Configured (%d chars)"), #key) or _("Not Set")
                return string.format(_("OpenAI API Key: %s"), status)
            end,
            help_text = _("Optional key for OpenAI DALL-E 3"),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                local dialog
                dialog = InputDialog:new{
                    title = _("OpenAI API Key"),
                    description = _("Paste your OpenAI Key (for DALL-E 3):"),
                    input = (self_ref.settings and self_ref.settings:get("openai_key")) or "",
                    buttons = {
                        {
                            {
                                text = _("Cancel"),
                                id = "close",
                                callback = function() UIManager:close(dialog) end,
                            },
                            {
                                text = _("Save"),
                                is_enter_default = true,
                                callback = function()
                                    local new_key = dialog:getInputText()
                                    UIManager:close(dialog)
                                    if self_ref.settings then
                                        self_ref.settings:set("openai_key", new_key)
                                    end
                                    UIManager:show(InfoMessage:new{ text = _("OpenAI Key saved."), timeout = 2 })
                                    if touchmenu_instance and touchmenu_instance.updateItems then
                                        touchmenu_instance:updateItems()
                                    end
                                end,
                            },
                        },
                    },
                }
                UIManager:show(dialog)
                dialog:onShowKeyboard()
            end,
        },
        {
            text_func = function()
                local on = self_ref.settings and self_ref.settings:get("enable_web_search") == true
                return on and _("🌐 Character Web Search: ON (Google Grounding)") or _("🌐 Character Web Search: OFF (Book Text Only)")
            end,
            help_text = _("When ON, searches Google/wikis for canonical character details. When OFF, uses Kindle book text only."),
            checked_func = function()
                return self_ref.settings and self_ref.settings:get("enable_web_search") == true
            end,
            callback = function(touchmenu_instance)
                if self_ref.settings then
                    local cur = self_ref.settings:get("enable_web_search") == true
                    self_ref.settings:set("enable_web_search", not cur)
                    local state_str = (not cur) and _("Enabled (Google Grounding)") or _("Disabled (Book Text Only)")
                    UIManager:show(InfoMessage:new{ text = string.format(_("Character Web Search: %s"), state_str), timeout = 2 })
                end
                if touchmenu_instance and touchmenu_instance.updateItems then
                    touchmenu_instance:updateItems()
                end
            end,
        },
        {
            text = _("📁 Browse Storage for Key File (*.txt)..."),
            help_text = _("Select any .txt or .key file from Kindle storage to import keys."),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                self_ref:browseAndImportKeyFile(touchmenu_instance)
            end,
        },
        {
            text = _("⚡ Quick Import from /mnt/us/*.txt"),
            help_text = _("Auto-detects gemini_token.txt, fal_token.txt, or openai_token.txt on Kindle root."),
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                if self_ref.settings then
                    local msgs = {}
                    local ok_g, msg_g = self_ref.settings:importTokenFromFile("gemini", "gemini_token.txt")
                    if ok_g then table.insert(msgs, "Gemini Key: OK") end

                    local ok_f, msg_f = self_ref.settings:importTokenFromFile("fal", "fal_token.txt")
                    if ok_f then table.insert(msgs, "Fal Key: OK") end

                    local ok_o, msg_o = self_ref.settings:importTokenFromFile("openai", "openai_token.txt")
                    if ok_o then table.insert(msgs, "OpenAI Key: OK") end

                    if #msgs > 0 then
                        UIManager:show(InfoMessage:new{ text = table.concat(msgs, "\n"), timeout = 3 })
                    else
                        UIManager:show(InfoMessage:new{ text = _("No standard token files found on Kindle root storage.\n(Use 'Browse Storage' above to select your file)"), timeout = 4 })
                    end

                    if touchmenu_instance and touchmenu_instance.updateItems then
                        touchmenu_instance:updateItems()
                    end
                end
            end,
        },
    }
end

-- Open PathChooser to let the user browse and pick any key text file
function GeminiIllustrator:browseAndImportKeyFile(touchmenu_instance)
    self:ensureInitialized()
    local self_ref = self

    local ok_pc, PathChooser = pcall(require, "ui/widget/pathchooser")
    if not ok_pc or not PathChooser then
        self:showFallbackTxtPicker(touchmenu_instance)
        return
    end

    local chooser
    chooser = PathChooser:new{
        path = "/mnt/us",
        title = _("Select API Key File:"),
        select_directory = false,
        select_file = true,
        show_files = true,
        file_filter = function(filename)
            local lower = filename:lower()
            return lower:match("%.txt$") or lower:match("%.key$") or lower:match("%.token$") or lower:match("token") or lower:match("key")
        end,
        onConfirm = function(chosen_path)
            if self_ref.settings then
                local ok_imp, msg = self_ref.settings:importKeyFromArbitraryFile(chosen_path, "auto")
                if ok_imp then
                    UIManager:show(InfoMessage:new{ text = msg, timeout = 3.5 })
                else
                    UIManager:show(InfoMessage:new{ text = string.format(_("Import failed:\n%s"), msg), timeout = 3.5 })
                end
                if touchmenu_instance and touchmenu_instance.updateItems then
                    touchmenu_instance:updateItems()
                end
            end
        end,
    }
    UIManager:show(chooser)
end

-- Fallback TXT file picker if PathChooser cannot be instantiated
function GeminiIllustrator:showFallbackTxtPicker(touchmenu_instance)
    self:ensureInitialized()
    local self_ref = self
    local files = {}
    local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok_lfs then ok_lfs, lfs = pcall(require, "lfs") end

    if ok_lfs and lfs and lfs.dir then
        pcall(function()
            for fname in lfs.dir("/mnt/us") do
                if fname:match("%.txt$") or fname:match("%.key$") then
                    table.insert(files, "/mnt/us/" .. fname)
                end
            end
        end)
    else
        local p = io.popen("ls /mnt/us/*.txt /mnt/us/*.key 2>/dev/null")
        if p then
            for line in p:lines() do
                local fpath = line:gsub("^%s+", ""):gsub("%s+$", "")
                if #fpath > 0 then table.insert(files, fpath) end
            end
            p:close()
        end
    end

    if #files == 0 then
        UIManager:show(InfoMessage:new{
            text = _("No .txt files found in /mnt/us/\nPlease copy your key text file to Kindle root storage."),
            timeout = 3.5,
        })
        return
    end

    local Menu = require("ui/widget/menu")
    local items = {}
    for _, fpath in ipairs(files) do
        local fname = fpath:match("([^/\\]+)$") or fpath
        table.insert(items, {
            text = string.format("📄 %s", fname),
            help_text = fpath,
            callback = function()
                local ok_imp, msg = self_ref.settings:importKeyFromArbitraryFile(fpath, "auto")
                if ok_imp then
                    UIManager:show(InfoMessage:new{ text = msg, timeout = 3.5 })
                else
                    UIManager:show(InfoMessage:new{ text = string.format(_("Import failed:\n%s"), msg), timeout = 3.5 })
                end
                if touchmenu_instance and touchmenu_instance.updateItems then
                    touchmenu_instance:updateItems()
                end
            end,
        })
    end
    table.insert(items, { text = _("Cancel"), callback = function() end })

    local menu = Menu:new{
        title = _("Select Key File from /mnt/us"),
        item_table = items,
        is_borderless = true,
    }
    UIManager:show(menu)
end

return GeminiIllustrator
