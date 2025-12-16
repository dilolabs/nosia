# Nosia UI Audit - Current State

**Date:** 2025-12-16  
**Purpose:** Document existing UI components before applying Medietilsynet branding

---

## 📁 File Structure

### Views
```
app/views/
├── layouts/
│   └── application.html.erb          # Main layout
├── application/
│   ├── _header.html.erb              # Top navigation bar
│   ├── _menu.html.erb                # Left sidebar + mobile bottom nav
│   ├── _navbar.html.erb              # Breadcrumb/secondary nav
│   ├── _sidebar.html.erb             # Right sidebar
│   ├── _search.html.erb              # Search modal
│   └── _flash.html.erb               # Flash messages
└── [various feature folders]/
```

### Stylesheets
```
app/assets/stylesheets/nosia/
├── main.css                          # Core styles & animations
├── button.css                        # Button variants
├── card.css                          # Card components
├── form.css                          # Form elements
├── menu.css                          # Navigation styles
└── tag.css                           # Tag/badge components
```

---

## 🎨 Current Color Scheme

### Primary Colors
- **Green:** Main brand color (CTAs, hover states, focus)
  - Light: `green-200` → `green-400`
  - Dark: `green-700` → `green-900`
  
- **Neutral:** Backgrounds, borders, text
  - Light: `neutral-100` → `neutral-500`
  - Dark: `neutral-700` → `neutral-900`

### Semantic Colors
- **Red:** Danger/error states
- **Orange:** Tertiary actions
- **Blue:** Links and info
- **Pink:** Code highlighting

---

## 🧩 Component Classes

### Custom Nosia Classes

#### Background & Borders
- `.n-main-bg` → `bg-neutral-200 dark:bg-neutral-800`
- `.n-main-border` → `border-neutral-200 dark:border-neutral-700`

#### Interactive States
- `.n-main-hover` → Green hover: `hover:bg-green-200 dark:hover:bg-green-800`
- `.n-main-hover-danger` → Red hover
- `.n-main-hover-tertiary` → Orange hover

#### Focus States
- `.n-main-focus` → Green outline: `focus:outline-green-500`
- `.n-main-focus-danger` → Red outline
- `.n-main-focus-tertiary` → Orange outline

#### Navigation
- `.n-nav-link` → Navigation link style
- `.n-nav-bottom` → Mobile bottom navigation
- `.n-btn-drawer` → Drawer toggle button

#### Buttons
- `.n-btn` → Base button
- `.n-btn-primary` → Primary action (green)
- `.n-btn-danger` → Destructive action (red)
- `.n-btn-chat` → Chat-specific button
- `.n-btn-icon` → Icon button

#### Tabs
- `.n-tab` → Inactive tab
- `.n-tab-active` → Active tab with green underline

---

## 🏗️ Layout Structure

### Header (`_header.html.erb`)
```
┌─────────────────────────────────────┐
│ [Logo]        [Search] [Theme] [User]│
└─────────────────────────────────────┘
```
- Logo (nosia-logo.png) in top left
- Search, theme toggle, user menu in top right
- Fixed height: `h-16`
- Border bottom: `.n-main-border`

### Menu (`_menu.html.erb`)
**Desktop:** Left sidebar with collapsible labels
```
┌──────┐
│ [≡]  │ Menu toggle
│ [🏠] │ Home
│ [📁] │ Accounts
│ [🔍] │ Sources
└──────┘
```

**Mobile:** Bottom navigation bar (rounded pill)
```
┌───────────────────────────────────────┐
│ [🏠]  [📁]  [💬]  [🔍]  [⚙️]         │
└───────────────────────────────────────┘
```

### Main Content Area
- Scrollable: `overflow-y-auto`
- Padding: `pl-6 pt-6 pr-2 lg:p-6`
- Full height minus header: `h-[calc(100dvh-4rem)]`

