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
- 📑 **Flexible Trigger Modes**:
  - **Scan Entire Chapter**: AI-curated scene selection menu with quotes.
  - **Custom Page Range**: Scan specific passages (e.g. pages 15–28).
  - **Current Page**: Directly visualize the open page.
  - **Highlight Selection**: Select any paragraph $\rightarrow$ tap **✨ Gemini Illustrate** in the popup menu.
- 🖋️ **Genre-Aware & E-Ink Optimized Prompt Engine**:
  - Reads book title, author, and synopsis to automatically calibrate tone (Sci-Fi, Dark Fantasy, Cyberpunk, Gothic Horror, Historical Drama, Noir).
  - Enforces high-contrast chiaroscuro, crisp linework, and deep blacks for monochrome 300 PPI E-Ink readability.
  - Art style presets: *Victorian Engraving & Ink (Doré/Dürer)*, *Graphic Novel Comic Noir*, *Vintage Woodcut*, *Charcoal & Pencil Sketch*, *Cinematic B&W*.
- 🚀 **Kindle Performance & Fast Mode**:
  - Configurable resolutions: `768x1024 (Fast - Recommended)`, `896x1152 (Balanced)`, `1024x1365 (HD)`, `1272x1696 (Native 300 PPI)`.
  - Instant background base64 decoding via native Linux command.
- 🖼️ **One-Click Actions**:
  - Fullscreen `ImageViewer` with zoom and pan.
  - **Set as Screensaver**: Saves image directly to Kindle screensavers directory.
  - **Set as Book Cover**: Sets image as custom cover for current book.

---

## 📦 Installation

1. Copy the `gemini_illustrator.koplugin` folder to your KOReader plugins directory:
   ```bash
   /mnt/us/koreader/plugins/gemini_illustrator.koplugin
   ```
2. Restart KOReader.

---

## 🔑 API Keys Setup

1. **Google Gemini Key (Required for Text Brain)**:
   - Get a free key from [Google AI Studio](https://aistudio.google.com/).
   - Place in `/mnt/us/gemini_token.txt` on your Kindle root drive.
2. **Optional Image Provider Keys**:
   - **Pollinations**: No key required! ($0.00 Free).
   - **Fal.ai**: Place key in `/mnt/us/fal_token.txt`.
   - **OpenAI**: Place key in `/mnt/us/openai_token.txt`.
3. In KOReader $\rightarrow$ **AI Book Illustrator** $\rightarrow$ **Settings** $\rightarrow$ **Import Keys from Kindle Files**.

---

## 📄 License
MIT License
