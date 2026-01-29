#include "overlaymanager.h"
#include "path.h"

using namespace Overlay;

OverlayManager::OverlayManager() :
    m_Renderer(nullptr),
    m_RendererLock(SDL_CreateMutex()),
    m_FontData(Path::readDataFile("ModeSeven.ttf")),
    m_FontSymbolData(Path::readDataFile("FontAwesome.otf"))
{
    memset(m_Overlays, 0, sizeof(m_Overlays));

    m_Overlays[OverlayType::OverlayDebug].color = {0xD0, 0xD0, 0x00, 0xFF};
    m_Overlays[OverlayType::OverlayDebug].fontSize = 20;

    m_Overlays[OverlayType::OverlayStatusUpdate].color = {0xCC, 0x00, 0x00, 0xFF};
    m_Overlays[OverlayType::OverlayStatusUpdate].fontSize = 36;

    // While TTF will usually not be initialized here, it is valid for that not to
    // be the case, since Session destruction is deferred and could overlap with
    // the lifetime of a new Session object.
    //SDL_assert(TTF_WasInit() == 0);

    if (TTF_Init() != 0) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "TTF_Init() failed: %s",
                    TTF_GetError());
        return;
    }
}

OverlayManager::~OverlayManager()
{
    for (int i = 0; i < OverlayType::OverlayMax; i++) {
        if (m_Overlays[i].surface != nullptr) {
            SDL_FreeSurface(m_Overlays[i].surface);
        }
        if (m_Overlays[i].font != nullptr) {
            TTF_CloseFont(m_Overlays[i].font);
        }
        if (m_Overlays[i].fontSymbol != nullptr) {
            TTF_CloseFont(m_Overlays[i].fontSymbol);
        }
    }

    TTF_Quit();
    
    SDL_DestroyMutex(m_RendererLock);

    // For similar reasons to the comment in the constructor, this will usually,
    // but not always, deinitialize TTF. In the cases where Session objects overlap
    // in lifetime, there may be an additional reference on TTF for the new Session
    // that means it will not be cleaned up here.
    //SDL_assert(TTF_WasInit() == 0);
}

bool OverlayManager::isOverlayEnabled(OverlayType type)
{
    return m_Overlays[type].enabled;
}

char* OverlayManager::getOverlayText(OverlayType type)
{
    return m_Overlays[type].text;
}

void OverlayManager::updateOverlayText(OverlayType type, const char* text)
{
    SDL_strlcpy(m_Overlays[type].text, text, sizeof(m_Overlays[0].text));

    setOverlayTextUpdated(type);
}

int OverlayManager::getOverlayMaxTextLength()
{
    return sizeof(m_Overlays[0].text);
}

int OverlayManager::getOverlayFontSize(OverlayType type)
{
    return m_Overlays[type].fontSize;
}

SDL_Surface* OverlayManager::getUpdatedOverlaySurface(OverlayType type)
{
    // If a new surface is available, return it. If not, return nullptr.
    // Caller must free the surface on success.
    return (SDL_Surface*)SDL_AtomicSetPtr((void**)&m_Overlays[type].surface, nullptr);
}

void OverlayManager::setOverlayTextUpdated(OverlayType type)
{
    // Only update the overlay state if it's enabled. If it's not enabled,
    // the renderer has already been notified by setOverlayState().
    if (m_Overlays[type].enabled) {
        notifyOverlayUpdated(type);
    }
}

void OverlayManager::setOverlayState(OverlayType type, bool enabled)
{
    bool stateChanged = m_Overlays[type].enabled != enabled;

    m_Overlays[type].enabled = enabled;

    if (stateChanged) {
        if (!enabled) {
            // Set the text to empty string on disable
            m_Overlays[type].text[0] = 0;
        }

        notifyOverlayUpdated(type);
    }
}

SDL_Color OverlayManager::getOverlayColor(OverlayType type)
{
    return m_Overlays[type].color;
}

void OverlayManager::setOverlayRenderer(IOverlayRenderer* renderer)
{
    SDL_LockMutex(m_RendererLock);
    m_Renderer = renderer;
    SDL_UnlockMutex(m_RendererLock);
}

