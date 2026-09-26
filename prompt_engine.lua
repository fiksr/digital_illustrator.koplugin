--[[--
Smart Prompt Engine for Gemini AI Book Illustrator.
Constructs genre-aware, context-rich prompts optimized for monochrome E-Ink rendering.
--]]--

local PromptEngine = {}
PromptEngine.__index = PromptEngine

local STYLE_MODIFIERS = {
    engraving = "Victorian book illustration style, detailed copperplate engraving and ink etching, intricate cross-hatching, in the style of Gustave Doré and Albrecht Dürer, sharp black ink lines on off-white paper, high contrast, vertical composition, masterpiece.",
    comic_noir = "Graphic novel illustration style, dramatic comic noir ink drawing, heavy chiaroscuro lighting, bold ink shadows, crisp silhouettes, Frank Miller and Mike Mignola graphic novel aesthetic, monochromatic, high contrast, vertical composition.",
    woodcut = "Vintage woodblock and woodcut print style, bold folkloric lines, traditional relief printmaking aesthetic, stark monochromatic contrast, historic medieval and early modern woodcut art, vertical composition.",
    charcoal_sketch = "Detailed academic charcoal and graphite drawing, fine tonal gradients, textured paper grain, atmospheric sfumato shading, realistic classical book illustration, monochrome, vertical portrait composition.",
    cinematic_bw = "Cinematic 35mm black and white portrait photography still, dramatic film lighting, rich grayscale depth, Hasselblad monochrome portraiture, sharp focus, deep shadows and crisp highlights, vertical orientation.",
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
   - MANDATORY: VERTICAL PORTRAIT ORIENTATION ONLY (3:4 vertical aspect ratio, vertical composition, taller than wide, perfectly formatted for a vertical e-reader book screen). Never generate wide/horizontal/landscape scenes.
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
    "visual_prompt": "Vertical portrait 3:4 aspect ratio, masterpiece black and white book illustration of [detailed vertical visual description of characters, actions, setting, architecture, camera angle, lighting, and style]"
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
        style_guide = "High contrast black and white book illustration, atmospheric lighting, detailed ink line art, crisp shadows and highlights, masterpiece for vertical e-ink display."
    end

    local prompt = string.format(
        "Vertical portrait orientation, 3:4 aspect ratio. Scene from '%s' by %s: \"%s\". Visual composition: %s",
        title, author, selected_text:sub(1, 400), style_guide
    )
    return prompt
end

-- Builds prompt for Extracting Characters from Text (returns JSON array of characters)
function PromptEngine:buildCharacterAnalysisInstruction(book_info, enable_web_search)
    local title = (book_info and book_info.title) or "Unknown Book"
    local author = (book_info and book_info.author) or "Unknown Author"
    local description = (book_info and book_info.description) or ""
    local style_pref = self.settings:get("art_style") or "auto_genre"
    local style_note = STYLE_MODIFIERS[style_pref] or ""

    local web_note = enable_web_search and "You may use Google Search to verify canonical visual descriptions and appearance details for well-known literary characters, but DO NOT include future plot spoilers." or "Rely exclusively on physical descriptions and characteristics found in the provided text."

    local prompt = string.format([[
You are an expert literary visualizer, character analyst, and portrait art director.
The user is reading "%s" by %s. %s

Language & Processing Note:
- The book text may be in Serbian, Croatian, Bosnian, English, or other languages.
- Thoroughly analyze the text in its original language.
- Extract character names in their authentic original form / nominative case (e.g. "Petar", "Mihailo", "Vuk", "Geralt", "Jaskier", "Paul Atreides").

Your task:
1. Comprehensively scan the entire provided text and identify ALL distinct named characters (protagonists, antagonists, recurring allies, supporting characters, historical figures, and notable secondary characters). Extract up to 15 to 20 key characters if present in the text.
2. For each character, extract or deduce their exact physical appearance, facial structure, age, hair, eyes, facial hair/scars, body build, clothing/armor of the era, demeanor, and signature items.
3. %s
4. Construct a rich, masterpiece vertical portrait visual prompt for each character:
   - VERTICAL PORTRAIT COMPOSITION (3:4 aspect ratio, upper-body bust portrait framing).
   - Focused on facial details, expression, eyes, hair, and period clothing.
   - Dynamic chiaroscuro lighting, deep black shadows, and crisp highlights for 300 PPI E-Ink display.
   - %s
   - Strictly avoid future plot spoilers in the summary.

Output STRICTLY a JSON array of objects with no surrounding markdown formatting or backticks. Follow this exact schema:
[
  {
    "name": "Original Character Name (in Nominative Case)",
    "role": "Role (e.g. Protagonist / Glavni junak, Vojskovođa, Detektiv, Supruga)",
    "summary": "1-2 sentence non-spoiler summary of who they are and their role in the story",
    "visual_prompt": "Vertical portrait composition (3:4 aspect ratio, upper-body bust portrait), masterpiece character concept art of [Name], [age] years old, [detailed face, eyes, hair, expression, scars], wearing [authentic period attire/clothing], dramatic side chiaroscuro lighting, deep black shadows, stark monochromatic contrast, crisp linework, masterpiece for e-ink display."
  }
]
]], title, author, (#description > 0 and ("Book context: " .. description) or ""), web_note, style_note)

    return prompt
end

-- Builds prompt for Extracting Characters directly from Internet Search Grounding
function PromptEngine:buildInternetCharacterAnalysisInstruction(book_info)
    local title = (book_info and book_info.title) or "Unknown Book"
    local author = (book_info and book_info.author) or "Unknown Author"
    local description = (book_info and book_info.description) or ""
    local style_pref = self.settings:get("art_style") or "auto_genre"
    local style_note = STYLE_MODIFIERS[style_pref] or ""

    local prompt = string.format([[
You are an expert literary visualizer and character analyst equipped with Google Search.
The user is reading the book "%s" by %s. %s

Your task:
1. Use Google Search to look up the canonical character list, Wikipedia page, literary summary, character bios, and fandom entries for "%s" by %s.
2. Identify ALL major and important recurring characters (protagonists, antagonists, supporting characters, allies). Extract 15 to 20 key characters.
3. Language & Names:
   - If the book is originally or commonly known in Serbian, Croatian, Bosnian, or the edition is translated, output names in their authentic nominative form (e.g. "Petar", "Mihailo", "Geralt", "Viola", "Porša", "Paul Atreides").
   - Roles and summaries should be clear and concise.
4. For each character, deduce their exact canonical physical appearance, age, facial structure, eyes, hair, clothing/armor of their era/setting, demeanor, and signature traits.
5. Construct a rich 3:4 vertical portrait prompt:
   - VERTICAL PORTRAIT COMPOSITION (3:4 aspect ratio, upper-body bust portrait framing).
   - %s
   - Strictly avoid future plot spoilers.

Output STRICTLY a JSON array of objects with no surrounding markdown formatting or backticks:
[
  {
    "name": "Original Character Name (in Nominative Case)",
    "role": "Role (e.g. Protagonist / Glavni junak, Vojskovođa, Zapovednik dirižabla, Detektiv)",
    "summary": "1-2 sentence non-spoiler summary of who they are in the story",
    "visual_prompt": "Vertical portrait composition (3:4 aspect ratio, upper-body bust portrait), masterpiece character concept art of [Name], [age] years old, [detailed face, eyes, hair, expression, scars], wearing [authentic period attire/clothing], dramatic side chiaroscuro lighting, deep black shadows, stark monochromatic contrast, crisp linework, masterpiece for e-ink display."
  }
]
]], title, author, (#description > 0 and ("Context: " .. description) or ""), title, author, style_note)

    return prompt
end

return PromptEngine
