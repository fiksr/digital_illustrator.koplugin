# 📖 Gemini AI Book Illustrator for KOReader
> **`gemini_illustrator.koplugin`** — Intelligent, genre-aware scene visualization and chapter art generator powered by Google Gemini (2026 models) and optimized for E-Ink displays.

---

## ✨ Features

- 🧠 **Chapter Brain (Scene Suggestions)**:
  - Automatically identifies chapter boundaries using Table of Contents (TOC).
  - Analyzes the full chapter and extracts **3 to 4 dramatic, visually striking scenes** complete with titles and direct book quotes.
- 📑 **Flexible Trigger Modes**:
  - **Scan Entire Chapter**: AI-curated scene selection menu.
  - **Custom Page Range**: Scan specific passages (e.g. pages 15–28).
  - **Current Page**: Directly visualize the open page.
  - **Highlight Selection**: Select any paragraph $\rightarrow$ tap **✨ Gemini Illustrate** in the popup menu.
- ⚡ **2026 Google Gemini Models**:
  - **Text Brain**: `gemini-3.1-flash-lite` (**500 Requests/Day high-quota limit**), `gemini-3.8-flash`, `gemini-2.5-flash`, `gemini-2.0-flash`, `gemini-2.5-pro`.
  - **Image Generation**: `gemini-3.1-flash-lite-image` (*Nano Banana 2 Lite - 2.7x faster*), `gemini-3.1-flash-image` (*Nano Banana 2*), `gemini-3-pro-image` (*Nano Banana Pro*), `imagen-4.0-generate-001`, `imagen-3.0-generate-002`.
- 🎨 **Genre-Aware & E-Ink Optimized Prompt Engine**:
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

## 🔑 API Key Setup

1. Get a free API key from [Google AI Studio](https://aistudio.google.com/).
2. **Easy setup**: Create a file named `gemini_token.txt` on your Kindle root directory (`/mnt/us/gemini_token.txt`) containing your API key.
3. Open KOReader $\rightarrow$ **AI Book Illustrator** $\rightarrow$ **Settings** $\rightarrow$ **Import Key from /mnt/us/gemini_token.txt**.

---

## ⚙️ Configuration

Inside KOReader, navigate to **AI Book Illustrator** $\rightarrow$ **Settings**:
- **Text / Analysis Model**: Choose between `gemini-3.1-flash-preview` (500 RPD), `gemini-3.8-flash`, etc.
- **Image Model**: Choose between `gemini-3.1-flash-image`, `gemini-3-pro-image`, `imagen-4.0`.
- **Art Style & Resolution**: Pick your preferred visual style and resolution.

---

## 📄 License
MIT License