### Right Sidebar (`_sidebar.html.erb`)
- Desktop: Fixed width `w-72`
- Mobile: Drawer overlay `w-80`
- Collapsible with accordion

---

## 🎯 Key UI Patterns

### 1. **Dark Mode Support**
- Controlled by `data-controller="dark-mode"`
- Class toggle on `<body>`: `dark:` prefix in Tailwind
- Theme toggle button in header

### 2. **Responsive Design**
- Breakpoints: `sm`, `md`, `lg`
- Desktop: sidebar navigation
- Mobile: bottom tab bar + drawer menus

### 3. **Interactive States**
- Hover: Green background tint
- Focus: Green outline
- Transitions: 200ms duration

### 4. **Accessibility**
- `sr-only` for screen reader text
- ARIA labels on buttons
- Keyboard navigation support
- Focus indicators

---

## 🎨 Animation & Effects

### Animations (from main.css)
- `fadeInOut` → Thinking phases
- `messageSlideIn` → New messages
- `intermediateMessageFade` → Tool calls
- `subtlePulse` → Thinking indicator
- `spin` → Loading spinners

### Scrollbar Styling
- Thin scrollbars (8px)
- Neutral colors
- Rounded thumbs
- Visible on hover

---

## 🔄 What Needs to Change for Medietilsynet

### 1. **Colors**
| Current (Green) | Medietilsynet (Blue) |
|-----------------|----------------------|
| `green-200` → `green-900` | `#0c5da4` (brand blue) |
| Hover: Green | Hover: Darker blue |
| Focus: Green outline | Focus: Blue outline |

### 2. **Typography**
| Current | Medietilsynet |
|---------|---------------|
| System fonts | Graphik Web (primary) |
| Generic sizes | 18px base, defined scale |

### 3. **Logo**
- Replace `nosia-logo.png` with Medietilsynet logo
- Ensure proper sizing and spacing

### 4. **Component Styles**
- Update `.n-main-hover` → Blue instead of green
- Update `.n-main-focus` → Blue outline
- Update `.n-btn-primary` → Blue background
- Update `.n-tab-active` → Blue underline

### 5. **Border Radius**
- Current: Default Tailwind
- Medietilsynet: 3px (subtle) or 35px (pill)

### 6. **Spacing**
- Continue using Tailwind's 8px-based system
- Ensure consistency with Medietilsynet patterns

---

## ✅ What's Already Good

- ✅ **8px-based spacing** (aligns with Medietilsynet)
- ✅ **Dark mode infrastructure** (need blue variant)
- ✅ **Accessibility features** (SR text, ARIA, focus)
- ✅ **Responsive design** (desktop/mobile patterns)
- ✅ **Component organization** (modular CSS files)
- ✅ **Professional animations** (smooth, subtle)

---

## 📋 Implementation Priority

### Phase 1: Color System (Highest Priority)
1. Update Tailwind config (✅ Done)
2. Replace `.n-main-hover` classes
3. Replace `.n-main-focus` classes
4. Update button variants
5. Update tab styles

### Phase 2: Typography
1. Load Graphik Web font
2. Apply to body and headings
3. Set base font size to 18px
4. Update heading styles

### Phase 3: Visual Assets
1. Replace Nosia logo
2. Update favicon
3. Add Medietilsynet branding elements

### Phase 4: Component Refinement
1. Border radius adjustments
2. Spacing fine-tuning
3. Dark mode blue theme
4. High-contrast variant

---

## 🛠️ Technical Notes

### CSS Architecture
- Using Tailwind `@apply` directives
- Custom classes prefixed with `n-`
- Dark mode with `class` strategy (not `media`)

### Font Loading
Need to add Graphik Web:
```html
<link rel="preconnect" href="https://fonts.googleapis.com">
<!-- Or self-host if available -->
```

### Logo Dimensions
Current: `h-8` (32px height)
Consider: Medietilsynet logo aspect ratio

---

**Next Step:** Apply Medietilsynet design system to these components
