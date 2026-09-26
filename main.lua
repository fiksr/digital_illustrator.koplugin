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

-- Safely load internal modules
local plugin_dir = debug.getinfo(1, "S").source:match("@?(.*[/\\])") or ""

local Settings, API, Scanner, PromptEngine, SceneDialog
local ok, mod

ok, mod = pcall(dofile, plugin_dir .. "settings.lua")
if ok then Settings = mod end

ok, mod = pcall(dofile, plugin_dir .. "gemini_api.lua")
if ok then API = mod end

ok, mod = pcall(dofile, plugin_dir .. "chapter_scanner.lua")
if ok then Scanner = mod end

ok, mod = pcall(dofile, plugin_dir .. "prompt_engine.lua")
if ok then PromptEngine = mod end

ok, mod = pcall(dofile, plugin_dir .. "scene_dialog.lua")
if ok then SceneDialog = mod end

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
    if not self.settings and Settings then
        self.settings = Settings:new()
    end
    if not self.api and API and self.settings then
        self.api = API:new(self.settings)
    end
    if not self.scanner and Scanner then
        self.scanner = Scanner:new()
    end
    if not self.prompt_engine and PromptEngine and self.settings then
        self.prompt_engine = PromptEngine:new(self.settings)
    end
    if not self.scene_dialog and SceneDialog and self.settings then
        self.scene_dialog = SceneDialog:new(self.settings)
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

-- Submenu structure
function GeminiIllustrator:getSubMenuItems()
    self:ensureInitialized()
    local self_ref = self

    return {
        {
            text = _("✨ Scan Current Chapter (AI Scene Suggestions)"),
            help_text = _("Gemini analyzes the full chapter and proposes 3-4 visual scenes."),
            callback = function()
                self_ref:scanAndSuggestScenes("chapter")
            end,
        },
        {
            text = _("📑 Scan Custom Page Range..."),
            help_text = _("Pick a specific page range (e.g. pages 15-28)."),
            callback = function()
                local cur_p = (self_ref.ui and self_ref.ui.view and self_ref.ui.view.state and self_ref.ui.view.state.page) or 1
                self_ref.scene_dialog:showPageRangeDialog(cur_p, function(start_p, end_p)
                    self_ref:scanAndSuggestScenes("range", start_p, end_p)
                end)
            end,
        },
        {
            text = _("📄 Illustrate Current Page"),
            help_text = _("Directly illustrate the scene on the visible page."),
            callback = function()
                self_ref:illustrateCurrentPage()
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
            text = _("📐 Image Resolution & Speed"),
            help_text = _("Fast 768x1024, Balanced, or Native 300 PPI."),
            sub_item_table_func = function()
                return self_ref:buildResolutionSubmenu()
            end,
        },
        {
            text = _("⚙️ Connection & API Settings"),
            sub_item_table_func = function()
                return self_ref:buildSettingsMenu()
            end,
        },
    }
end

-- Workflow 1: Scan Chapter or Range, Present Scene Choices, and Generate
function GeminiIllustrator:scanAndSuggestScenes(mode, custom_start, custom_end)
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

    if mode == "chapter" then
        local chapter_text, s_p, e_p, ch_title = self.scanner:getCurrentChapterText(self.ui)
        text_to_analyze = chapter_text
        title_label = string.format("%s (pp. %d-%d)", ch_title, s_p, e_p)
    else
        local range_text, s_p, e_p = self.scanner:getPageRangeText(self.ui, custom_start, custom_end)
        text_to_analyze = range_text
        title_label = string.format(_("Pages %d - %d"), s_p, e_p)
    end

    if #text_to_analyze < 30 then
        UIManager:show(InfoMessage:new{
            text = _("Could not extract text from document.\nPlease ensure a book is currently open."),
            timeout = 3,
        })
        return
    end

    local info = InfoMessage:new{
        text = string.format(_("🧠 Gemini (%s) is reading %s and identifying dramatic scenes..."), self.api:getTextModel(), title_label),
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

        -- Show the interactive scene picker
        self_ref.scene_dialog:showScenePicker(scenes, title_label, function(chosen_scene)
            self_ref:generateAndDisplayScene(chosen_scene, book_info)
        end)
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

-- Settings Submenu (API keys, Models, Import)
function GeminiIllustrator:buildSettingsMenu()
    self:ensureInitialized()
    local self_ref = self

    -- Text Model Items
    local text_model_items = {}
    local text_models = (Settings and Settings.TEXT_MODELS) or {}
    for _, m in ipairs(text_models) do
        table.insert(text_model_items, {
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

    -- Image Model Items (All Providers)
    local img_model_items = {}
    local img_models = (Settings and Settings.IMAGE_MODELS) or {}
    for _, m in ipairs(img_models) do
        table.insert(img_model_items, {
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

    return {
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
                local cur = (self_ref.settings and self_ref.settings:get("image_model")) or "pollinations-flux"
                for _, m in ipairs(img_models) do
                    if m.id == cur then return string.format(_("🖼️ Image Model: %s"), m.name) end
                end
                return string.format(_("🖼️ Image Model: %s"), cur)
            end,
            help_text = _("Choose between Pollinations ($0), Fal.ai ($0.003), Google ($0.07), or OpenAI"),
            sub_item_table = img_model_items,
        },
        {
            text_func = function()
                local cur = (self_ref.settings and self_ref.settings:get("text_model")) or "gemini-3.1-flash-lite"
                return string.format(_("🧠 Text / Analysis Model: %s"), cur)
            end,
            help_text = _("Reads & analyzes chapters (Gemini Flash Lite is 100% Free)"),
            sub_item_table = text_model_items,
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
            text = _("Import Keys from Kindle Files (/mnt/us/*.txt)"),
            help_text = _("Reads gemini_token.txt, fal_token.txt, or openai_token.txt on Kindle root."),
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
                        UIManager:show(InfoMessage:new{ text = _("No token files found.\n(Place gemini_token.txt, fal_token.txt, or openai_token.txt on Kindle)"), timeout = 3.5 })
                    end

                    if touchmenu_instance and touchmenu_instance.updateItems then
                        touchmenu_instance:updateItems()
                    end
                end
            end,
        },
    }
end

return GeminiIllustrator
