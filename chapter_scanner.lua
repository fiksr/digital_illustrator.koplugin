--[[--
Chapter & Document Scanner for KOReader.
Extracts book metadata, full book text, current chapter text, custom page ranges,
and screen text across EPUB, MOBI, AZW3, FB2, TXT, PDF, and DjVu formats.
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

-- Standard and Serbian/Cyrillic/Latin HTML entity table
local HTML_ENTITIES = {
    ["&nbsp;"] = " ",
    ["&amp;"] = "&",
    ["&lt;"] = "<",
    ["&gt;"] = ">",
    ["&quot;"] = '"',
    ["&apos;"] = "'",
    ["&#39;"] = "'",
    ["&mdash;"] = "—",
    ["&ndash;"] = "–",
    ["&hellip;"] = "…",
    ["&lsquo;"] = "'",
    ["&rsquo;"] = "'",
    ["&ldquo;"] = '"',
    ["&rdquo;"] = '"',
    ["&scaron;"] = "š",
    ["&Scaron;"] = "Š",
    ["&ccaron;"] = "č",
    ["&Ccaron;"] = "Č",
    ["&cacute;"] = "ć",
    ["&Cacute;"] = "Ć",
    ["&zcaron;"] = "ž",
    ["&Zcaron;"] = "Ž",
    ["&dstrok;"] = "đ",
    ["&Dstrok;"] = "Đ",
}

-- Convert Unicode codepoints to valid UTF-8 byte sequences
local function codepointToUtf8(cp)
    if cp < 128 then
        return string.char(cp)
    elseif cp < 2048 then
        return string.char(192 + math.floor(cp / 64), 128 + (cp % 64))
    elseif cp < 65536 then
        return string.char(
            224 + math.floor(cp / 4096),
            128 + (math.floor(cp / 64) % 64),
            128 + (cp % 64)
        )
    elseif cp < 1114112 then
        return string.char(
            240 + math.floor(cp / 262144),
            128 + (math.floor(cp / 4096) % 64),
            128 + (math.floor(cp / 64) % 64),
            128 + (cp % 64)
        )
    end
    return " "
end

-- Clean HTML/XML tags and decode entities into clean text
function Scanner:cleanHtmlText(raw_html)
    if not raw_html or #raw_html == 0 then return "" end

    local txt = raw_html

    pcall(function()
        -- Strip HTML comments: <!%-%-.-%-%->
        txt = txt:gsub("<!%-%-.-%-%->", " ")
        -- Strip script, style, head blocks
        txt = txt:gsub("<[sS][cC][rR][iI][pP][tT].-</[sS][cC][rR][iI][pP][tT]>", " ")
        txt = txt:gsub("<[sS][tT][yY][lL][eE].-</[sS][tT][yY][lL][eE]>", " ")
        txt = txt:gsub("<[hH][eE][aA][dD].-</[hH][eE][aA][dD]>", " ")
        -- Replace block tags with newlines for natural sentence flow
        txt = txt:gsub("<[pP][^>]*>", "\n")
        txt = txt:gsub("<[bB][rR][^>]*>", "\n")
        txt = txt:gsub("<[hH][1-6][^>]*>", "\n\n")
        txt = txt:gsub("<[dD][iI][vV][^>]*>", "\n")
        -- Strip all remaining tags
        txt = txt:gsub("<[^>]+>", " ")
    end)

    -- Decode named HTML entities
    pcall(function()
        for ent, val in pairs(HTML_ENTITIES) do
            txt = txt:gsub(ent, val)
        end
    end)

    -- Decode decimal entities &#269;
    pcall(function()
        txt = txt:gsub("&#([0-9]+);", function(c)
            local n = tonumber(c)
            if n then return codepointToUtf8(n) end
            return " "
        end)
    end)

    -- Decode hex entities &#x10d;
    pcall(function()
        txt = txt:gsub("&#x([0-9a-fA-F]+);", function(c)
            local n = tonumber(c, 16)
            if n then return codepointToUtf8(n) end
            return " "
        end)
    end)

    -- Normalize multiple spaces and excess blank lines
    pcall(function()
        txt = txt:gsub("[ \t\r\f]+", " ")
        txt = txt:gsub("\n%s*\n+", "\n\n")
    end)

    return txt:gsub("^%s+", ""):gsub("%s+$", "")
end

-- Extract metadata for current book (Title, Author, Description, Filepath)
function Scanner:getBookInfo(ui)
    ui = resolveReaderUI(ui)
    if not ui or not ui.document then
        return {
            title = "Current Book",
            author = "Unknown Author",
            description = "",
            filepath = "",
            total_pages = 1,
            cur_page = 1,
        }
    end

    local doc = ui.document
    local props = doc.getProps and doc:getProps() or {}
    local filepath = doc.file or ""

    local title = props.title
    if not title or #title == 0 then
        if #filepath > 0 then
            title = filepath:match("([^/\\]+)%.[^%.]+$") or filepath
        else
            title = "Book"
        end
    end

    local author = props.authors or props.author or ""
    local description = props.description or props.comment or ""
    local cur_page = (ui.getCurrentPage and ui:getCurrentPage()) or (ui.view and ui.view.state and ui.view.state.page) or 1
    local total_pages = (doc.getPageCount and doc:getPageCount()) or cur_page

    return {
        title = tostring(title),
        author = tostring(author),
        description = tostring(description),
        filepath = filepath,
        total_pages = total_pages,
        cur_page = cur_page,
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

-- Direct EPUB text extraction via built-in system unzip (Kindle / Linux / Android)
function Scanner:extractEpubText(filepath, max_chars)
    if not filepath or #filepath == 0 then return "" end
    max_chars = max_chars or 2000000

    -- Try targeting xhtml / html files first
    local cmd = string.format('unzip -p "%s" "*.xhtml" "*.html" "*.htm" "*/*.xhtml" "*/*.html" "*/*.htm" "*/*/*.xhtml" "*/*/*.html" 2>/dev/null', filepath)
    local handle = io.popen(cmd)
    local raw_data = handle and handle:read("*a")
    if handle then handle:close() end

    -- Fallback to extracting all files if pattern missed
    if not raw_data or #raw_data < 200 then
        local cmd_all = string.format('unzip -p "%s" 2>/dev/null', filepath)
        local h_all = io.popen(cmd_all)
        raw_data = h_all and h_all:read("*a")
        if h_all then h_all:close() end
    end

    if raw_data and #raw_data > 100 then
        local clean = self:cleanHtmlText(raw_data)
        if #clean > 100 then
            return clean:sub(1, max_chars)
        end
    end

    return ""
end

-- Direct FB2 text extraction (uncompressed or zipped)
function Scanner:extractFb2Text(filepath, max_chars)
    if not filepath or #filepath == 0 then return "" end
    max_chars = max_chars or 2000000

    local raw_data = ""
    if filepath:match("%.fb2%.zip$") or filepath:match("%.zip$") then
        local cmd = string.format('unzip -p "%s" "*.fb2" "*.xml" 2>/dev/null', filepath)
        local handle = io.popen(cmd)
        if handle then
            raw_data = handle:read("*a")
            handle:close()
        end
    else
        local f = io.open(filepath, "r")
        if f then
            raw_data = f:read("*a")
            f:close()
        end
    end

    if raw_data and #raw_data > 100 then
        local clean = self:cleanHtmlText(raw_data)
        if #clean > 100 then
            return clean:sub(1, max_chars)
        end
    end

    return ""
end

-- Direct TXT file reading
function Scanner:extractTxtText(filepath, max_chars)
    if not filepath or #filepath == 0 then return "" end
    max_chars = max_chars or 2000000

    local f = io.open(filepath, "r")
    if not f then return "" end
    local content = f:read(max_chars)
    f:close()
    return content or ""
end

-- Decompress PalmDoc LZ77 chunk (for MOBI / AZW / PRC)
local function decompressPalmDocChunk(data)
    local out = {}
    local out_len = 0
    local i = 1
    local len = #data
    while i <= len do
        local byte = string.byte(data, i)
        i = i + 1
        if byte >= 1 and byte <= 8 then
            local chunk = string.sub(data, i, i + byte - 1)
            table.insert(out, chunk)
            out_len = out_len + #chunk
            i = i + byte
        elseif byte <= 0x7f then
            table.insert(out, string.char(byte))
            out_len = out_len + 1
        elseif byte >= 0xc0 then
            local ch = string.char(byte - 0x80)
            table.insert(out, " " .. ch)
            out_len = out_len + 2
        elseif byte >= 0x80 and byte <= 0xbf then
            if i <= len then
                local next_byte = string.byte(data, i)
                i = i + 1
                local pair = (byte - 0x80) * 256 + next_byte
                local distance = math.floor(pair / 8)
                local length = (pair % 8) + 3
                if distance > 0 and distance <= out_len then
                    local full_text = table.concat(out)
                    local start_pos = #full_text - distance + 1
                    local chunk = string.sub(full_text, start_pos, start_pos + length - 1)
                    table.insert(out, chunk)
                    out_len = out_len + #chunk
                end
            end
        end
    end
    return table.concat(out)
end

-- Direct MOBI / AZW PalmDoc record parser in pure Lua
function Scanner:extractMobiText(filepath, max_chars)
    if not filepath or #filepath == 0 then return "" end
    max_chars = max_chars or 2000000

    -- Try KF8 / AZW3 unzip first
    local ep_txt = self:extractEpubText(filepath, max_chars)
    if #ep_txt > 500 then
        return ep_txt
    end

    local f = io.open(filepath, "rb")
    if not f then return "" end

    -- Read PalmDB header
    f:seek("set", 76)
    local rec_count_bytes = f:read(2)
    if not rec_count_bytes or #rec_count_bytes < 2 then
        f:close()
        return ""
    end

    local num_records = string.byte(rec_count_bytes, 1) * 256 + string.byte(rec_count_bytes, 2)
    if num_records < 2 or num_records > 15000 then
        f:close()
        return ""
    end

    -- Read record offset list
    local offsets = {}
    for r = 1, num_records do
        local rec_info = f:read(8)
        if not rec_info or #rec_info < 8 then break end
        local off = string.byte(rec_info, 1) * 16777216 +
                    string.byte(rec_info, 2) * 65536 +
                    string.byte(rec_info, 3) * 256 +
                    string.byte(rec_info, 4)
        table.insert(offsets, off)
    end

    if #offsets < 2 then
        f:close()
        return ""
    end

    -- Read Record 0 (PalmDoc header)
    f:seek("set", offsets[1])
    local r0_len = offsets[2] - offsets[1]
    local r0 = f:read(math.min(r0_len, 100))
    if not r0 or #r0 < 10 then
        f:close()
        return ""
    end

    local compression = string.byte(r0, 1) * 256 + string.byte(r0, 2)
    local text_rec_count = string.byte(r0, 9) * 256 + string.byte(r0, 10)
    if text_rec_count <= 0 or text_rec_count > num_records then
        text_rec_count = math.min(num_records - 1, 1000)
    end

    local collected_chunks = {}
    local total_len = 0

    for r = 2, math.min(text_rec_count + 1, #offsets) do
        local start_off = offsets[r]
        local end_off = offsets[r + 1] or (start_off + 4096)
        local rec_len = end_off - start_off
        if rec_len > 0 and rec_len < 100000 then
            f:seek("set", start_off)
            local rec_data = f:read(rec_len)
            if rec_data and #rec_data > 0 then
                local chunk_text = ""
                if compression == 1 then
                    chunk_text = rec_data
                elseif compression == 2 then
                    chunk_text = decompressPalmDocChunk(rec_data)
                end
                if #chunk_text > 0 then
                    table.insert(collected_chunks, chunk_text)
                    total_len = total_len + #chunk_text
                    if total_len >= max_chars then break end
                end
            end
        end
    end
    f:close()

    if #collected_chunks > 0 then
        local raw = table.concat(collected_chunks)
        local clean = self:cleanHtmlText(raw)
        if #clean > 100 then
            return clean:sub(1, max_chars)
        end
    end

    return ""
end

-- PDF / DjVu page-by-page text extraction
function Scanner:extractPdfText(doc, start_page, end_page)
    if not doc then return "" end
    start_page = math.max(1, start_page or 1)
    end_page = math.max(start_page, end_page or start_page)

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

    return table.concat(collected, "\n\n")
end

-- Extract chapters text using CreDocument TOC XPointers
function Scanner:extractTocChaptersText(doc, toc, up_to_page)
    if not doc or not doc.getTextFromXPointers or not toc or #toc == 0 then
        return ""
    end

    local entries = {}
    local function flatten(items)
        for _, item in ipairs(items) do
            if item.xpointer or item.page then
                table.insert(entries, {
                    title = item.title or "Chapter",
                    page = item.page or 1,
                    xpointer = item.xpointer,
                })
            end
            if item.subitems and #item.subitems > 0 then
                flatten(item.subitems)
            end
        end
    end
    flatten(toc)
    table.sort(entries, function(a, b) return (a.page or 1) < (b.page or 1) end)

    local collected = {}
    for i = 1, #entries do
        local cur_e = entries[i]
        local next_e = entries[i + 1]
        if up_to_page and cur_e.page and cur_e.page > up_to_page then
            break
        end

        if cur_e.xpointer and next_e and next_e.xpointer then
            local ok, txt = pcall(doc.getTextFromXPointers, doc, cur_e.xpointer, next_e.xpointer, false)
            if ok and txt and #txt > 0 then
                table.insert(collected, txt)
            end
        end
    end

    return table.concat(collected, "\n\n")
end

-- Locate current chapter text (using TOC XPointers or direct file slice)
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
                        xpointer = item.xpointer,
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
            end_page = next_entry and (next_entry.page - 1) or math.min(start_page + 25, total_pages)

            -- Fast CREngine DOM extraction via XPointers
            if doc.getTextFromXPointers and cur_entry.xpointer and next_entry and next_entry.xpointer then
                local ok, ch_text = pcall(doc.getTextFromXPointers, doc, cur_entry.xpointer, next_entry.xpointer, false)
                if ok and ch_text and #ch_text > 50 then
                    return ch_text, start_page, end_page, chapter_title
                end
            end
        end
    end

    -- 2. Fallback: Proportional slice of book text for this chapter range
    local full_txt, s_p, e_p = self:getPageRangeText(ui, start_page, end_page)
    if #full_txt > 50 then
        return full_txt, start_page, end_page, chapter_title
    end

    -- 3. Last Fallback: Extract current screen page text
    local current_page_text = self:getCurrentPageText(ui)
    return current_page_text, cur_page, cur_page, string.format("Page %d (%s)", cur_page, chapter_title)
end

-- Extract text for a specified range of pages (e.g. 15 to 25 or 1 to 500)
function Scanner:getPageRangeText(ui, start_page, end_page)
    ui = resolveReaderUI(ui)
    if not ui or not ui.document then return "", start_page, end_page end

    local doc = ui.document
    local filepath = doc.file or ""
    local total_pages = (doc.getPageCount and doc:getPageCount()) or 1000

    start_page = math.max(1, math.min(start_page, total_pages))
    end_page = math.max(start_page, math.min(end_page, total_pages))

    -- 1. PDF / DjVu page-by-page extraction
    if doc.getPageText or doc.getTextBoxes then
        local pdf_txt = self:extractPdfText(doc, start_page, end_page)
        if #pdf_txt > 50 then
            return pdf_txt, start_page, end_page
        end
    end

    -- 2. Extract full text from file and slice proportionally to page range
    local full_book_text = ""
    local ext = filepath:match("%.([%w_]+)$") and filepath:match("%.([%w_]+)$"):lower() or ""

    if ext == "epub" then
        full_book_text = self:extractEpubText(filepath, 2000000)
    elseif ext == "fb2" or ext == "zip" then
        full_book_text = self:extractFb2Text(filepath, 2000000)
    elseif ext == "mobi" or ext == "azw" or ext == "azw3" or ext == "prc" then
        full_book_text = self:extractMobiText(filepath, 2000000)
    elseif ext == "txt" then
        full_book_text = self:extractTxtText(filepath, 2000000)
    end

    -- If direct file extraction was successful, slice by page proportion
    if full_book_text and #full_book_text > 100 then
        if start_page <= 1 and end_page >= total_pages then
            return full_book_text, start_page, end_page
        end

        local total_chars = #full_book_text
        local start_char = math.max(1, math.floor(total_chars * ((start_page - 1) / total_pages)) + 1)
        local end_char = math.min(total_chars, math.floor(total_chars * (end_page / total_pages)))
        local slice = full_book_text:sub(start_char, end_char)
        if #slice > 50 then
            return slice, start_page, end_page
        end
    end

    -- 3. TOC XPointers extraction
    local toc = doc.getToc and doc:getToc() or nil
    if toc and type(toc) == "table" and #toc > 0 then
        local toc_text = self:extractTocChaptersText(doc, toc, end_page)
        if #toc_text > 50 then
            return toc_text, start_page, end_page
        end
    end

    -- 4. Final Fallback: Use current page text
    local txt = self:getCurrentPageText(ui)
    return txt, start_page, end_page
end

-- Extract all text from page 1 up to current page (for comprehensive full book cast analysis)
function Scanner:getTextUpToCurrentPage(ui)
    ui = resolveReaderUI(ui)
    if not ui or not ui.document then return "" end

    local doc = ui.document
    local filepath = doc.file or ""
    local cur_page = (ui.getCurrentPage and ui:getCurrentPage()) or (ui.view and ui.view.state and ui.view.state.page) or 1
    local total_pages = (doc.getPageCount and doc:getPageCount()) or cur_page
    cur_page = math.max(1, math.min(cur_page, total_pages))

    local ext = filepath:match("%.([%w_]+)$") and filepath:match("%.([%w_]+)$"):lower() or ""
    local full_text = ""

    -- 1. Direct file extraction based on format
    if ext == "epub" then
        full_text = self:extractEpubText(filepath, 2000000)
    elseif ext == "fb2" or ext == "zip" then
        full_text = self:extractFb2Text(filepath, 2000000)
    elseif ext == "mobi" or ext == "azw" or ext == "azw3" or ext == "prc" then
        full_text = self:extractMobiText(filepath, 2000000)
    elseif ext == "txt" then
        full_text = self:extractTxtText(filepath, 2000000)
    elseif ext == "pdf" or ext == "djvu" or doc.getPageText or doc.getTextBoxes then
        full_text = self:extractPdfText(doc, 1, cur_page)
    end

    -- If full text was extracted from file:
    if full_text and #full_text > 100 then
        -- If current reading position is at or near the end of the book, take all of it
        if cur_page >= total_pages or cur_page >= (total_pages * 0.85) then
            return full_text, 1, cur_page
        end
        -- Otherwise take up to the current reading progress
        local target_chars = math.max(1000, math.floor(#full_text * (cur_page / total_pages)))
        return full_text:sub(1, target_chars), 1, cur_page
    end

    -- 2. CreDocument TOC XPointers extraction
    local toc = doc.getToc and doc:getToc() or nil
    if toc and type(toc) == "table" and #toc > 0 then
        local toc_text = self:extractTocChaptersText(doc, toc, cur_page)
        if #toc_text > 100 then
            return toc_text, 1, cur_page
        end
    end

    -- 3. Fallback: Page range text
    local range_txt, s_p, e_p = self:getPageRangeText(ui, 1, cur_page)
    if #range_txt > 50 then
        return range_txt, s_p, e_p
    end

    -- 4. Absolute Fallback: Current page text
    return self:getCurrentPageText(ui), 1, cur_page
end

return Scanner
