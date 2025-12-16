# Medietilsynet Design System

**Extracted from:** https://www.medietilsynet.no/  
**Date:** 2025-12-16  
**Tool:** Dembrandt v0.5.1

---

## 🎨 Color Palette

### Primary Colors

| Name | Hex | RGB | Usage | Confidence |
|------|-----|-----|-------|------------|
| **Dark Gray** | `#393939` | rgb(57, 57, 57) | Primary text, headings | High (385 instances) |
| **White** | `#ffffff` | rgb(255, 255, 255) | Backgrounds, light text | High (211 instances) |
| **Blue** | `#0000ee` | rgb(0, 0, 238) | Links, interactive elements | High (116 instances) |
| **Brand Blue** | `#0c5da4` | rgb(12, 93, 164) | Brand accent, CTA buttons | High (66 instances) |
| **Medium Gray** | `#808080` | rgb(128, 128, 128) | Secondary text, borders | High (64 instances) |
| **Black** | `#000000` | rgb(0, 0, 0) | Pure black accents | Medium (14 instances) |

### Border Colors

| Name | Hex | RGB | Usage |
|------|-----|-----|-------|
| **Light Gray** | `#dddddd` | rgb(221, 221, 221) | Subtle borders, dividers |
| **Medium Gray** | `#808080` | rgb(128, 128, 128) | Emphasized borders |

---

## 📝 Typography

### Font Families

- **Primary:** `Graphik Web` (sans-serif)
- **Secondary:** `Merriweather` (serif - mentioned but not in tokens)
- **Accent:** `Play` (mentioned but not in tokens)

### Typography Styles

#### Heading 1
- **Font:** Graphik Web
- **Size:** 18px
- **Weight:** 700 (Bold)

#### Link Text
- **Font:** Graphik Web
- **Size:** 18px
- **Weight:** 400 (Regular)

#### Button Text
- **Font:** Graphik Web
- **Size:** 18px
- **Weight:** 400 (Regular)
- **Line Height:** 1.56

---

## 📏 Spacing System

Based on an 8px grid system with additional granular values:

| Token | Value | Common Usage |
|-------|-------|--------------|
| spacing-1 | 1px | Hairline spacing |
| spacing-2 | 3px | Minimal padding |
| spacing-3 | 4px | Tight spacing |
| spacing-4 | 5px | Small gaps |
| spacing-5 | 7px | Compact spacing |
| spacing-6 | **8px** | **Base unit** |
| spacing-7 | 9px | Slightly larger |
| spacing-8 | 10px | Medium spacing |
| spacing-9 | 10.5px | Fine-tuned |
| spacing-10 | 10.8px | Fine-tuned |
| spacing-11 | 12px | Comfortable spacing |
| spacing-12 | 15px | Generous spacing |

**Recommended Scale:**
- Use 8px (spacing-6) as the base multiplier
- Common values: 8px, 16px, 24px, 32px, 40px, 48px

---

## 🔲 Border Radius

| Token | Value | Usage |
|-------|-------|-------|
| radius-1 | 3px | Subtle rounding (buttons, inputs) |
| radius-2 | 35px | Pill-shaped elements |

---

## 🖼️ Borders

### Border Widths
- **Default:** 1px
- **None:** 0px

### Border Colors
- **Light borders:** `#dddddd`
- **Emphasis borders:** `#808080`

---

## 📱 Breakpoints

26 breakpoints detected, ranging from:
- **Maximum:** 1520px
- **Minimum:** 480px

**Recommended responsive breakpoints:**
- Mobile: 480px
- Tablet: 768px
- Desktop: 1024px
- Large: 1280px
- XL: 1520px

---

## 🎯 Component Patterns

### Buttons
4 button variants detected:
- Primary (Brand Blue background)
- Secondary (outlined or gray)
- Link-style buttons
- Icon buttons

### Links
4 link styles detected:
- Default links (Blue `#0000ee`)
- Hover state (Brand Blue `#0c5da4`)
- Visited links
- Button-styled links

### Icons
- **System:** SVG Icons
- **Style:** Inline SVG elements

---

## ♿ Accessibility Notes

### Color Contrast
- **Dark Gray (`#393939`) on White:** ✅ Passes WCAG AAA
- **Brand Blue (`#0c5da4`) on White:** ✅ Passes WCAG AA (needs testing for AAA)
- **Pure Blue (`#0000ee`) on White:** ⚠️ May need adjustment for WCAG AAA

### Recommendations
- Ensure minimum contrast ratio of 4.5:1 for normal text
- Aim for 7:1 for AAA compliance
- Test all color combinations with a contrast checker

---

## 🎨 Design Principles

Based on the extracted tokens, Medietilsynet's design system emphasizes:

1. **Clarity:** High contrast between text and backgrounds
2. **Simplicity:** Minimal color palette focused on blues and grays
3. **Professionalism:** Conservative, government-appropriate styling
4. **Accessibility:** Strong contrast, readable typography
5. **Consistency:** 8px-based spacing system

---

## 📦 Source Data

Raw design tokens available in:
`/Medietilsynet/output/medietilsynet.no/2025-12-16T09-29-33-746Z.tokens.json`

W3C Design Tokens Community Group (DTCG) format
