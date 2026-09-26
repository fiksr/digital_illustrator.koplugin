# 📖 Gemini AI Book Illustrator for KOReader
> **`gemini_illustrator.koplugin`** — Intelligent, genre-aware scene visualization and chapter art generator powered by Google Gemini (Text & Chapter Brain) with multi-backend image generation (Pollinations Free, Fal.ai FLUX, Google Nano Banana, OpenAI DALL-E 3) optimized for E-Ink displays.

---

## ✨ Features

- 🧠 **Gemini Chapter Brain (100% Free Text Analysis)**:
  - Powered by **Google Gemini 3.1 Flash Lite** (500 Requests/Day Free Tier).
  - Automatically identifies chapter boundaries using Table of Contents (TOC) and XPointers.
  - Analyzes the full chapter and extracts **3 to 4 dramatic, visually striking scenes** complete with titles and direct book quotes.
- 🎨 **Multi-Provider Image Backends**:
  - 🌸 **Pollinations Flux.1**: **$0.00 (100% Free)** — No API key needed, unlimited generations.
  - ⚡ **Fal.ai FLUX.1 [schnell]**: **$0.003 / image** (~333 images for $1, 1-second generation).
  - 🎨 **Fal.ai FLUX.1 [dev]**: **$0.025 / image** (~40 images for $1, maximum photorealism).
  - 🍌 **Google Nano Banana 2 Lite**: **$0.07 / image** (`gemini-3.1-flash-lite-image`).
  - 🍌 **Google Nano Banana 2**: **$0.10 / image** (`gemini-3.1-flash-image`).
  - 🍌 **Google Nano Banana Pro**: **~$0.13 / image** (`gemini-3-pro-image`).
  - 🖼️ **Google Imagen 4.0 / 3.0**: **$0.04 – $0.08 / image** (`imagen-4.0-generate-001`).
  - 🤖 **OpenAI DALL-E 3**: **$0.04 – $0.08 / image** (`dall-e-3`).
- 🎭 **AI Cast of Characters (Concept Art & Portrets)**:
  - **Chapter Cast**: Scans characters in the active chapter and builds a character gallery.
  - **Full Book Cast**: Gathers all characters met up to your current reading progress with non-spoiler summaries.
  - **Master Bust Portraits**: Generates vertical (3:4) upper-body portraits with facial features, period attire, and dramatic chiaroscuro lighting.
  - **🌐 Optional Google Search Grounding**: Toggle online search in settings to cross-reference canonical appearances from official wikis.
- 📑 **Flexible Trigger Modes**:
  - **Scan Entire Chapter**: AI-curated scene selection menu with quotes and 0-second persistent caching.
  - **Custom Page Range**: Scan specific passages (e.g. pages 15–28).
  - **Current Page**: Directly visualize the open page.
  - **Highlight Selection**: Select any paragraph $\rightarrow$ tap **✨ Gemini Illustrate** in the popup menu.
- 🖋️ **Genre-Aware & E-Ink Optimized Prompt Engine**:
  - Strict **Vertical Portrait Orientation (3:4 aspect ratio)** calibration.
  - Enforces high-contrast chiaroscuro, crisp linework, and deep blacks for monochrome 300 PPI E-Ink readability.
  - Art style presets: *Victorian Engraving & Ink (Doré/Dürer)*, *Graphic Novel Comic Noir*, *Vintage Woodcut*, *Charcoal & Pencil Sketch*, *Cinematic B&W*.
- 🚀 **Kindle Performance & Fast Mode**:
  - Configurable resolutions: `768x1024 (Fast - Recommended)`, `896x1152 (Balanced)`, `1024x1365 (HD)`, `1272x1696 (Native 300 PPI)`.
  - Instant background base64 decoding via native Linux command.
- 📱 **Instant Phone QR Code Pairing (Local Wi-Fi Server)**:
  - Tap **📱 Pair with Phone (Scan QR Code)** in settings.
  - Scan the QR code with your mobile camera $\rightarrow$ opens a sleek dark-mode web setup page.
  - Paste all your API keys at once and tap **"Send & Save to Kindle"**.
  - Transferred 100% locally and securely over your home Wi-Fi (no external servers needed).
- 📁 **Visual File Browser (`PathChooser`)**:
  - Browse storage on Kindle to select any `.txt` or `.key` file with automatic provider detection (Gemini `AIza...`, OpenAI `sk-...`, Fal.ai).
- 🖼️ **Saved Illustrations Gallery & Export**:
  - **Saved Illustrations Gallery**: Browse and open all previously generated illustrations with full metadata.
  - **Set as Screensaver**: Direct export to `/mnt/us/screensavers/`.
  - **Set as Book Cover**: Custom cover integration into KOReader book metadata.
  - **Export to Pictures**: Save directly to `/mnt/us/pictures/`.

---

## 📦 Installation

1. Copy the `gemini_illustrator.koplugin` folder to your KOReader plugins directory:
   ```bash
   /mnt/us/koreader/plugins/gemini_illustrator.koplugin
   ```
2. Restart KOReader.

---

## 🔑 3 Easy Ways to Set Up API Keys

1. **📱 Method 1: Phone QR Code (Recommended - Fastest)**:
   - Open plugin menu $\rightarrow$ **🔑 API Keys & Connection Test** $\rightarrow$ **📱 Pair with Phone (Scan QR Code)**.
   - Scan the QR code with your phone and paste your keys.
2. **📁 Method 2: Visual File Browser**:
   - Tap **📁 Browse Storage for Key File (*.txt)...** and pick any text file.
3. **📄 Method 3: USB Text File Import**:
   - Place `gemini_token.txt`, `fal_token.txt`, or `openai_token.txt` on your Kindle root drive (`/mnt/us/`).
   - Tap **⚡ Quick Import from /mnt/us/*.txt**.

---

## 📄 License
MIT License
