--[[--
Chapter & Document Scanner for KOReader.
Extracts book metadata, current chapter text via TOC, custom page ranges, and single page excerpts.
--]]--

local logger = require("logger")

local Scanner = {}
Scanner.__index = Scanner

function Scanner:new()
    local self = setmetatable({}, Scanner)
    return self
end

-- Extract metadata for current book (Title, Author, Description, Series)
function Scanner:getBookInfo(ui)
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
        -- Fallback to filename
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

-- Safely extract text from a single page
function Scanner:getPageText(ui, page_num)
    if not ui or not ui.document then return "" end
    local doc = ui.document

    -- Method 1: getPageText
    if doc.getPageText then
        local ok, txt = pcall(doc.getPageText, doc, page_num)
        if ok and txt and #txt > 0 then
            return txt
        end
    end

    -- Method 2: getTextFromPositions
    if doc.getTextFromPositions and doc.getPagePositions then
        local ok, pos = pcall(doc.getPagePositions, doc, page_num)
        if ok and pos and pos.start_pos and pos.end_pos then
            local ok_t, txt = pcall(doc.getTextFromPositions, doc, pos.start_pos, pos.end_pos)
            if ok_t and txt and #txt > 0 then
                return txt
            end
        end
    end

    return ""
end

-- Extract text of the currently open page
function Scanner:getCurrentPageText(ui)
    if not ui or not ui.view or not ui.view.state then return "" end
    local cur_page = ui.view.state.page or 1
    return self:getPageText(ui, cur_page)
end

-- Extract text for a specified range of pages (e.g. 15 to 25)
function Scanner:getPageRangeText(ui, start_page, end_page)
    if not ui or not ui.document then return "" end
    local total_pages = (ui.document.getPageCount and ui.document:getPageCount()) or 1000

    start_page = math.max(1, math.min(start_page, total_pages))
    end_page = math.max(start_page, math.min(end_page, total_pages))

    local text_parts = {}
    for p = start_page, end_page do
        local page_str = self:getPageText(ui, p)
        if #page_str > 0 then
            table.insert(text_parts, page_str)
        end
        -- Keep total text within reasonable memory limits
        if #text_parts > 50 then break end
    end

    return table.concat(text_parts, "\n\n"), start_page, end_page
end

-- Locate current chapter bounds using Table of Contents (TOC) and extract chapter text
function Scanner:getCurrentChapterText(ui)
    if not ui or not ui.document or not ui.view or not ui.view.state then
        return "", 1, 1, "Current Chapter"
    end

    local doc = ui.document
    local cur_page = ui.view.state.page or 1
    local total_pages = (doc.getPageCount and doc:getPageCount()) or cur_page

    local toc = doc.getToc and doc:getToc() or nil
    local chapter_title = "Chapter"
    local start_page = cur_page
    local end_page = cur_page

    if toc and type(toc) == "table" and #toc > 0 then
        -- Flatten TOC to find chapter surrounding cur_page
        local entries = {}
        local function flatten(items)
            for _, item in ipairs(items) do
                if item.page then
                    table.insert(entries, { title = item.title or "Chapter", page = item.page })
                end
                if item.subitems and #item.subitems > 0 then
                    flatten(item.subitems)
                end
            end
        end
        flatten(toc)

        table.sort(entries, function(a, b) return a.page < b.page end)

        local current_entry_idx = nil
        for i, entry in ipairs(entries) do
            if entry.page <= cur_page then
                current_entry_idx = i
            else
                break
            end
        end

        if current_entry_idx then
            local entry = entries[current_entry_idx]
            chapter_title = entry.title
            start_page = entry.page
            if entries[current_entry_idx + 1] then
                end_page = math.max(start_page, entries[current_entry_idx + 1].page - 1)
            else
                end_page = math.min(start_page + 25, total_pages)
            end
        end
    end

    -- Fallback if no TOC found or single chapter: take 15-page window around current page
    if start_page == end_page then
        start_page = math.max(1, cur_page - 2)
        end_page = math.min(total_pages, cur_page + 10)
        chapter_title = string.format("Pages %d - %d", start_page, end_page)
    end

    -- Extract text
    local text, s_p, e_p = self:getPageRangeText(ui, start_page, end_page)
    return text, s_p, e_p, chapter_title
end

return Scanner
