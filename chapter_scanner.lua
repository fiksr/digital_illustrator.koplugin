--[[--
Chapter & Document Scanner for KOReader.
Extracts book metadata, current chapter text via TOC/XPointers, custom page ranges, and screen text across EPUB, MOBI, PDF, and DjVu formats.
--]]--

local Device = require("device")
local logger = require("logger")
local Screen = Device.screen

local Scanner = {}
Scanner.__index = Scanner

function Scanner:new()
    local self = setmetatable({}, Scanner)
    return self
end

-- Safely resolve active ReaderUI document context
local function resolveReaderUI(ui)
    if ui and ui.document then return ui end

    -- Try ReaderUI singleton
    local ok_rui, ReaderUI = pcall(require, "apps/reader/readerui")
    if ok_rui and ReaderUI and ReaderUI.instance and ReaderUI.instance.document then
        return ReaderUI.instance
    end

    -- Try top active widget in UIManager
    local ok_uim, UIManager = pcall(require, "ui/uimanager")
    if ok_uim and UIManager then
        local top = UIManager:getTopWidget()
        if top and top.document then return top end
        if top and top.ui and top.ui.document then return top.ui end
    end

    return ui
end

-- Extract metadata for current book (Title, Author, Description)
function Scanner:getBookInfo(ui)
    ui = resolveReaderUI(ui)
    if not ui or not ui.document then
        return {
            title = "Current Book",
            author = "Unknown Author",
            description = "",
        }
    end

    local doc = ui.document
    local props = doc.getProps and doc:getProps() or {}

    local title = props.title
    if not title or #title == 0 then
        if doc.file then
            title = doc.file:match("([^/\\]+)%.[^%.]+$") or doc.file
        else
            title = "Book"
        end
    end

    local author = props.authors or props.author or ""
    local description = props.description or props.comment or ""

    return {
        title = tostring(title),
        author = tostring(author),
        description = tostring(description),
    }
end

-- Extract text of the currently visible screen page (supports CREngine and MuPDF)
function Scanner:getCurrentPageText(ui)
    ui = resolveReaderUI(ui)
    if not ui or not ui.document then return "" end

    local doc = ui.document

    -- 1. CREngine (EPUB, MOBI, FB2, AZW3): getTextFromPositions across screen dimensions
    if doc.getTextFromPositions then
        local w = Screen and Screen:getWidth() or 1272
        local h = Screen and Screen:getHeight() or 1696
        local ok, res = pcall(doc.getTextFromPositions, doc, { x = 0, y = 0 }, { x = w, y = h }, true)
        if ok and res then
            if type(res) == "table" and res.text and #res.text > 0 then
                return res.text:gsub("^%s+", ""):gsub("%s+$", "")
            elseif type(res) == "string" and #res > 0 then
                return res:gsub("^%s+", ""):gsub("%s+$", "")
            end
        end
    end

    -- 2. MuPDF / PDF / DjVu: getTextBoxes
    local cur_page = (ui.getCurrentPage and ui:getCurrentPage()) or (ui.view and ui.view.state and ui.view.state.page) or 1
    if doc.getTextBoxes then
        local ok, page_boxes = pcall(doc.getTextBoxes, doc, cur_page)
        if ok and page_boxes and type(page_boxes) == "table" and #page_boxes > 0 then
            local lines = {}
            for _, line in ipairs(page_boxes) do
                local words = {}
                for _, word_item in ipairs(line) do
                    if word_item.word and #word_item.word > 0 then
                        table.insert(words, word_item.word)
                    end
                end
                if #words > 0 then
                    table.insert(lines, table.concat(words, " "))
                end
            end
            if #lines > 0 then
                return table.concat(lines, "\n")
            end
        end
    end

    -- 3. Fallback: getPageText
    if doc.getPageText then
        local ok, txt = pcall(doc.getPageText, doc, cur_page)
        if ok and txt and #txt > 0 then
            return txt:gsub("^%s+", ""):gsub("%s+$", "")
        end
    end

    return ""
end