void OverlayManager::notifyOverlayUpdated(OverlayType type)
{
    SDL_LockMutex(m_RendererLock);

    if (m_Renderer == nullptr) {
        SDL_UnlockMutex(m_RendererLock);
        return;
    }

    // Construct the required font to render the overlay
    if (m_Overlays[type].font == nullptr) {
        if (m_FontData.isEmpty() || m_FontSymbolData.isEmpty()) {
            SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                         "SDL overlay font failed to load");
            SDL_UnlockMutex(m_RendererLock);
            return;
        }

        // m_FontData must stay around until the font is closed
        m_Overlays[type].font = TTF_OpenFontRW(SDL_RWFromConstMem(m_FontData.constData(), m_FontData.size()),
                                               1,
                                               m_Overlays[type].fontSize);
        m_Overlays[type].fontSymbol = TTF_OpenFontRW(SDL_RWFromConstMem(m_FontSymbolData.constData(), m_FontSymbolData.size()),
                                               1,
                                               m_Overlays[type].fontSize);

        if (m_Overlays[type].font == nullptr || m_Overlays[type].fontSymbol == nullptr) {
            SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                        "TTF_OpenFont() failed: %s",
                        TTF_GetError());

            // Can't proceed without a font
            SDL_UnlockMutex(m_RendererLock);
            return;
        }

        // Enable hinting for sharper text at small sizes
        TTF_SetFontHinting(m_Overlays[type].font, TTF_HINTING_LIGHT);
        TTF_SetFontHinting(m_Overlays[type].fontSymbol, TTF_HINTING_LIGHT);
    }

    SDL_Surface* oldSurface = (SDL_Surface*)SDL_AtomicSetPtr((void**)&m_Overlays[type].surface, nullptr);

    // Free the old surface
    if (oldSurface != nullptr) {
        SDL_FreeSurface(oldSurface);
    }

    if (m_Overlays[type].enabled) {
        // Manually implement font fallback rendering
        int lineSkip = TTF_FontLineSkip(m_Overlays[type].font);
        
        // Calculate total dimensions
        int maxLineWidth = 0;
        int currentLineWidth = 0;
        int totalHeight = lineSkip;
        const char* ptr = m_Overlays[type].text;
        
        while (*ptr) {
            Uint32 ch;
            int len = 0;
            
            // Get next UTF-8 character
            if ((*ptr & 0x80) == 0) {
                ch = *ptr;
                len = 1;
            }
            else if ((*ptr & 0xE0) == 0xC0) {
                ch = ((*ptr & 0x1F) << 6) | (*(ptr + 1) & 0x3F);
                len = 2;
            }
            else if ((*ptr & 0xF0) == 0xE0) {
                ch = ((*ptr & 0x0F) << 12) | ((*(ptr + 1) & 0x3F) << 6) | (*(ptr + 2) & 0x3F);
                len = 3;
            }
            else {
                ch = ((*ptr & 0x07) << 18) | ((*(ptr + 1) & 0x3F) << 12) | ((*(ptr + 2) & 0x3F) << 6) | (*(ptr + 3) & 0x3F);
                len = 4;
            }
            
            if (ch == '\n') {
                if (currentLineWidth > maxLineWidth) maxLineWidth = currentLineWidth;
                currentLineWidth = 0;
                totalHeight += lineSkip;
                ptr += len;
                continue;
            }
            
            TTF_Font* fontToUse = m_Overlays[type].font;
            if (ch >= 0xE000 && ch <= 0xF8FF) { // Private Use Area where FontAwesome icons live
                fontToUse = m_Overlays[type].fontSymbol;
            }
            
            int minx, maxx, miny, maxy, advance;
            if (TTF_GlyphMetrics(fontToUse, ch, &minx, &maxx, &miny, &maxy, &advance) == 0) {
                currentLineWidth += advance;
            }
            else {
                // Fallback width calculation if metrics fail
                // We render a temp glyph to measure it
                SDL_Surface* tempGlyph = TTF_RenderGlyph_Blended(fontToUse, ch, m_Overlays[type].color);
                if (tempGlyph) {
                    currentLineWidth += tempGlyph->w;
                    SDL_FreeSurface(tempGlyph);
                }
            }
            
            ptr += len;
        }
        if (currentLineWidth > maxLineWidth) maxLineWidth = currentLineWidth;
        
        // Ensure valid surface dimensions
        if (maxLineWidth == 0) maxLineWidth = 1;
        if (totalHeight == 0) totalHeight = 1;
        
        // Create the surface
        SDL_Surface* surface = SDL_CreateRGBSurfaceWithFormat(0, maxLineWidth, totalHeight, 32, SDL_PIXELFORMAT_ARGB8888);
        
        // Render pass
        int currentX = 0;
        int currentY = 0;
        ptr = m_Overlays[type].text;
        
        while (*ptr) {
            Uint32 ch;
            int len = 0;
            
            if ((*ptr & 0x80) == 0) { ch = *ptr; len = 1; }
            else if ((*ptr & 0xE0) == 0xC0) { ch = ((*ptr & 0x1F) << 6) | (*(ptr + 1) & 0x3F); len = 2; }
            else if ((*ptr & 0xF0) == 0xE0) { ch = ((*ptr & 0x0F) << 12) | ((*(ptr + 1) & 0x3F) << 6) | (*(ptr + 2) & 0x3F); len = 3; }
            else { ch = ((*ptr & 0x07) << 18) | ((*(ptr + 1) & 0x3F) << 12) | ((*(ptr + 2) & 0x3F) << 6) | (*(ptr + 3) & 0x3F); len = 4; }
            
            if (ch == '\n') {
                currentX = 0;
                currentY += lineSkip;
                ptr += len;
                continue;
            }
            
            TTF_Font* fontToUse = m_Overlays[type].font;
             if (ch >= 0xE000 && ch <= 0xF8FF) {
                 fontToUse = m_Overlays[type].fontSymbol;
             }
             
             SDL_Surface* glyph = TTF_RenderGlyph_Blended(fontToUse, ch, m_Overlays[type].color);
             if (glyph) {
                 SDL_Rect dstRect = { currentX, currentY, 0, 0 };
                 SDL_BlitSurface(glyph, NULL, surface, &dstRect);
                 
                 // Use glyph advance for accurate spacing
                 int minx, maxx, miny, maxy, advance;
                 if (TTF_GlyphMetrics(fontToUse, ch, &minx, &maxx, &miny, &maxy, &advance) == 0) {
                      currentX += advance;
                 }
                 else {
                      // Fallback if metrics fail
                      currentX += glyph->w;
                 }
                 
                 SDL_FreeSurface(glyph);
             }
             
             ptr += len;
         }
         
         SDL_AtomicSetPtr((void**)&m_Overlays[type].surface, surface);
     }

    // Notify the renderer
    m_Renderer->notifyOverlayUpdated(type);

    SDL_UnlockMutex(m_RendererLock);
}
