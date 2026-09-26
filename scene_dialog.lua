--[[--
UI Dialogs and Viewers for Gemini AI Book Illustrator.
Renders scene suggestion lists, full-screen image views, and custom page range pickers.
--]]--

local _ = require("gettext")
local ButtonDialog = require("ui/widget/buttondialog")
local ImageViewer = require("ui/widget/imageviewer")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local Menu = require("ui/widget/menu")
local UIManager = require("ui/uimanager")

local SceneDialog = {}
SceneDialog.__index = SceneDialog

function SceneDialog:new(settings)
    local self = setmetatable({}, SceneDialog)
    self.settings = settings
    return self
end

-- Show list of AI-suggested scenes from chapter analysis (supports cached results and re-scan)
function SceneDialog:showScenePicker(scenes, chapter_title, on_select_callback, on_rescan_callback, is_cached)
    local menu_items = {}

    if on_rescan_callback then
        table.insert(menu_items, {
            text = _("🔄 Re-scan Chapter (Get New AI Scenes)"),
            help_text = _("Bypass cache and ask Gemini to analyze the chapter again."),
            callback = function()
                on_rescan_callback()
            end,
        })
    end

    for idx, scene in ipairs(scenes) do
        local title = scene.title or string.format(_("Scene #%d"), idx)
        local summary = scene.summary or ""
        local quote = scene.quote and (#scene.quote > 0) and string.format('"%s"', scene.quote) or ""
        local help = (#quote > 0) and quote or summary

        table.insert(menu_items, {
            text = string.format("✨ %s", title),
            help_text = help,
            callback = function()
                if on_select_callback then
                    on_select_callback(scene)
                end
            end,
        })
    end

    table.insert(menu_items, {
        text = _("Cancel"),
        callback = function() end,
    })

    local title_prefix = is_cached and _("⚡ Cached Scenes: ") or _("✨ AI Scenes: ")
    local picker_menu = Menu:new{
        title = title_prefix .. (chapter_title or _("Chapter")),
        item_table = menu_items,
        is_borderless = true,
    }
    UIManager:show(picker_menu)
end

-- Show list of extracted characters (Cast of Characters)
function SceneDialog:showCharacterPicker(characters, title_label, on_select_character, on_rescan_callback, is_cached)
    local menu_items = {}

    if on_rescan_callback then
        table.insert(menu_items, {
            text = _("🔄 Re-scan Cast with Gemini"),
            help_text = _("Re-analyze text to detect all characters and update profiles."),
            callback = function()
                on_rescan_callback()
            end,
        })
    end

    for idx, char in ipairs(characters) do
        local name = char.name or string.format(_("Character #%d"), idx)
        local role = char.role and (#char.role > 0) and string.format(" (%s)", char.role) or ""
        local summary = char.summary or ""
        local has_portrait = (char.has_portrait == true)
        local icon = has_portrait and "🖼️" or "🎨"
        local status_tag = has_portrait and _(" [Saved - View]") or _(" [Create Portrait]")

        table.insert(menu_items, {
            text = string.format("%s %s%s%s", icon, name, role, status_tag),
            help_text = has_portrait and (_("✅ Portrait already saved on device. Tap to view instantly!\n") .. summary) or summary,
            callback = function()
                if on_select_character then
                    on_select_character(char)
                end
            end,
        })
    end

    table.insert(menu_items, {
        text = _("Cancel"),
        callback = function() end,
    })

    local title_prefix = is_cached and _("⚡ Cached Cast: ") or _("🎭 Cast: ")
    local picker_menu = Menu:new{
        title = title_prefix .. (title_label or _("Characters")),
        item_table = menu_items,
        is_borderless = true,
    }
    UIManager:show(picker_menu)
end

-- Show Detailed Character Profile Card (Dossier) with Bio & Action Buttons
function SceneDialog:showCharacterCard(char, book_info, on_generate_callback, on_view_callback)
    local self_ref = self
    local name = char.name or _("Character")
    local role = char.role and (#char.role > 0) and char.role or _("Character")
    local summary = char.summary or _("No summary available.")
    local visual_desc = char.visual_prompt or ""
    local has_portrait = (char.has_portrait == true)

    local card_text = string.format("🎭 Uloga:\n%s\n\n📖 Opis i uloga u priči:\n%s", role, summary)

    if #visual_desc > 0 then
        local clean_vis = visual_desc:gsub("^Vertical portrait[^,]*,%s*", ""):gsub("^masterpiece[^,]*,%s*", "")
        if #clean_vis > 0 then
            card_text = card_text .. string.format("\n\n🎨 Vizuelni izgled (Koncept):\n%s", clean_vis)
        end
    end

    local dialog
    local row1 = {}

    if has_portrait then
        table.insert(row1, {
            text = _("🖼️ Prikaži Portret"),
            is_enter_default = true,
            callback = function()
                UIManager:close(dialog)
                if on_view_callback then on_view_callback(char) end
            end,
        })
        table.insert(row1, {
            text = _("🔄 Ponovo Nacrtaj (AI)"),
            callback = function()
                UIManager:close(dialog)
                if on_generate_callback then on_generate_callback(char, true) end
            end,
        })
    else
        table.insert(row1, {
            text = _("🎨 Generiši AI Portret"),
            is_enter_default = true,
            callback = function()
                UIManager:close(dialog)
                if on_generate_callback then on_generate_callback(char, false) end
            end,
        })
    end

    local row2 = {
        {
            text = _("Zatvori"),
            callback = function()
                UIManager:close(dialog)
            end,
        },
    }

    dialog = ButtonDialog:new{
        title = string.format("🎭 %s (%s)", name, role),
        text = card_text,
        buttons = {
            row1,
            row2,
        },
    }
    UIManager:show(dialog)
end

-- Show Fullscreen Image Viewer with Quick Action Buttons
function SceneDialog:showGeneratedArtwork(image_path, scene_info, book_info, on_regenerate)
    if not image_path then return end

    local title = (scene_info and scene_info.title) or _("AI Illustration")
    local self_ref = self

    -- 1. Open ImageViewer
    local viewer = ImageViewer:new{
        file = image_path,
        with_title = true,
        title = title,
    }
    UIManager:show(viewer)

    -- 2. Offer complete action dialog overlay
    self:showArtworkActions(image_path, scene_info, book_info, on_regenerate)
end

-- Comprehensive Actions Dialog for any artwork (New or from Gallery)
function SceneDialog:showArtworkActions(image_path, scene_info, book_info, on_regenerate)
    local self_ref = self
    local title = (scene_info and scene_info.title) or _("AI Illustration")
    local summary = (scene_info and scene_info.summary) or string.format(_("Saved at: %s"), image_path)

    local row1 = {
        {
            text = _("🖼️ Set as Screensaver"),
            callback = function()
                UIManager:close(dialog)
                local ok_sc, msg = self_ref:saveAsScreensaver(image_path)
                UIManager:show(InfoMessage:new{ text = msg, timeout = 3 })
            end,
        },
        {
            text = _("📖 Set as Book Cover"),
            callback = function()
                UIManager:close(dialog)
                local ok_cov, msg = self_ref:saveAsCover(image_path, book_info)
                UIManager:show(InfoMessage:new{ text = msg, timeout = 3 })
            end,
        },
    }

    local row2 = {}
    if on_regenerate then
        table.insert(row2, {
            text = _("🔄 Regenerate with AI"),
            callback = function()
                UIManager:close(dialog)
                on_regenerate()
            end,
        })
    end

    table.insert(row2, {
        text = _("💾 Export to Pictures"),
        callback = function()
            UIManager:close(dialog)
            local ok_exp, msg = self_ref:exportImage(image_path, "/mnt/us/pictures")
            UIManager:show(InfoMessage:new{ text = msg, timeout = 3 })
        end,
    })

    table.insert(row2, {
        text = _("🔍 View Fullscreen"),
        callback = function()
            UIManager:close(dialog)
            local v = ImageViewer:new{ file = image_path, with_title = true, title = title }
            UIManager:show(v)
        end,
    })

    table.insert(row2, {
        text = _("Dismiss"),
        callback = function()
            UIManager:close(dialog)
        end,
    })

    local dialog
    dialog = ButtonDialog:new{
        title = title,
        text = summary,
        buttons = {
            row1,
            row2,
        },
    }

    UIManager:scheduleIn(0.4, function()
        UIManager:show(dialog)
    end)
end

-- Copy image to Kindle screensavers directory
function SceneDialog:saveAsScreensaver(image_path)
    local target_dirs = {
        "/mnt/us/screensavers",
        "/mnt/us/koreader/screensavers",
        "/mnt/us/koreader/settings/screensavers",
    }

    local target_file = nil
    for _, dir in ipairs(target_dirs) do
        pcall(function() os.execute(string.format('mkdir -p "%s"', dir)) end)
        local f = io.open(dir .. "/test.tmp", "w")
        if f then
            f:close()
            os.remove(dir .. "/test.tmp")
            target_file = string.format("%s/gemini_art_%d.png", dir, os.time())
            break
        end
    end

    if not target_file then
        target_file = "/mnt/us/screensaver.png"
    end

    local copy_cmd = string.format('cp "%s" "%s"', image_path, target_file)
    os.execute(copy_cmd)
    return true, string.format(_("Saved to Screensavers!\n(%s)"), target_file)
end

-- Save image as book cover
function SceneDialog:saveAsCover(image_path, book_info)
    local target_dir = "/mnt/us/koreader/bookart/covers"
    pcall(function() os.execute(string.format('mkdir -p "%s"', target_dir)) end)

    local safe_title = (book_info and book_info.title or "cover"):gsub("[^%w_%-]", "_")
    local target_file = string.format("%s/%s_cover.png", target_dir, safe_title)

    local copy_cmd = string.format('cp "%s" "%s"', image_path, target_file)
    os.execute(copy_cmd)
    return true, string.format(_("Saved as Book Cover!\n(%s)"), target_file)
end

-- Export image to a destination folder (e.g. /mnt/us/pictures)
function SceneDialog:exportImage(image_path, dest_dir)
    dest_dir = dest_dir or "/mnt/us/pictures"
    pcall(function() os.execute(string.format('mkdir -p "%s"', dest_dir)) end)

    local basename = image_path:match("([^/\\]+)$") or string.format("art_%d.png", os.time())
    local target_file = string.format("%s/%s", dest_dir, basename)

    local copy_cmd = string.format('cp "%s" "%s"', image_path, target_file)
    os.execute(copy_cmd)
    return true, string.format(_("Exported image to:\n%s"), target_file)
end

-- Browse and view all previously generated illustrations
function SceneDialog:showGallery(book_info)
    local self_ref = self
    local base_dir = (self.settings and self.settings:get("save_dir")) or "/mnt/us/koreader/bookart"
    local search_dirs = {
        base_dir,
        base_dir .. "/portraits",
        base_dir .. "/covers",
    }
    local files = {}

    -- Scan directories using posix ls or lfs
    local ok_lfs, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok_lfs then ok_lfs, lfs = pcall(require, "lfs") end

    for _, sdir in ipairs(search_dirs) do
        if ok_lfs and lfs and lfs.dir then
            pcall(function()
                for fname in lfs.dir(sdir) do
                    if fname:match("%.png$") or fname:match("%.jpg$") then
                        local fpath = sdir .. "/" .. fname
                        local attr = lfs.attributes(fpath) or {}
                        table.insert(files, {
                            path = fpath,
                            name = fname,
                            mod = attr.modification or 0,
                            size = attr.size or 0,
                            sdir = sdir,
                        })
                    end
                end
            end)
        else
            local p = io.popen(string.format('ls -t "%s"/*.png "%s"/*.jpg 2>/dev/null', sdir, sdir))
            if p then
                for line in p:lines() do
                    local fpath = line:gsub("^%s+", ""):gsub("%s+$", "")
                    if #fpath > 0 then
                        local fname = fpath:match("([^/\\]+)$") or fpath
                        table.insert(files, {
                            path = fpath,
                            name = fname,
                            mod = 0,
                            size = 0,
                            sdir = sdir,
                        })
                    end
                end
                p:close()
            end
        end
    end

    table.sort(files, function(a, b) return (a.mod or 0) > (b.mod or 0) end)

    if #files == 0 then
        UIManager:show(InfoMessage:new{
            text = string.format(_("No saved illustrations found in:\n%s\n\nGenerate your first scene illustration or character portrait!"), base_dir),
            timeout = 3.5,
        })
        return
    end

    local menu_items = {}
    for idx, f in ipairs(files) do
        local date_str = (f.mod > 0) and os.date("%Y-%m-%d %H:%M", f.mod) or ""
        local sz_kb = math.floor(f.size / 1024)
        local help = (f.mod > 0) and string.format("%s (%d KB)", date_str, sz_kb) or f.path

        local prefix = "🖼️ "
        if (f.sdir and f.sdir:find("/portraits")) or f.name:match("^char_") then
            prefix = "🎭 [Portrait] "
        elseif (f.sdir and f.sdir:find("/covers")) or f.name:match("_cover%.png$") then
            prefix = "📖 [Cover] "
        end

        table.insert(menu_items, {
            text = string.format("%s%s", prefix, f.name),
            help_text = help,
            callback = function()
                local scene_info = {
                    title = f.name,
                    summary = string.format("Path: %s\nDate: %s", f.path, date_str),
                }
                self_ref:showArtworkActions(f.path, scene_info, book_info)
            end,
        })
    end

    table.insert(menu_items, {
        text = _("Close Gallery"),
        callback = function() end,
    })

    local gallery_menu = Menu:new{
        title = string.format(_("📁 Saved Illustrations (%d)"), #files),
        item_table = menu_items,
        is_borderless = true,
    }
    UIManager:show(gallery_menu)
end

-- Show input dialog for custom page range (e.g. "12-24")
function SceneDialog:showPageRangeDialog(cur_page, on_confirm_callback)
    local dialog
    dialog = InputDialog:new{
        title = _("Scan Custom Page Range"),
        description = _("Enter page range to analyze (e.g. 15-28 or 10):"),
        input = string.format("%d-%d", math.max(1, cur_page - 2), cur_page + 8),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function() UIManager:close(dialog) end,
                },
                {
                    text = _("Analyze with Gemini"),
                    is_enter_default = true,
                    callback = function()
                        local input_str = dialog:getInputText()
                        UIManager:close(dialog)

                        local s_p, e_p = input_str:match("(%d+)%s*-%s*(%d+)")
                        if not s_p then
                            s_p = input_str:match("(%d+)")
                            e_p = s_p
                        end

                        s_p = tonumber(s_p) or cur_page
                        e_p = tonumber(e_p) or (s_p + 10)

                        if on_confirm_callback then
                            on_confirm_callback(s_p, e_p)
                        end
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

return SceneDialog
