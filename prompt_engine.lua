--[[--
Smart Prompt Engine for Gemini AI Book Illustrator.
Constructs genre-aware, context-rich prompts optimized for monochrome E-Ink rendering.
--]]--

local PromptEngine = {}
PromptEngine.__index = PromptEngine

local STYLE_MODIFIERS = {
    engraving = "Victorian book illustration style, detailed copperplate engraving and ink etching, intricate cross-hatching, in the style of Gustave Doré and Albrecht Dürer, sharp black ink lines on off-white paper, high contrast, masterpiece.",
    comic_noir = "Graphic novel illustration style, dramatic comic noir ink drawing, heavy chiaroscuro lighting, bold ink shadows, crisp silhouettes, Frank Miller and Mike Mignola graphic novel aesthetic, monochromatic, high contrast.",
    woodcut = "Vintage woodblock and woodcut print style, bold folkloric lines, traditional relief printmaking aesthetic, stark monochromatic contrast, historic medieval and early modern woodcut art.",
    charcoal_sketch = "Detailed academic charcoal and graphite drawing, fine tonal gradients, textured paper grain, atmospheric sfumato shading, realistic classical book illustration, monochrome.",
    cinematic_bw = "Cinematic 35mm black and white photography still, dramatic film lighting, rich grayscale depth, Hasselblad monochrome portraiture, sharp focus, deep shadows and crisp highlights.",
    auto_genre = "", -- Dynamically determined by Gemini based on book context
}

function PromptEngine:new(settings)
    local self = setmetatable({}, PromptEngine)
    self.settings = settings
    return self
end

-- Builds prompt for Chapter / Excerpt Analysis (returns JSON with 3-4 scenes)
function PromptEngine:buildAnalysisSystemInstruction(book_info)
    local title = (book_info and book_info.title) or "Unknown Book"
    local author = (book_info and book_info.author) or "Unknown Author"
    local description = (book_info and book_info.description) or ""
    local style_pref = self.settings:get("art_style") or "auto_genre"
    local style_note = STYLE_MODIFIERS[style_pref] or ""

    local prompt = string.format([[
You are an elite literary visualizer and art director for luxury book illustrations.
The user is reading "%s" by %s. %s

Your mission:
1. Analyze the provided book excerpt/chapter, its overarching genre (e.g. Sci-Fi, Dark Fantasy, Cyberpunk, Gothic Horror, Historical Drama, Noir, Classic Romance, Thriller), mood, and visual aesthetics.
2. Identify 3 to 4 distinct, visually stunning, dramatic, or iconic moments from the text.
3. For each moment, craft a rich, highly specific visual prompt for an image generation model.
4. The visual prompt must be tailor-made for high-contrast, black-and-white E-Ink screen viewing:
   - Strong focal point and clear character/environment silhouettes.
   - Dynamic lighting (chiaroscuro, moonlight, neon reflections in grayscale, dramatic backlighting).
   - %s
   - Explicitly avoid muddy grays, washed-out colors, or generic flat lighting.

Output STRICTLY a JSON array of objects with no surrounding markdown formatting or backticks. Follow this exact schema:
[
  {
    "title": "Short catchy scene title",
    "summary": "1-2 sentence vivid summary of the visual action",
    "quote": "Direct quote from text capturing this instant",
    "visual_prompt": "Masterpiece black and white book illustration of [detailed visual description of characters, actions, setting, architecture, camera angle, lighting, and style]"
  }
]
]], title, author, (#description > 0 and ("Book context: " .. description) or ""), style_note)

    return prompt
end

-- Builds direct prompt for Single Selected Paragraph (Highlight Mode)
function PromptEngine:buildSingleScenePrompt(selected_text, book_info)
    local title = (book_info and book_info.title) or "Book"
    local author = (book_info and book_info.author) or "Author"
    local style_pref = self.settings:get("art_style") or "auto_genre"
    local style_guide = STYLE_MODIFIERS[style_pref]

    if not style_guide or #style_guide == 0 then
        style_guide = "High contrast black and white book illustration, atmospheric lighting, detailed ink line art, crisp shadows and highlights, masterpiece for e-ink display."
    end

    local prompt = string.format(
        "Scene from '%s' by %s: \"%s\". Visual composition: %s",
        title, author, selected_text:sub(1, 400), style_guide
    )
    return prompt
end

return PromptEngine