-- Locate current chapter text (using fast CreDocument XPointers or TOC page ranges)
function Scanner:getCurrentChapterText(ui)
    ui = resolveReaderUI(ui)
    if not ui or not ui.document then
        return "", 1, 1, "Current Chapter"
    end

    local doc = ui.document
    local cur_page = (ui.getCurrentPage and ui:getCurrentPage()) or (ui.view and ui.view.state and ui.view.state.page) or 1
    local total_pages = (doc.getPageCount and doc:getPageCount()) or cur_page

    local toc = doc.getToc and doc:getToc() or nil
    local chapter_title = "Chapter"
    local start_page = cur_page
    local end_page = cur_page

    -- 1. If TOC is available, locate current chapter entry
    if toc and type(toc) == "table" and #toc > 0 then
        local entries = {}
        local function flatten(items)
            for _, item in ipairs(items) do
                if item.page or item.xpointer then
                    table.insert(entries, {
                        title = item.title or "Chapter",
                        page = item.page or 1,
                        xpointer = item.xpointer
                    })
                end
                if item.subitems and #item.subitems > 0 then
                    flatten(item.subitems)
                end
            end
        end
        flatten(toc)

        table.sort(entries, function(a, b) return (a.page or 1) < (b.page or 1) end)

        local current_entry_idx = nil
        for i, entry in ipairs(entries) do
            if entry.page <= cur_page then
                current_entry_idx = i
            else
                break
            end
        end

        if current_entry_idx then
            local cur_entry = entries[current_entry_idx]
            local next_entry = entries[current_entry_idx + 1]

            chapter_title = cur_entry.title
            start_page = cur_entry.page or cur_page
            end_page = next_entry and (next_entry.page - 1) or math.min(start_page + 20, total_pages)

            -- Fast CREngine DOM extraction via XPointers
            if doc.getTextFromXPointers and cur_entry.xpointer then
                local next_xp = next_entry and next_entry.xpointer or nil
                if not next_xp and doc.getXPointerForPage then
                    next_xp = doc:getXPointerForPage(end_page)
                end

                if next_xp then
                    local ok, ch_text = pcall(doc.getTextFromXPointers, doc, cur_entry.xpointer, next_xp, false)
                    if ok and ch_text and #ch_text > 50 then
                        return ch_text, start_page, end_page, chapter_title
                    end
                end
            end
        end
    end

    -- 2. Fallback: Extract current page + surrounding pages
    local current_page_text = self:getCurrentPageText(ui)
    if #current_page_text > 0 then
        return current_page_text, cur_page, cur_page, string.format("Page %d (%s)", cur_page, chapter_title)
    end

    return "", cur_page, cur_page, "Current Page"
end

-- Extract text for a specified range of pages (e.g. 15 to 25 or 1 to 500)
function Scanner:getPageRangeText(ui, start_page, end_page)
    ui = resolveReaderUI(ui)
    if not ui or not ui.document then return "", start_page, end_page end

    local doc = ui.document
    local total_pages = (doc.getPageCount and doc:getPageCount()) or 1000

    start_page = math.max(1, math.min(start_page, total_pages))
    end_page = math.max(start_page, math.min(end_page, total_pages))

    -- 1. Fast extraction for CREngine (EPUB, MOBI, FB2, AZW3) via XPointers
    if doc.getTextFromXPointers and doc.getXPointerForPage then
        local xp0 = doc:getXPointerForPage(start_page)
        local xp1 = doc:getXPointerForPage(math.min(end_page + 1, total_pages))
        if xp0 and xp1 then
            local ok, txt = pcall(doc.getTextFromXPointers, doc, xp0, xp1, false)
            if ok and txt and #txt > 0 then
                return txt, start_page, end_page
            end
        end
    end

    -- 2. Fallback for MuPDF, PDF, DjVu: page-by-page text extraction
    if doc.getPageText or doc.getTextBoxes then
        local collected = {}
        for p = start_page, end_page do
            local p_txt = ""
            if doc.getPageText then
                local ok, txt = pcall(doc.getPageText, doc, p)
                if ok and txt and #txt > 0 then
                    p_txt = txt
                end
            end
            if #p_txt == 0 and doc.getTextBoxes then
                local ok, boxes = pcall(doc.getTextBoxes, doc, p)
                if ok and boxes and type(boxes) == "table" then
                    local lines = {}
                    for _, line in ipairs(boxes) do
                        local words = {}
                        for _, word_item in ipairs(line) do
                            if word_item.word and #word_item.word > 0 then
                                table.insert(words, word_item.word)
                            end
                        end
                        if #words > 0 then
                            table.insert(lines, table.concat(words, " "))
                        end
                    end
                    p_txt = table.concat(lines, "\n")
                end
            end
            if #p_txt > 0 then
                table.insert(collected, p_txt)
            end
        end
        if #collected > 0 then
            return table.concat(collected, "\n\n"), start_page, end_page
        end
    end

    -- 3. Final Fallback: Use current page text
    local txt = self:getCurrentPageText(ui)
    return txt, start_page, end_page
end

-- Extract all text from page 1 up to current page (for full book cast analysis)
function Scanner:getTextUpToCurrentPage(ui)
    ui = resolveReaderUI(ui)
    if not ui or not ui.document then return "" end

    local doc = ui.document
    local cur_page = (ui.getCurrentPage and ui:getCurrentPage()) or (ui.view and ui.view.state and ui.view.state.page) or 1
    local total_pages = (doc.getPageCount and doc:getPageCount()) or cur_page

    cur_page = math.max(1, math.min(cur_page, total_pages))

    -- Fast extraction via XPointers
    if doc.getTextFromXPointers and doc.getXPointerForPage then
        local xp0 = doc:getXPointerForPage(1)
        local xp1 = doc:getXPointerForPage(cur_page + 1) or doc:getXPointerForPage(cur_page)
        if xp0 and xp1 then
            local ok, txt = pcall(doc.getTextFromXPointers, doc, xp0, xp1, false)
            if ok and txt and #txt > 0 then
                return txt, 1, cur_page
            end
        end
    end

    -- Fallback: Get page range text
    local txt, s_p, e_p = self:getPageRangeText(ui, 1, cur_page)
    return txt, s_p, e_p
end

return Scanner
